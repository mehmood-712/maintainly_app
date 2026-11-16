import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/application/maintainly_controller.dart';
import 'package:maintainly/core/data/legacy_storage_keys.dart';
import 'package:maintainly/core/data/local_store.dart';
import 'package:maintainly/data/models/service_record.dart';
import 'package:maintainly/data/models/expense.dart';
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
      LegacyStorageKeys.reminders: jsonEncode([
        {
          'id': 'manual-reminder',
          'vehicleId': 'vehicle-1',
          'title': 'Manual reminder',
          'dueDate': null,
          'dueOdometer': 60000,
          'notes': '',
          'completed': false,
        },
      ]),
      LegacyStorageKeys.seeded: 'yes',
    });
    final controller = MaintainlyController(
      MaintainlyRepository(await LocalStore.create()),
    );
    await controller.initialize();
    return controller;
  }

  ServiceRecord service({
    String title = 'Oil change',
    int? nextDueOdometer = 55000,
    bool noNextDue = false,
  }) => ServiceRecord(
    id: 'service-1',
    vehicleId: 'vehicle-1',
    title: title,
    category: 'Maintenance',
    date: DateTime(2026, 11, 1),
    odometer: 51000,
    cost: 5000,
    mechanic: '',
    notes: '',
    nextDueDate: noNextDue ? null : DateTime(2027, 5, 1),
    nextDueOdometer: nextDueOdometer,
  );

  test(
    'archiving and restoring a vehicle preserves all related history',
    () async {
      final controller = await createController();
      await controller.addService(service());
      await controller.saveExpense(
        VehicleExpense(
          id: 'expense-1',
          vehicleId: 'vehicle-1',
          category: 'Parts',
          description: 'Oil filter',
          date: DateTime(2026, 11, 1),
          amount: 1000,
          odometer: 51000,
        ),
      );
      final reminderCount = controller.reminders.length;

      await controller.archiveVehicle('vehicle-1');
      expect(controller.activeVehicles, isEmpty);
      expect(controller.archivedVehicles, hasLength(1));
      expect(controller.services, hasLength(1));
      expect(controller.expenses, hasLength(1));
      expect(controller.reminders, hasLength(reminderCount));

      await controller.restoreVehicle('vehicle-1');
      expect(controller.activeVehicles, hasLength(1));
      expect(controller.archivedVehicles, isEmpty);
    },
  );

  test(
    'service-linked expenses remain visible but are not double counted',
    () async {
      final controller = await createController();
      await controller.addService(service());
      await controller.saveExpense(
        VehicleExpense(
          id: 'expense-1',
          vehicleId: 'vehicle-1',
          category: 'Parts',
          description: 'Parts itemized in service invoice',
          date: DateTime(2026, 11, 1),
          amount: 1200,
          odometer: 51000,
          sourceServiceId: 'service-1',
        ),
      );
      expect(controller.expenses, hasLength(1));
      expect(controller.totalExpenses, 0);
      expect(controller.serviceSpend, 5000);
      expect(controller.totalSpend, 5000);

      await controller.deleteService('service-1');
      expect(controller.expenses.single.sourceServiceId, isNull);
      expect(controller.totalSpend, 1200);
    },
  );

  test('rejects linked expense amounts above service cost', () async {
    final controller = await createController();
    await controller.addService(service());
    await expectLater(
      controller.saveExpense(
        VehicleExpense(
          id: 'expense-too-large',
          vehicleId: 'vehicle-1',
          category: 'Parts',
          description: 'Over service total',
          date: DateTime(2026, 11, 1),
          amount: 5001,
          odometer: 51000,
          sourceServiceId: 'service-1',
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(controller.expenses, isEmpty);
  });

  test(
    'creates a linked reminder when a service has a next due value',
    () async {
      final controller = await createController();

      await controller.addService(service());

      final linked = controller.reminders.singleWhere(
        (reminder) => reminder.sourceServiceId == 'service-1',
      );
      expect(linked.title, 'Oil change');
      expect(linked.dueOdometer, 55000);
      expect(
        controller.reminders.any((r) => r.id == 'manual-reminder'),
        isTrue,
      );
    },
  );

  test(
    'updates the existing linked reminder when its service is edited',
    () async {
      final controller = await createController();
      await controller.addService(service());
      final originalReminder = controller.reminders.singleWhere(
        (reminder) => reminder.sourceServiceId == 'service-1',
      );
      await controller.toggleReminder(originalReminder.id);

      await controller.saveService(
        service(title: 'Updated oil change', nextDueOdometer: 57000),
      );

      final linked = controller.reminders.singleWhere(
        (reminder) => reminder.sourceServiceId == 'service-1',
      );
      expect(linked.id, originalReminder.id);
      expect(linked.title, 'Updated oil change');
      expect(linked.dueOdometer, 57000);
      expect(linked.completed, isFalse);
      expect(
        controller.reminders.where((r) => r.sourceServiceId == 'service-1'),
        hasLength(1),
      );
    },
  );

  test('deleting a service removes only its linked reminder', () async {
    final controller = await createController();
    await controller.addService(service());

    await controller.deleteService('service-1');

    expect(controller.services, isEmpty);
    expect(controller.reminders.map((r) => r.id), ['manual-reminder']);
  });

  test('removing next due values removes the linked reminder but keeps manual reminders', () async {
    final controller = await createController();
    await controller.addService(service());

    await controller.saveService(
      service(nextDueOdometer: null, noNextDue: true),
    );

    expect(controller.reminders.map((r) => r.id), ['manual-reminder']);
  });
}
