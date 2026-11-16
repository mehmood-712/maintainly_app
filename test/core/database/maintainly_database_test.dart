import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/core/database/maintainly_database.dart';
import 'package:maintainly/core/database/maintainly_schema.dart';

void main() {
  // Each test gets exactly one database instance and one independent in-memory
  // executor. This avoids creating unused databases in the migration test and
  // prevents Drift's duplicate-database warning from obscuring real issues.
  MaintainlyDatabase createDatabase({int? seedSchemaVersion}) {
    final executor = NativeDatabase.memory(
      setup: seedSchemaVersion == null
          ? null
          : (database) {
              final legacyVersion = seedSchemaVersion;
              if (legacyVersion >= 2) {
                for (final statement in MaintainlySchema.createV2Statements) {
                  database.execute(statement);
                }
              }
              if (legacyVersion >= 3) {
                database.execute(MaintainlySchema.createV3MigrationLedger);
              }
              if (legacyVersion >= 4) {
                database.execute(
                  'ALTER TABLE maintenance_reminders ADD COLUMN source_service_id TEXT NULL REFERENCES service_records (id) ON DELETE CASCADE',
                );
                database.execute(
                  'CREATE UNIQUE INDEX IF NOT EXISTS idx_maintenance_reminders_source_service ON maintenance_reminders (source_service_id) WHERE source_service_id IS NOT NULL',
                );
              }
              database.execute('PRAGMA user_version = $legacyVersion');
            },
    );
    final instance = MaintainlyDatabase(
      connection: DatabaseConnection(executor),
    );
    addTearDown(instance.close);
    return instance;
  }

  test('opens SQLite and exposes the engine version', () async {
    final database = createDatabase();
    await database.open();

    expect(await database.sqliteVersion, isNotEmpty);
  });

  test('creates all current tables and indexes on a new database', () async {
    final database = createDatabase();
    await database.open();

    expect(await database.currentSchemaVersion, MaintainlySchema.version);

    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tableNames = tables.map((row) => row.read<String>('name')).toSet();
    expect(tableNames, containsAll(MaintainlySchema.tableNames));

    final indexes = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
    expect(
      indexNames,
      containsAll([
        'idx_service_records_vehicle_date',
        'idx_vehicle_expenses_vehicle_date',
        'idx_vehicle_expenses_category_date',
        'idx_maintenance_reminders_vehicle',
        'idx_maintenance_reminders_open_due_date',
        'idx_maintenance_reminders_open_due_odometer',
        'idx_maintenance_reminders_source_service',
        'idx_vehicle_expenses_source_service',
      ]),
    );
  });

  test(
    'upgrades a Step 1 schema v1 database to the current schema v5',
    () async {
      // Seed the legacy schema version during native SQLite initialization.
      // This test creates only the database it uses, with no extra setUp DB.
      final upgradedDatabase = createDatabase(seedSchemaVersion: 1);

      await upgradedDatabase.open();

      expect(
        await upgradedDatabase.currentSchemaVersion,
        MaintainlySchema.version,
      );
      final tables = await upgradedDatabase
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((row) => row.read<String>('name')).toSet();
      expect(tableNames, containsAll(MaintainlySchema.tableNames));
    },
  );

  test('upgrades a schema v2 database through the current schema', () async {
    final upgradedDatabase = createDatabase(seedSchemaVersion: 2);
    await upgradedDatabase.open();

    expect(await upgradedDatabase.currentSchemaVersion, 5);
    final row = await upgradedDatabase
        .customSelect(
          "SELECT COUNT(*) AS row_count FROM sqlite_master "
          "WHERE type = 'table' AND name = 'maintainly_migrations'",
        )
        .getSingle();
    expect(row.read<int>('row_count'), 1);
  });

  test(
    'upgrades schema v3 through reminder and data-integrity migrations',
    () async {
      final upgradedDatabase = createDatabase(seedSchemaVersion: 3);
      await upgradedDatabase.open();

      expect(await upgradedDatabase.currentSchemaVersion, 5);
      final columns = await upgradedDatabase
          .customSelect('PRAGMA table_info(maintenance_reminders)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('source_service_id'),
      );
      final index = await upgradedDatabase
          .customSelect(
            "SELECT COUNT(*) AS row_count FROM sqlite_master WHERE type = 'index' AND name = 'idx_maintenance_reminders_source_service'",
          )
          .getSingle();
      expect(index.read<int>('row_count'), 1);
    },
  );

  test('upgrades schema v4 with archive and expense-service columns', () async {
    final database = createDatabase(seedSchemaVersion: 4);
    await database.open();

    expect(await database.currentSchemaVersion, 5);
    final vehicleColumns = await database
        .customSelect('PRAGMA table_info(vehicles)')
        .get();
    final expenseColumns = await database
        .customSelect('PRAGMA table_info(vehicle_expenses)')
        .get();
    expect(
      vehicleColumns.map((row) => row.read<String>('name')),
      contains('is_archived'),
    );
    expect(
      expenseColumns.map((row) => row.read<String>('name')),
      contains('source_service_id'),
    );
  });

  test('deleting a service cascades only to its linked reminder', () async {
    final database = createDatabase();
    await database.open();
    await database.customStatement('''
      INSERT INTO vehicles
        (id, name, type, make, model, year, registration, odometer, purchase_price)
      VALUES ('vehicle-1', 'Test vehicle', 'Car', 'Make', 'Model', 2024, '', 100, 0)
    ''');
    await database.customStatement('''
      INSERT INTO service_records
        (id, vehicle_id, title, category, date, odometer, cost, mechanic, notes)
      VALUES ('service-1', 'vehicle-1', 'Oil change', 'Service',
        1730000000000000, 100, 10, '', '')
    ''');
    await database.customStatement('''
      INSERT INTO maintenance_reminders
        (id, vehicle_id, title, notes, completed, source_service_id)
      VALUES ('linked-reminder', 'vehicle-1', 'Oil change', '', 0, 'service-1')
    ''');
    await database.customStatement('''
      INSERT INTO maintenance_reminders
        (id, vehicle_id, title, notes, completed)
      VALUES ('manual-reminder', 'vehicle-1', 'Manual check', '', 0)
    ''');

    await database.customStatement(
      "DELETE FROM service_records WHERE id = 'service-1'",
    );

    final remaining = await database
        .customSelect('SELECT id FROM maintenance_reminders ORDER BY id')
        .get();
    expect(remaining.map((row) => row.read<String>('id')), ['manual-reminder']);
  });

  test(
    'deleting a service unlinks its expenses instead of deleting them',
    () async {
      final database = createDatabase();
      await database.open();
      await database.customStatement('''
      INSERT INTO vehicles
        (id, name, type, make, model, year, registration, odometer, purchase_price)
      VALUES ('vehicle-1', 'Test vehicle', 'Car', 'Make', 'Model', 2024, '', 100, 0)
    ''');
      await database.customStatement('''
      INSERT INTO service_records
        (id, vehicle_id, title, category, date, odometer, cost, mechanic, notes)
      VALUES ('service-1', 'vehicle-1', 'Oil change', 'Service', 1730000000000000, 100, 100, '', '')
    ''');
      await database.customStatement('''
      INSERT INTO vehicle_expenses
        (id, vehicle_id, category, description, date, amount, odometer, source_service_id)
      VALUES ('expense-1', 'vehicle-1', 'Parts', 'Filter', 1730000000000000, 25, 100, 'service-1')
    ''');

      await database.customStatement(
        "DELETE FROM service_records WHERE id = 'service-1'",
      );
      final row = await database
          .customSelect(
            "SELECT source_service_id FROM vehicle_expenses WHERE id = 'expense-1'",
          )
          .getSingle();
      expect(row.data['source_service_id'], equals(null));
    },
  );

  test('enables SQLite foreign-key enforcement', () async {
    final database = createDatabase();
    await database.open();

    expect(await database.foreignKeysEnabled, isTrue);
  });

  test(
    'child records require a valid vehicle and cascade on vehicle delete',
    () async {
      final database = createDatabase();
      await database.open();

      await expectLater(
        database.customStatement('''
          INSERT INTO service_records
            (id, vehicle_id, title, category, date, odometer, cost, mechanic, notes)
          VALUES ('orphan-service', 'missing-vehicle', 'Oil change', 'Service',
            1730000000000000, 100, 10, '', '')
        '''),
        throwsA(anything),
      );

      await database.customStatement('''
        INSERT INTO vehicles
          (id, name, type, make, model, year, registration, odometer, purchase_price)
        VALUES ('vehicle-1', 'Test vehicle', 'Car', 'Make', 'Model', 2024, '', 100, 0)
      ''');
      await database.customStatement('''
        INSERT INTO service_records
          (id, vehicle_id, title, category, date, odometer, cost, mechanic, notes)
        VALUES ('service-1', 'vehicle-1', 'Oil change', 'Service',
          1730000000000000, 100, 10, '', '')
      ''');
      await database.customStatement('''
        INSERT INTO vehicle_expenses
          (id, vehicle_id, category, description, date, amount, odometer)
        VALUES ('expense-1', 'vehicle-1', 'Fuel', 'Refuel',
          1730000000000000, 20, 100)
      ''');
      await database.customStatement('''
        INSERT INTO maintenance_reminders
          (id, vehicle_id, title, due_date, due_odometer, notes, completed)
        VALUES ('reminder-1', 'vehicle-1', 'Inspection', NULL, 200, '', 0)
      ''');

      await database.customStatement(
        "DELETE FROM vehicles WHERE id = 'vehicle-1'",
      );

      for (final table in [
        'service_records',
        'vehicle_expenses',
        'maintenance_reminders',
      ]) {
        final row = await database
            .customSelect('SELECT COUNT(*) AS row_count FROM $table')
            .getSingle();
        expect(row.read<int>('row_count'), 0, reason: '$table should cascade');
      }
    },
  );

  test('numeric and boolean constraints reject invalid values', () async {
    final database = createDatabase();
    await database.open();

    await expectLater(
      database.customStatement('''
        INSERT INTO vehicles
          (id, name, type, make, model, year, registration, odometer, purchase_price)
        VALUES ('bad-vehicle', 'Bad', 'Car', '', '', 2024, '', -1, 0)
      '''),
      throwsA(anything),
    );

    await database.customStatement('''
      INSERT INTO vehicles
        (id, name, type, make, model, year, registration, odometer, purchase_price)
      VALUES ('vehicle-valid', 'Valid', 'Car', '', '', 2024, '', 0, 0)
    ''');
    await expectLater(
      database.customStatement('''
        INSERT INTO maintenance_reminders
          (id, vehicle_id, title, completed)
        VALUES ('bad-reminder', 'vehicle-valid', 'Inspection', 2)
      '''),
      throwsA(anything),
    );
  });

  test('repeated open and close calls are safe', () async {
    final database = createDatabase();
    await Future.wait([database.open(), database.open()]);
    await database.close();
    await database.close();
  });

  test('does not reopen after it has been closed', () async {
    final database = createDatabase();
    await database.close();

    await expectLater(database.open(), throwsA(isA<StateError>()));
  });
}
