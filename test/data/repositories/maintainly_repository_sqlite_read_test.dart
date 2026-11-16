import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/core/data/legacy_storage_keys.dart';
import 'package:maintainly/core/data/local_store.dart';
import 'package:maintainly/core/database/maintainly_database.dart';
import 'package:maintainly/data/migration/legacy_json_to_sqlite_migrator.dart';
import 'package:maintainly/data/models/service_record.dart';
import 'package:maintainly/data/repositories/maintainly_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> vehicle({String name = 'Legacy car'}) => {
    'id': 'vehicle-1',
    'name': name,
    'type': 'Car',
    'make': 'Toyota',
    'model': 'Corolla',
    'year': 2022,
    'registration': 'ABC-123',
    'odometer': 50000,
    'purchaseDate': '2022-01-01T00:00:00.000',
    'purchasePrice': 2500000.0,
  };

  Map<String, Object?> service() => {
    'id': 'service-1',
    'vehicleId': 'vehicle-1',
    'title': 'Oil change',
    'category': 'Maintenance',
    'date': '2026-10-01T10:00:00.000',
    'odometer': 49000,
    'cost': 8500.0,
    'mechanic': 'Workshop',
    'notes': 'Synthetic oil',
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

  Map<String, Object> legacyValues({String vehicleName = 'Legacy car'}) => {
    LegacyStorageKeys.vehicles: jsonEncode([vehicle(name: vehicleName)]),
    LegacyStorageKeys.services: jsonEncode([service()]),
    LegacyStorageKeys.expenses: jsonEncode([expense()]),
    LegacyStorageKeys.reminders: jsonEncode([reminder()]),
    LegacyStorageKeys.seeded: 'yes',
  };

  Future<_Fixture> createFixture({
    bool migrate = false,
    bool autoMigrateOnLoad = false,
  }) async {
    SharedPreferences.setMockInitialValues(legacyValues());
    final store = await LocalStore.create();
    final database = MaintainlyDatabase(
      connection: DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final migrator = LegacyJsonToSqliteMigrator(
      store: store,
      database: database,
    );
    if (migrate) {
      final result = await migrator.migrate(
        completedAt: DateTime.utc(2026, 11, 13, 12),
      );
      expect(result.didMigrate, isTrue);
    }
    return _Fixture(
      store: store,
      database: database,
      repository: MaintainlyRepository(
        store,
        database: database,
        autoMigrateLegacyDataOnLoad: autoMigrateOnLoad,
      ),
    );
  }

  test(
    'uses legacy SharedPreferences when no completed migration ledger exists',
    () async {
      final fixture = await createFixture();

      final data = await fixture.repository.load();

      expect(data.vehicles, hasLength(1));
      expect(data.vehicles.single.name, 'Legacy car');
      expect(data.services, hasLength(1));
      expect(data.expenses, hasLength(1));
      expect(data.reminders, hasLength(1));
    },
  );

  test(
    'reads all four collections from SQLite after successful migration',
    () async {
      final fixture = await createFixture(migrate: true);

      // Deliberately change the legacy copy without using repository.save().
      // A repository correctly following the migration ledger must still read
      // the committed SQLite snapshot in this test.
      await fixture.store.write(
        LegacyStorageKeys.vehicles,
        jsonEncode([vehicle(name: 'Changed legacy copy')]),
      );

      final data = await fixture.repository.load();

      expect(data.vehicles, hasLength(1));
      expect(data.vehicles.single.name, 'Legacy car');
      expect(data.services.single.id, 'service-1');
      expect(data.services.single.nextDueOdometer, 54000);
      expect(data.expenses.single.amount, 5000.0);
      expect(data.reminders.single.completed, isFalse);
    },
  );

  test(
    'writes updated snapshots to SQLite and reloads them from SQLite',
    () async {
      final fixture = await createFixture(migrate: true);
      final migratedData = await fixture.repository.load();
      final updatedData = MaintainlyData(
        vehicles: [
          migratedData.vehicles.single.copyWith(name: 'Edited in current app'),
        ],
        services: migratedData.services,
        expenses: migratedData.expenses,
        reminders: migratedData.reminders,
      );

      await fixture.repository.save(updatedData);
      final reloaded = await fixture.repository.load();

      expect(reloaded.vehicles.single.name, 'Edited in current app');
      expect(
        fixture.store.readBool(MaintainlyRepository.sqliteReadFallbackKey),
        isFalse,
      );
      final sqliteVehicle = await fixture.database
          .customSelect(
            'SELECT name FROM vehicles WHERE id = ?',
            variables: [Variable.withString('vehicle-1')],
          )
          .getSingle();
      expect(sqliteVehicle.read<String>('name'), 'Edited in current app');
      final ledger = await fixture.database
          .customSelect(
            'SELECT vehicle_count, total_record_count FROM maintainly_migrations WHERE migration_key = ?',
            variables: [
              Variable.withString(LegacyJsonToSqliteMigrator.migrationKey),
            ],
          )
          .getSingle();
      expect(ledger.read<int>('vehicle_count'), 1);
      expect(ledger.read<int>('total_record_count'), 4);
    },
  );

  test('rolls back the entire SQLite snapshot when a child row violates its vehicle foreign key', () async {
    final fixture = await createFixture(migrate: true);
    final original = await fixture.repository.load();
    final invalidData = MaintainlyData(
      vehicles: original.vehicles,
      services: [
        ServiceRecord(
          id: 'orphan-service',
          vehicleId: 'missing-vehicle',
          title: 'Invalid service',
          category: 'Repair',
          date: DateTime(2026, 11, 1),
          odometer: 50000,
          cost: 100,
          mechanic: '',
          notes: '',
        ),
      ],
      expenses: original.expenses,
      reminders: original.reminders,
    );

    await expectLater(fixture.repository.save(invalidData), throwsA(anything));

    final dataAfterFailure = await fixture.repository.load();
    expect(dataAfterFailure.services.single.id, 'service-1');
    expect(dataAfterFailure.vehicles.single.name, 'Legacy car');
    final serviceCount = await fixture.database
        .customSelect('SELECT COUNT(*) AS row_count FROM service_records')
        .getSingle();
    expect(serviceCount.read<int>('row_count'), 1);
  });

  test('restores a complete backup snapshot to SQLite', () async {
    final fixture = await createFixture(migrate: true);
    final current = await fixture.repository.load();
    final backupData = MaintainlyData(
      vehicles: [current.vehicles.single.copyWith(name: 'Restored vehicle')],
      services: current.services,
      expenses: current.expenses,
      reminders: current.reminders,
    );

    await fixture.repository.restore(backupData);

    final restored = await fixture.repository.load();
    expect(restored.vehicles.single.name, 'Restored vehicle');
    expect(restored.services.single.id, 'service-1');
    expect(restored.expenses.single.id, 'expense-1');
    expect(restored.reminders.single.id, 'reminder-1');
    expect(
      fixture.store.readBool(MaintainlyRepository.sqliteReadFallbackKey),
      isFalse,
    );
  });

  test(
    'rolls back a failed restore and retains the previous source marker',
    () async {
      final fixture = await createFixture(migrate: true);
      final current = await fixture.repository.load();
      await fixture.store.writeBool(
        MaintainlyRepository.sqliteReadFallbackKey,
        true,
      );
      final backupData = MaintainlyData(
        vehicles: [
          current.vehicles.single.copyWith(name: 'Must not be committed'),
        ],
        services: current.services,
        expenses: current.expenses,
        reminders: current.reminders,
      );
      await fixture.database.customStatement('''
      CREATE TRIGGER fail_restore_vehicle_insert
      BEFORE INSERT ON vehicles
      BEGIN
        SELECT RAISE(ABORT, 'forced restore failure');
      END;
    ''');

      await expectLater(
        fixture.repository.restore(backupData),
        throwsA(anything),
      );

      expect(
        fixture.store.readBool(MaintainlyRepository.sqliteReadFallbackKey),
        isTrue,
      );
      final dataAfterFailure = await fixture.repository.load();
      expect(dataAfterFailure.vehicles.single.name, 'Legacy car');
      expect(dataAfterFailure.services.single.id, 'service-1');
      await fixture.database.customStatement(
        'DROP TRIGGER fail_restore_vehicle_insert',
      );
    },
  );

  test('refuses restore when SQLite migration is not complete', () async {
    final fixture = await createFixture();
    final current = await fixture.repository.load();
    final attemptedData = MaintainlyData(
      vehicles: [current.vehicles.single.copyWith(name: 'Must stay unchanged')],
      services: current.services,
      expenses: current.expenses,
      reminders: current.reminders,
    );

    await expectLater(
      fixture.repository.restore(attemptedData),
      throwsStateError,
    );

    final stillCurrent = await fixture.repository.load();
    expect(stillCurrent.vehicles.single.name, 'Legacy car');
  });

  test(
    'switches a Step 5 legacy-write fallback snapshot into SQLite on save',
    () async {
      final fixture = await createFixture(migrate: true);
      final original = await fixture.repository.load();
      await fixture.store.writeBool(
        MaintainlyRepository.sqliteReadFallbackKey,
        true,
      );
      await fixture.store.write(
        LegacyStorageKeys.vehicles,
        jsonEncode([vehicle(name: 'Edited during compatibility mode')]),
      );

      final compatibilityData = await fixture.repository.load();
      expect(
        compatibilityData.vehicles.single.name,
        'Edited during compatibility mode',
      );
      await fixture.repository.save(compatibilityData);

      expect(
        fixture.store.readBool(MaintainlyRepository.sqliteReadFallbackKey),
        isFalse,
      );
      final persisted = await fixture.repository.load();
      expect(
        persisted.vehicles.single.name,
        'Edited during compatibility mode',
      );
      expect(original.vehicles.single.name, 'Legacy car');
    },
  );

  test('falls back to preserved legacy data when SQLite ledger counts do not match', () async {
    final fixture = await createFixture(migrate: true);
    await fixture.database.customStatement(
      "DELETE FROM service_records WHERE id = 'service-1'",
    );

    final data = await fixture.repository.load();

    expect(data.vehicles.single.name, 'Legacy car');
    expect(data.services, hasLength(1));
    expect(fixture.store.read(LegacyStorageKeys.services) != null, true);
  });

  test(
    'keeps legacy-only repository construction backwards compatible',
    () async {
      SharedPreferences.setMockInitialValues(legacyValues());
      final store = await LocalStore.create();
      final repository = MaintainlyRepository(store);

      final data = await repository.load();

      expect(data.vehicles.single.name, 'Legacy car');
      expect(data.services, hasLength(1));
    },
  );

  test(
    'does not switch back to SQLite once a legacy-write fallback marker exists',
    () async {
      final fixture = await createFixture(migrate: true);
      await fixture.store.writeBool(
        MaintainlyRepository.sqliteReadFallbackKey,
        true,
      );
      await fixture.store.write(
        LegacyStorageKeys.vehicles,
        jsonEncode([vehicle(name: 'New legacy source')]),
      );

      final data = await fixture.repository.load();

      expect(data.vehicles.single.name, 'New legacy source');
    },
  );

  test('automatically backs up and migrates valid legacy data before returning SQLite reads', () async {
    final fixture = await createFixture(autoMigrateOnLoad: true);

    final data = await fixture.repository.load();

    expect(data.vehicles.single.name, 'Legacy car');
    expect(data.services, hasLength(1));
    expect(data.expenses, hasLength(1));
    expect(data.reminders, hasLength(1));
    final ledger = await fixture.database
        .customSelect(
          'SELECT total_record_count FROM maintainly_migrations WHERE migration_key = ?',
          variables: [
            Variable.withString(LegacyJsonToSqliteMigrator.migrationKey),
          ],
        )
        .getSingle();
    expect(ledger.read<int>('total_record_count'), 4);
    expect(fixture.store.read(LegacyStorageKeys.migrationBackup) != null, true);
  });

  test(
    'keeps the legacy source active when automatic migration is blocked',
    () async {
      const malformed = '[{"id":"broken"';
      SharedPreferences.setMockInitialValues({
        LegacyStorageKeys.vehicles: malformed,
        LegacyStorageKeys.seeded: 'yes',
      });
      final store = await LocalStore.create();
      final database = MaintainlyDatabase(
        connection: DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final repository = MaintainlyRepository(
        store,
        database: database,
        autoMigrateLegacyDataOnLoad: true,
      );

      final data = await repository.load();

      expect(data.vehicles, isEmpty);
      expect(store.read(LegacyStorageKeys.vehicles), malformed);
      expect(store.read(LegacyStorageKeys.migrationBackup) != null, true);
      final ledgerCount = await database
          .customSelect(
            'SELECT COUNT(*) AS row_count FROM maintainly_migrations',
          )
          .getSingle();
      expect(ledgerCount.read<int>('row_count'), 0);
    },
  );

  test('seeds and migrates a genuinely fresh first launch when enabled by the app provider', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.create();
    final database = MaintainlyDatabase(
      connection: DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final repository = MaintainlyRepository(
      store,
      database: database,
      autoMigrateLegacyDataOnLoad: true,
    );

    final data = await repository.load();

    expect(data.vehicles, hasLength(3));
    expect(data.services, hasLength(3));
    expect(data.expenses, hasLength(4));
    expect(data.reminders, hasLength(3));
    expect(store.read(LegacyStorageKeys.seeded), 'yes');
    expect(store.read(LegacyStorageKeys.migrationBackup) != null, true);
  });

  test(
    'falls back to preserved SharedPreferences when SQLite cannot open',
    () async {
      final fixture = await createFixture(autoMigrateOnLoad: true);
      await fixture.database.close();

      final data = await fixture.repository.load();

      expect(data.vehicles.single.name, 'Legacy car');
      expect(data.services, hasLength(1));
      expect(fixture.store.read(LegacyStorageKeys.vehicles) != null, true);
    },
  );

  test('preserves newer legacy saves when SQLite becomes unavailable after migration', () async {
    final fixture = await createFixture(migrate: true);

    // First successful SQLite read persists the migration-completed marker.
    final migratedData = await fixture.repository.load();
    expect(
      fixture.store.readBool(MaintainlyRepository.sqliteMigrationCompletedKey),
      isTrue,
    );

    // Simulate a later database-open failure on this same app repository.
    await fixture.database.close();
    final legacyData = await fixture.repository.load();
    final updatedData = MaintainlyData(
      vehicles: [
        legacyData.vehicles.single.copyWith(
          name: 'Saved while SQLite unavailable',
        ),
      ],
      services: legacyData.services,
      expenses: legacyData.expenses,
      reminders: legacyData.reminders,
    );
    await fixture.repository.save(updatedData);

    expect(
      fixture.store.readBool(MaintainlyRepository.sqliteReadFallbackKey),
      isTrue,
    );
    expect(
      fixture.store.read(LegacyStorageKeys.vehicles),
      contains('Saved while SQLite unavailable'),
    );
    expect(migratedData.vehicles.single.name, 'Legacy car');
  });
}

class _Fixture {
  const _Fixture({
    required this.store,
    required this.database,
    required this.repository,
  });

  final LocalStore store;
  final MaintainlyDatabase database;
  final MaintainlyRepository repository;
}
