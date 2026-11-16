import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/core/data/legacy_storage_keys.dart';
import 'package:maintainly/core/data/local_store.dart';
import 'package:maintainly/core/database/maintainly_database.dart';
import 'package:maintainly/data/migration/legacy_data_inspector.dart';
import 'package:maintainly/data/migration/legacy_json_to_sqlite_migrator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_MigrationFixture> createFixture(
    Map<String, Object> values, {
    bool openDatabase = false,
  }) async {
    SharedPreferences.setMockInitialValues(values);
    final store = await LocalStore.create();
    final database = MaintainlyDatabase(
      connection: DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    if (openDatabase) await database.open();
    return _MigrationFixture(
      store: store,
      database: database,
      migrator: LegacyJsonToSqliteMigrator(store: store, database: database),
    );
  }

  Map<String, Object?> vehicle({String id = 'vehicle-1'}) => {
    'id': id,
    'name': 'Daily car',
    'type': 'Car',
    'make': 'Toyota',
    'model': 'Corolla',
    'year': 2022,
    'registration': 'ABC-123',
    'odometer': 50000,
    'purchaseDate': '2022-01-01T00:00:00.000',
    'purchasePrice': 2500000.0,
  };

  Map<String, Object?> service({String id = 'service-1'}) => {
    'id': id,
    'vehicleId': 'vehicle-1',
    'title': 'Oil change',
    'category': 'Maintenance',
    'date': '2026-10-01T10:00:00.000',
    'odometer': 49000,
    'cost': 8500.0,
    'mechanic': 'Workshop',
    'notes': '',
    'nextDueDate': '2027-04-01T10:00:00.000',
    'nextDueOdometer': 54000,
  };

  Map<String, Object?> expense() => {
    'id': 'expense-1',
    'vehicleId': 'vehicle-1',
    'category': 'Fuel',
    'description': 'Petrol',
    'date': '2026-10-02T12:00:00.000',
    'amount': 5000.0,
    'odometer': 49100,
  };

  Map<String, Object?> reminder() => {
    'id': 'reminder-1',
    'vehicleId': 'vehicle-1',
    'title': 'Next oil change',
    'dueDate': '2026-12-01T00:00:00.000',
    'dueOdometer': 54000,
    'notes': 'Use recommended oil',
    'completed': false,
  };

  Map<String, Object> validLegacyValues() => {
    LegacyStorageKeys.vehicles: jsonEncode([vehicle()]),
    LegacyStorageKeys.services: jsonEncode([service()]),
    LegacyStorageKeys.expenses: jsonEncode([expense()]),
    LegacyStorageKeys.reminders: jsonEncode([reminder()]),
    LegacyStorageKeys.seeded: 'yes',
  };

  Future<int> countRows(MaintainlyDatabase database, String table) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS row_count FROM $table')
        .getSingle();
    return row.read<int>('row_count');
  }

  test('backs up and imports all four collections in one migration', () async {
    final values = validLegacyValues();
    final fixture = await createFixture(values);
    final sourceVehicles = fixture.store.read(LegacyStorageKeys.vehicles);
    final sourceServices = fixture.store.read(LegacyStorageKeys.services);
    final sourceExpenses = fixture.store.read(LegacyStorageKeys.expenses);
    final sourceReminders = fixture.store.read(LegacyStorageKeys.reminders);

    final result = await fixture.migrator.migrate(
      completedAt: DateTime.utc(2026, 11, 13, 12),
    );

    expect(result.status, LegacyMigrationStatus.migrated);
    expect(result.didMigrate, isTrue);
    expect(result.vehicleCount, 1);
    expect(result.serviceCount, 1);
    expect(result.expenseCount, 1);
    expect(result.reminderCount, 1);
    expect(result.totalRecordCount, 4);

    expect(await countRows(fixture.database, 'vehicles'), 1);
    expect(await countRows(fixture.database, 'service_records'), 1);
    expect(await countRows(fixture.database, 'vehicle_expenses'), 1);
    expect(await countRows(fixture.database, 'maintenance_reminders'), 1);
    expect(await countRows(fixture.database, 'maintainly_migrations'), 1);

    final importedVehicle = await fixture.database
        .customSelect(
          'SELECT id, name, odometer, purchase_price FROM vehicles WHERE id = ?',
          variables: [Variable.withString('vehicle-1')],
        )
        .getSingle();
    expect(importedVehicle.read<String>('id'), 'vehicle-1');
    expect(importedVehicle.read<String>('name'), 'Daily car');
    expect(importedVehicle.read<int>('odometer'), 50000);
    expect(importedVehicle.read<double>('purchase_price'), 2500000.0);

    final importedReminder = await fixture.database
        .customSelect(
          'SELECT id, completed, due_odometer FROM maintenance_reminders WHERE id = ?',
          variables: [Variable.withString('reminder-1')],
        )
        .getSingle();
    expect(importedReminder.read<String>('id'), 'reminder-1');
    expect(importedReminder.read<int>('completed'), 0);
    expect(importedReminder.read<int>('due_odometer'), 54000);

    final backup = fixture.store.read(LegacyStorageKeys.migrationBackup);
    expect(backup != null, true);
    final decodedBackup = jsonDecode(backup!) as Map<String, dynamic>;
    expect(decodedBackup['formatVersion'], 1);
    expect(
      (decodedBackup['entries'] as Map)[LegacyStorageKeys.vehicles]['value'],
      sourceVehicles,
    );

    // The original source keys and seed marker remain untouched.
    expect(fixture.store.read(LegacyStorageKeys.vehicles), sourceVehicles);
    expect(fixture.store.read(LegacyStorageKeys.services), sourceServices);
    expect(fixture.store.read(LegacyStorageKeys.expenses), sourceExpenses);
    expect(fixture.store.read(LegacyStorageKeys.reminders), sourceReminders);
    expect(fixture.store.read(LegacyStorageKeys.seeded), 'yes');
  });

  test(
    'is idempotent and does not duplicate records on a repeated call',
    () async {
      final fixture = await createFixture(validLegacyValues());

      final first = await fixture.migrator.migrate();
      final second = await fixture.migrator.migrate();

      expect(first.status, LegacyMigrationStatus.migrated);
      expect(second.status, LegacyMigrationStatus.alreadyMigrated);
      expect(second.totalRecordCount, 4);
      expect(await countRows(fixture.database, 'vehicles'), 1);
      expect(await countRows(fixture.database, 'service_records'), 1);
      expect(await countRows(fixture.database, 'vehicle_expenses'), 1);
      expect(await countRows(fixture.database, 'maintenance_reminders'), 1);
      expect(await countRows(fixture.database, 'maintainly_migrations'), 1);
    },
  );

  test(
    'blocks unsafe legacy data but persists an exact backup first',
    () async {
      const malformedRaw = '[{"id":"broken"';
      final fixture = await createFixture({
        LegacyStorageKeys.vehicles: malformedRaw,
        LegacyStorageKeys.seeded: 'yes',
      });

      final result = await fixture.migrator.migrate();

      expect(result.status, LegacyMigrationStatus.blocked);
      expect(result.report.isReadyForMigration, isFalse);
      expect(fixture.store.read(LegacyStorageKeys.vehicles), malformedRaw);

      final backup = jsonDecode(
        fixture.store.read(LegacyStorageKeys.migrationBackup)!,
      ) as Map<String, dynamic>;
      expect(
        (backup['entries'] as Map)[LegacyStorageKeys.vehicles]['value'],
        malformedRaw,
      );
      expect(await countRows(fixture.database, 'vehicles'), 0);
      expect(await countRows(fixture.database, 'maintainly_migrations'), 0);
    },
  );

  test(
    'blocks partially valid collections without importing good rows alone',
    () async {
      final raw = jsonEncode([
        vehicle(),
        {'name': 'Missing required ID'},
      ]);
      final fixture = await createFixture({
        LegacyStorageKeys.vehicles: raw,
        LegacyStorageKeys.seeded: 'yes',
      });

      final result = await fixture.migrator.migrate();

      expect(result.status, LegacyMigrationStatus.blocked);
      expect(result.report.invalidRecordCount, 1);
      expect(fixture.store.read(LegacyStorageKeys.vehicles), raw);
      expect(
        fixture.store.read(LegacyStorageKeys.migrationBackup) != null,
        true,
      );
      expect(await countRows(fixture.database, 'vehicles'), 0);
      expect(await countRows(fixture.database, 'maintainly_migrations'), 0);
    },
  );

  test('rolls back every inserted row when a child insert fails', () async {
    final fixture = await createFixture(
      validLegacyValues(),
      openDatabase: true,
    );
    await fixture.database.customStatement('''
      CREATE TRIGGER force_service_insert_failure
      BEFORE INSERT ON service_records
      BEGIN
        SELECT RAISE(ABORT, 'forced test failure');
      END
    ''');

    await expectLater(fixture.migrator.migrate(), throwsA(anything));

    // Vehicle insertion happened before the service failure, but the
    // transaction must roll it back together with every other write.
    expect(await countRows(fixture.database, 'vehicles'), 0);
    expect(await countRows(fixture.database, 'service_records'), 0);
    expect(await countRows(fixture.database, 'vehicle_expenses'), 0);
    expect(await countRows(fixture.database, 'maintenance_reminders'), 0);
    expect(await countRows(fixture.database, 'maintainly_migrations'), 0);
    expect(fixture.store.read(LegacyStorageKeys.migrationBackup) != null, true);
    expect(fixture.store.read(LegacyStorageKeys.vehicles) != null, true);
  });

  test('can retry successfully after a transaction rollback', () async {
    final fixture = await createFixture(
      validLegacyValues(),
      openDatabase: true,
    );
    await fixture.database.customStatement('''
      CREATE TRIGGER force_service_insert_failure
      BEFORE INSERT ON service_records
      BEGIN
        SELECT RAISE(ABORT, 'forced test failure');
      END
    ''');

    await expectLater(fixture.migrator.migrate(), throwsA(anything));
    expect(await countRows(fixture.database, 'vehicles'), 0);

    await fixture.database.customStatement(
      'DROP TRIGGER force_service_insert_failure',
    );
    final retry = await fixture.migrator.migrate();

    expect(retry.status, LegacyMigrationStatus.migrated);
    expect(retry.totalRecordCount, 4);
    expect(await countRows(fixture.database, 'vehicles'), 1);
    expect(await countRows(fixture.database, 'service_records'), 1);
    expect(await countRows(fixture.database, 'vehicle_expenses'), 1);
    expect(await countRows(fixture.database, 'maintenance_reminders'), 1);
    expect(await countRows(fixture.database, 'maintainly_migrations'), 1);
  });

  test(
    'refuses to import over pre-existing SQLite data without a ledger row',
    () async {
      final fixture = await createFixture(
        validLegacyValues(),
        openDatabase: true,
      );
      await fixture.database.customStatement('''
      INSERT INTO vehicles
        (id, name, type, make, model, year, registration, odometer, purchase_price)
      VALUES ('already-here', 'Existing', 'Car', '', '', 2020, '', 10, 0)
    ''');

      await expectLater(fixture.migrator.migrate(), throwsA(isA<StateError>()));

      expect(await countRows(fixture.database, 'vehicles'), 1);
      expect(await countRows(fixture.database, 'maintainly_migrations'), 0);
      expect(
        fixture.store.read(LegacyStorageKeys.migrationBackup) != null,
        true,
      );
    },
  );

  test(
    'imports an empty but valid legacy snapshot and records completion',
    () async {
      final fixture = await createFixture({LegacyStorageKeys.seeded: 'yes'});

      final result = await fixture.migrator.migrate();

      expect(result.status, LegacyMigrationStatus.migrated);
      expect(result.totalRecordCount, 0);
      expect(await countRows(fixture.database, 'maintainly_migrations'), 1);
      expect(
        fixture.store.read(LegacyStorageKeys.migrationBackup) != null,
        true,
      );
    },
  );

  test('does not mark a completely fresh installation as migrated', () async {
    final fixture = await createFixture({});

    final result = await fixture.migrator.migrate();

    expect(result.status, LegacyMigrationStatus.blocked);
    expect(result.blockedReason, contains('fresh installation'));
    expect(await countRows(fixture.database, 'maintainly_migrations'), 0);
    expect(fixture.store.read(LegacyStorageKeys.migrationBackup) != null, true);
  });

  test(
    'preserves an earlier backup and writes a new snapshot when source changes',
    () async {
      final fixture = await createFixture(validLegacyValues());
      final inspector = LegacyDataInspector(fixture.store);
      final originalBackup = inspector
          .createBackupSnapshot(createdAt: DateTime.utc(2026, 11, 13))
          .encode();
      await fixture.store.writeVerified(
        LegacyStorageKeys.migrationBackup,
        originalBackup,
      );

      final changedVehicle = vehicle()..['name'] = 'Updated daily car';
      await fixture.store.write(
        LegacyStorageKeys.vehicles,
        jsonEncode([changedVehicle]),
      );

      final result = await fixture.migrator.migrate(
        completedAt: DateTime.utc(2026, 11, 14),
      );

      expect(result.status, LegacyMigrationStatus.migrated);
      expect(result.backupKey, isNot(LegacyStorageKeys.migrationBackup));
      expect(
        fixture.store.read(LegacyStorageKeys.migrationBackup),
        originalBackup,
      );
      final newBackup = jsonDecode(
        fixture.store.read(result.backupKey)!,
      ) as Map<String, dynamic>;
      expect(
        (newBackup['entries'] as Map)[LegacyStorageKeys.vehicles]['value'],
        jsonEncode([changedVehicle]),
      );
    },
  );
}

class _MigrationFixture {
  const _MigrationFixture({
    required this.store,
    required this.database,
    required this.migrator,
  });

  final LocalStore store;
  final MaintainlyDatabase database;
  final LegacyJsonToSqliteMigrator migrator;
}
