import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/core/data/legacy_storage_keys.dart';
import 'package:maintainly/core/data/local_store.dart';
import 'package:maintainly/data/repositories/maintainly_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> createStore(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return LocalStore.create();
  }

  Map<String, Object?> validVehicle() => {
    'id': 'vehicle-1',
    'name': 'Daily car',
    'type': 'Car',
    'make': 'Toyota',
    'model': 'Corolla',
    'year': 2022,
    'registration': 'ABC-123',
    'odometer': 50000,
    'purchaseDate': null,
    'purchasePrice': 2500000.0,
  };

  test(
    'does not seed sample data over existing keys when seed marker is missing',
    () async {
      final rawVehicles = jsonEncode([validVehicle()]);
      final store = await createStore({
        LegacyStorageKeys.vehicles: rawVehicles,
      });
      final repository = MaintainlyRepository(store);

      final data = await repository.load();

      expect(data.vehicles, hasLength(1));
      expect(data.vehicles.single.id, 'vehicle-1');
      expect(data.services, isEmpty);
      expect(store.readRaw(LegacyStorageKeys.vehicles), rawVehicles);
      expect(store.containsKey(LegacyStorageKeys.seeded), isFalse);
    },
  );

  test(
    'preserves malformed legacy JSON when the seed marker is missing',
    () async {
      const malformed = '[{"id":"incomplete"';
      final store = await createStore({LegacyStorageKeys.vehicles: malformed});
      final repository = MaintainlyRepository(store);

      final data = await repository.load();

      expect(data.vehicles, isEmpty);
      expect(store.readRaw(LegacyStorageKeys.vehicles), malformed);
      expect(store.containsKey(LegacyStorageKeys.seeded), isFalse);
    },
  );

  test('seeds sample data only for a completely empty first launch', () async {
    final store = await createStore({});
    final repository = MaintainlyRepository(store);

    final data = await repository.load();

    expect(data.vehicles, hasLength(3));
    expect(store.readRaw(LegacyStorageKeys.seeded), 'yes');
    for (final key in LegacyStorageKeys.collections) {
      expect(store.containsKey(key), isTrue);
    }
  });

  test('refuses to overwrite malformed legacy JSON during save', () async {
    const malformed = '[{"id":"broken"';
    final store = await createStore({
      LegacyStorageKeys.vehicles: malformed,
      LegacyStorageKeys.seeded: 'yes',
    });
    final repository = MaintainlyRepository(store);

    await expectLater(
      repository.save(
        const MaintainlyData(
          vehicles: [],
          services: [],
          expenses: [],
          reminders: [],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(store.readRaw(LegacyStorageKeys.vehicles), malformed);
  });

  test(
    'refuses to normalize and overwrite a legacy record with missing fields',
    () async {
      final raw = jsonEncode([
        {'id': 'vehicle-1'},
      ]);
      final store = await createStore({
        LegacyStorageKeys.vehicles: raw,
        LegacyStorageKeys.seeded: 'yes',
      });
      final repository = MaintainlyRepository(store);
      final data = await repository.load();

      await expectLater(repository.save(data), throwsA(isA<StateError>()));
      expect(store.readRaw(LegacyStorageKeys.vehicles), raw);
    },
  );

  test(
    'repairs a missing seed marker after saving a valid existing dataset',
    () async {
      final store = await createStore({
        LegacyStorageKeys.vehicles: jsonEncode([validVehicle()]),
      });
      final repository = MaintainlyRepository(store);
      final data = await repository.load();

      expect(store.containsKey(LegacyStorageKeys.seeded), isFalse);
      await repository.save(data);

      expect(store.readRaw(LegacyStorageKeys.seeded), 'yes');
      expect(jsonDecode(store.read(LegacyStorageKeys.vehicles)!), isA<List>());
      expect(data.vehicles, hasLength(1));
    },
  );
}
