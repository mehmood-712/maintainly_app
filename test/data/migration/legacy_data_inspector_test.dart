import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/core/data/local_store.dart';
import 'package:maintainly/core/data/legacy_storage_keys.dart';
import 'package:maintainly/data/migration/legacy_data_inspector.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> createStore(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return LocalStore.create();
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

  Map<String, Object?> service({
    String id = 'service-1',
    String vehicleId = 'vehicle-1',
  }) => {
    'id': id,
    'vehicleId': vehicleId,
    'title': 'Oil change',
    'category': 'Maintenance',
    'date': '2026-10-01T10:00:00.000',
    'odometer': 49000,
    'cost': 8500.0,
    'mechanic': 'Workshop',
    'notes': '',
    'nextDueDate': null,
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

  test(
    'inspects all four valid legacy JSON collections and relationships',
    () async {
      final store = await createStore(validLegacyValues());
      final report = LegacyDataInspector(store)
          .inspect(inspectedAt: DateTime.utc(2026, 11, 13));

      expect(
        report.collections.keys,
        containsAll(LegacyStorageKeys.collections),
      );
      for (final key in LegacyStorageKeys.collections) {
        expect(report.collections[key]!.status, LegacyValueStatus.valid);
        expect(report.collections[key]!.recordCount, 1);
        expect(report.collections[key]!.validRecordCount, 1);
        expect(report.collections[key]!.invalidRecordCount, 0);
      }
      expect(report.totalRecordCount, 4);
      expect(report.validRecordCount, 4);
      expect(report.invalidRecordCount, 0);
      expect(report.seedMarker.isMarkedSeeded, isTrue);
      expect(report.sampleDataOverwriteRisk, isFalse);
      expect(report.isReadyForMigration, isTrue);
      expect(report.issues, isEmpty);
    },
  );

  test('accepts older reminders without a source service link', () async {
    final store = await createStore(validLegacyValues());
    final report = LegacyDataInspector(store).inspect();

    expect(
      report.collections[LegacyStorageKeys.reminders]!.status,
      LegacyValueStatus.valid,
    );
    expect(report.collections[LegacyStorageKeys.reminders]!.issues, isEmpty);
  });

  test('rejects a non-string source service link when present', () async {
    final invalidReminder = reminder()..['sourceServiceId'] = 42;
    final values = validLegacyValues();
    values[LegacyStorageKeys.reminders] = jsonEncode([invalidReminder]);
    final store = await createStore(values);
    final report = LegacyDataInspector(store).inspect();

    expect(
      report.collections[LegacyStorageKeys.reminders]!.status,
      LegacyValueStatus.malformed,
    );
    expect(report.collections[LegacyStorageKeys.reminders]!.issues, isNotEmpty);
  });

  test(
    'rejects malformed optional expense and vehicle integrity fields',
    () async {
      final invalidExpense = expense()..['sourceServiceId'] = 42;
      final invalidVehicle = vehicle()..['isArchived'] = 'yes';
      final values = validLegacyValues();
      values[LegacyStorageKeys.expenses] = jsonEncode([invalidExpense]);
      values[LegacyStorageKeys.vehicles] = jsonEncode([invalidVehicle]);
      final store = await createStore(values);
      final report = LegacyDataInspector(store).inspect();

      expect(
        report.collections[LegacyStorageKeys.expenses]!.status,
        LegacyValueStatus.malformed,
      );
      expect(
        report.collections[LegacyStorageKeys.vehicles]!.status,
        LegacyValueStatus.malformed,
      );
    },
  );

  test(
    'distinguishes missing keys from present but empty collections',
    () async {
      final store = await createStore({
        LegacyStorageKeys.vehicles: '',
        LegacyStorageKeys.services: '[]',
        LegacyStorageKeys.seeded: 'yes',
      });
      final report = LegacyDataInspector(store).inspect();

      expect(
        report.collections[LegacyStorageKeys.vehicles]!.status,
        LegacyValueStatus.empty,
      );
      expect(
        report.collections[LegacyStorageKeys.services]!.status,
        LegacyValueStatus.empty,
      );
      expect(
        report.collections[LegacyStorageKeys.expenses]!.status,
        LegacyValueStatus.missing,
      );
      expect(
        report.collections[LegacyStorageKeys.reminders]!.status,
        LegacyValueStatus.missing,
      );
      expect(report.isReadyForMigration, isTrue);
    },
  );

  test('reports malformed JSON and retains the original raw value', () async {
    const raw = '[{"id":"broken"';
    final store = await createStore({
      LegacyStorageKeys.vehicles: raw,
      LegacyStorageKeys.seeded: 'yes',
    });
    final report = LegacyDataInspector(store).inspect();
    final vehicles = report.collections[LegacyStorageKeys.vehicles]!;

    expect(vehicles.status, LegacyValueStatus.malformed);
    expect(vehicles.rawValue, raw);
    expect(vehicles.issues, isNotEmpty);
    expect(report.isReadyForMigration, isFalse);
  });

  test(
    'identifies partially valid collections without dropping bad records',
    () async {
      final rows = [
        vehicle(),
        {'name': 'Record without an ID'},
      ];
      final raw = jsonEncode(rows);
      final store = await createStore({
        LegacyStorageKeys.vehicles: raw,
        LegacyStorageKeys.seeded: 'yes',
      });
      final report = LegacyDataInspector(store).inspect();
      final vehicles = report.collections[LegacyStorageKeys.vehicles]!;

      expect(vehicles.status, LegacyValueStatus.partiallyValid);
      expect(vehicles.recordCount, 2);
      expect(vehicles.validRecordCount, 1);
      expect(vehicles.invalidRecordCount, 1);
      expect(vehicles.rawValue, raw);
      expect(report.isReadyForMigration, isFalse);
    },
  );

  test(
    'detects duplicate record IDs and orphaned vehicle references',
    () async {
      final store = await createStore({
        LegacyStorageKeys.vehicles: jsonEncode([vehicle()]),
        LegacyStorageKeys.services: jsonEncode([
          service(id: 'same-id'),
          service(id: 'same-id', vehicleId: 'missing-vehicle'),
        ]),
        LegacyStorageKeys.seeded: 'yes',
      });
      final report = LegacyDataInspector(store).inspect();
      final messages = report.issues.map((issue) => issue.message).join('\n');

      expect(messages, contains('Duplicate record ID "same-id"'));
      expect(messages, contains('missing-vehicle'));
      expect(report.isReadyForMigration, isFalse);
    },
  );

  test(
    'flags negative values and invalid dates that SQLite cannot safely import',
    () async {
      final invalidService = service()
        ..['cost'] = -1
        ..['date'] = 'not-a-date';
      final store = await createStore({
        LegacyStorageKeys.vehicles: jsonEncode([vehicle()]),
        LegacyStorageKeys.services: jsonEncode([invalidService]),
        LegacyStorageKeys.seeded: 'yes',
      });
      final report = LegacyDataInspector(store).inspect();
      final messages = report.collections[LegacyStorageKeys.services]!.issues
          .map((issue) => issue.message)
          .join('\n');

      expect(messages, contains('valid ISO-8601'));
      expect(messages, contains('cannot be negative'));
      expect(report.isReadyForMigration, isFalse);
    },
  );

  test('detects first-launch sample-data overwrite risk', () async {
    final store = await createStore({
      LegacyStorageKeys.vehicles: jsonEncode([vehicle()]),
      // Seed marker intentionally absent while an existing collection exists.
    });
    final report = LegacyDataInspector(store).inspect();

    expect(report.seedMarker.status, LegacyValueStatus.missing);
    expect(report.sampleDataOverwriteRisk, isTrue);
    expect(report.isReadyForMigration, isFalse);
    expect(
      report.issues.any((issue) => issue.key == LegacyStorageKeys.seeded),
      isTrue,
    );
  });

  test(
    'detects a legacy key stored with an unexpected SharedPreferences type',
    () async {
      final store = await createStore({
        LegacyStorageKeys.vehicles: 42,
        LegacyStorageKeys.seeded: 'yes',
      });
      final report = LegacyDataInspector(store).inspect();

      expect(
        report.collections[LegacyStorageKeys.vehicles]!.status,
        LegacyValueStatus.invalidType,
      );
      expect(report.isReadyForMigration, isFalse);
    },
  );

  test(
    'backup snapshot preserves raw values and key-presence metadata',
    () async {
      const malformedRaw = '  [not valid JSON]\n';
      final store = await createStore({
        LegacyStorageKeys.vehicles: malformedRaw,
        LegacyStorageKeys.services: '[]',
        LegacyStorageKeys.seeded: 'yes',
      });
      final inspector = LegacyDataInspector(store);
      final before = inspector.inspect();
      final snapshot = inspector.createBackupSnapshot(
        createdAt: DateTime.utc(2026, 11, 13, 12),
      );
      final decoded = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      final entries = decoded['entries'] as Map<String, dynamic>;

      expect(decoded['format'], 'maintainly.legacy-shared-preferences-backup');
      expect(decoded['formatVersion'], 1);
      expect(
        (entries[LegacyStorageKeys.vehicles] as Map)['value'],
        malformedRaw,
      );
      expect((entries[LegacyStorageKeys.vehicles] as Map)['keyExists'], isTrue);
      expect(
        (entries[LegacyStorageKeys.expenses] as Map)['keyExists'],
        isFalse,
      );
      expect((entries[LegacyStorageKeys.seeded] as Map)['value'], 'yes');

      // Inspection and snapshot creation are read-only.
      final after = inspector.inspect();
      expect(
        after.collections[LegacyStorageKeys.vehicles]!.rawValue,
        malformedRaw,
      );
      expect(
        after.collections[LegacyStorageKeys.vehicles]!.rawValue,
        before.collections[LegacyStorageKeys.vehicles]!.rawValue,
      );
    },
  );

  test(
    'warns when optional legacy fields are missing but parser defaults exist',
    () async {
      final sparseVehicle = {'id': 'vehicle-1'};
      final store = await createStore({
        LegacyStorageKeys.vehicles: jsonEncode([sparseVehicle]),
        LegacyStorageKeys.seeded: 'yes',
      });
      final report = LegacyDataInspector(store).inspect();
      final vehicles = report.collections[LegacyStorageKeys.vehicles]!;

      expect(vehicles.status, LegacyValueStatus.valid);
      expect(vehicles.validRecordCount, 1);
      expect(vehicles.issues, isNotEmpty);
      expect(vehicles.hasErrors, isFalse);
      expect(report.isReadyForMigration, isFalse);
    },
  );
}
