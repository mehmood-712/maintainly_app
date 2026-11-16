import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/application/maintainly_controller.dart';
import 'package:maintainly/core/data/legacy_storage_keys.dart';
import 'package:maintainly/core/data/local_store.dart';
import 'package:maintainly/data/models/expense.dart';
import 'package:maintainly/data/models/maintenance_reminder.dart';
import 'package:maintainly/data/models/service_record.dart';
// import 'package:maintainly/data/models/vehicle.dart';
import 'package:maintainly/data/repositories/maintainly_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MaintainlyController> createController() async {
    SharedPreferences.setMockInitialValues({
      LegacyStorageKeys.vehicles: jsonEncode([
        {
          'id': 'vehicle-1',
          'name': 'Test car',
          'type': 'Car',
          'make': 'Toyota',
          'model': 'Corolla',
          'year': 2022,
          'registration': 'ABC-123',
          'odometer': 50000,
          'purchaseDate': null,
          'purchasePrice': 0,
        },
      ]),
      LegacyStorageKeys.services: jsonEncode([]),
      LegacyStorageKeys.expenses: jsonEncode([]),
      LegacyStorageKeys.reminders: jsonEncode([]),
      LegacyStorageKeys.seeded: 'yes',
    });
    final controller = MaintainlyController(
      MaintainlyRepository(await LocalStore.create()),
    );
    await controller.initialize();
    return controller;
  }

  test('rejects a negative vehicle odometer before changing state', () async {
    final controller = await createController();
    final vehicle = controller.vehicles.single.copyWith(odometer: -1);

    await expectLater(
      controller.saveVehicle(vehicle),
      throwsA(isA<ArgumentError>()),
    );

    expect(controller.vehicles.single.odometer, 50000);
  });

  test('rejects non-finite or negative vehicle purchase prices', () async {
    final controller = await createController();
    final vehicle = controller.vehicles.single.copyWith(
      purchasePrice: double.nan,
    );

    await expectLater(
      controller.saveVehicle(vehicle),
      throwsA(isA<ArgumentError>()),
    );
    expect(controller.vehicles.single.purchasePrice, 0);
  });

  test(
    'rejects negative service odometer, cost, and next due odometer',
    () async {
      final controller = await createController();
      ServiceRecord service({
        int odometer = 100,
        double cost = 100,
        int? nextDue,
      }) => ServiceRecord(
        id: 'service-1',
        vehicleId: 'vehicle-1',
        title: 'Oil change',
        category: 'Maintenance',
        date: DateTime(2026, 11, 1),
        odometer: odometer,
        cost: cost,
        mechanic: '',
        notes: '',
        nextDueOdometer: nextDue,
      );

      await expectLater(
        controller.saveService(service(odometer: -1)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        controller.saveService(service(cost: -1)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        controller.saveService(service(nextDue: -1)),
        throwsA(isA<ArgumentError>()),
      );
      expect(controller.services, isEmpty);
    },
  );

  test('rejects negative expense odometer and non-finite amount', () async {
    final controller = await createController();
    VehicleExpense expense({int odometer = 100, double amount = 100}) =>
        VehicleExpense(
          id: 'expense-1',
          vehicleId: 'vehicle-1',
          category: 'Fuel',
          description: 'Fuel',
          date: DateTime(2026, 11, 1),
          amount: amount,
          odometer: odometer,
        );

    await expectLater(
      controller.saveExpense(expense(odometer: -1)),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      controller.saveExpense(expense(amount: double.infinity)),
      throwsA(isA<ArgumentError>()),
    );
    expect(controller.expenses, isEmpty);
  });

  test('rejects a negative reminder due odometer', () async {
    final controller = await createController();

    await expectLater(
      controller.addReminder(
        const MaintenanceReminder(
          id: 'reminder-1',
          vehicleId: 'vehicle-1',
          title: 'Oil change',
          dueDate: null,
          dueOdometer: -1,
          notes: '',
          completed: false,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(controller.reminders, isEmpty);
  });
}
