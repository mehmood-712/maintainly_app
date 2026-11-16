import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/core/data/local_store.dart';
import 'package:maintainly/data/models/expense.dart';
import 'package:maintainly/data/models/maintenance_reminder.dart';
import 'package:maintainly/data/models/service_record.dart';
import 'package:maintainly/data/models/vehicle.dart';
import 'package:maintainly/data/repositories/maintainly_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'repository rejects invalid numeric snapshots before persistence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = MaintainlyRepository(await LocalStore.create());
      final invalidVehicle = Vehicle(
        id: 'vehicle-1',
        name: 'Test car',
        type: 'Car',
        make: 'Toyota',
        model: 'Corolla',
        year: 2022,
        registration: 'ABC-123',
        odometer: -1,
        purchaseDate: null,
        purchasePrice: 0,
      );

      await expectLater(
        repository.save(
          MaintainlyData(
            vehicles: [invalidVehicle],
            services: const <ServiceRecord>[],
            expenses: const <VehicleExpense>[],
            reminders: const <MaintenanceReminder>[],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test(
    'rejects expense links to missing or different-vehicle services',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = MaintainlyRepository(await LocalStore.create());
      final vehicle = Vehicle(
        id: 'vehicle-1',
        name: 'Car',
        type: 'Car',
        make: '',
        model: '',
        year: 2024,
        registration: '',
        odometer: 100,
        purchaseDate: null,
        purchasePrice: 0,
      );
      final otherVehicle = Vehicle(
        id: 'vehicle-2',
        name: 'Other car',
        type: 'Car',
        make: '',
        model: '',
        year: 2024,
        registration: '',
        odometer: 100,
        purchaseDate: null,
        purchasePrice: 0,
      );
      final service = ServiceRecord(
        id: 'service-1',
        vehicleId: 'vehicle-2',
        title: 'Repair',
        category: 'Repair',
        date: DateTime(2026, 11, 1),
        odometer: 100,
        cost: 500,
        mechanic: '',
        notes: '',
      );
      final expense = VehicleExpense(
        id: 'expense-1',
        vehicleId: 'vehicle-1',
        category: 'Parts',
        description: 'Part',
        date: DateTime(2026, 11, 1),
        amount: 100,
        odometer: 100,
        sourceServiceId: 'service-1',
      );
      await expectLater(
        repository.save(
          MaintainlyData(
            vehicles: [vehicle, otherVehicle],
            services: [service],
            expenses: [expense],
            reminders: [],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
