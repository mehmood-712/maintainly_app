import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/data/mappers/maintainly_database_mapper.dart';
import 'package:maintainly/data/models/expense.dart';
import 'package:maintainly/data/models/maintenance_reminder.dart';
import 'package:maintainly/data/models/service_record.dart';
import 'package:maintainly/data/models/vehicle.dart';

void main() {
  group('MaintainlyDatabaseMapper', () {
    test(
      'round-trips all vehicle fields and preserves nullable purchase date',
      () {
        final vehicle = Vehicle(
          id: 'vehicle-1',
          name: 'Daily Drive',
          type: 'Car',
          make: 'Toyota',
          model: 'Corolla',
          year: 2021,
          registration: 'ABC-123',
          odometer: 68420,
          purchaseDate: DateTime(2022, 3, 12, 10, 20, 30, 123, 456),
          purchasePrice: 4250000.75,
          isArchived: true,
        );

        final restored = MaintainlyDatabaseMapper.vehicleFromRow(
          MaintainlyDatabaseMapper.vehicleToRow(vehicle),
        );

        expect(restored.toJson(), vehicle.toJson());
      },
    );

    test('round-trips service dates and nullable next-due fields', () {
      final service = ServiceRecord(
        id: 'service-1',
        vehicleId: 'vehicle-1',
        title: 'Oil change',
        category: 'Maintenance',
        date: DateTime(2025, 6, 7, 9, 15, 10, 555, 678),
        odometer: 45000,
        cost: 12500.50,
        mechanic: 'Workshop',
        notes: 'Synthetic oil',
        nextDueDate: null,
        nextDueOdometer: null,
      );

      final restored = MaintainlyDatabaseMapper.serviceRecordFromRow(
        MaintainlyDatabaseMapper.serviceRecordToRow(service),
      );

      expect(restored.toJson(), service.toJson());
    });

    test('round-trips expense fields and DateTime precision', () {
      final expense = VehicleExpense(
        id: 'expense-1',
        vehicleId: 'vehicle-1',
        category: 'Fuel',
        description: 'Petrol refill',
        date: DateTime(2026, 1, 2, 13, 14, 15, 123, 456),
        amount: 9500.25,
        odometer: 68210,
        sourceServiceId: 'service-1',
      );

      final restored = MaintainlyDatabaseMapper.expenseFromRow(
        MaintainlyDatabaseMapper.expenseToRow(expense),
      );

      expect(restored.toJson(), expense.toJson());
    });

    test('round-trips reminder nullable due fields and boolean flag', () {
      final reminder = MaintenanceReminder(
        id: 'reminder-1',
        vehicleId: 'vehicle-1',
        title: 'Inspection',
        dueDate: null,
        dueOdometer: 80000,
        notes: 'Check brakes',
        completed: true,
        sourceServiceId: 'service-1',
      );

      final row = MaintainlyDatabaseMapper.reminderToRow(reminder);
      expect(row['completed'], 1);
      expect(row['source_service_id'], 'service-1');
      final restored = MaintainlyDatabaseMapper.reminderFromRow(row);

      expect(restored.toJson(), reminder.toJson());
    });

    test('rejects invalid boolean values instead of guessing', () {
      expect(
        () => MaintainlyDatabaseMapper.reminderFromRow({
          'id': 'reminder-1',
          'vehicle_id': 'vehicle-1',
          'title': 'Inspection',
          'due_date': null,
          'due_odometer': null,
          'notes': '',
          'completed': 2,
        }),
        throwsFormatException,
      );
    });
  });
}
