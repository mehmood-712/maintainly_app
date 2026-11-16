import '../models/expense.dart';
import '../models/maintenance_reminder.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';

/// Shared validation for values that must remain valid in both the legacy
/// snapshot and SQLite persistence paths.
abstract final class MaintainlyDataValidator {
  static void validateVehicle(Vehicle vehicle) {
    _requireNonNegativeInteger('vehicle.odometer', vehicle.odometer);
    _requireNonNegativeFiniteNumber(
      'vehicle.purchasePrice',
      vehicle.purchasePrice,
    );
  }

  static void validateService(ServiceRecord service) {
    _requireNonNegativeInteger('service.odometer', service.odometer);
    _requireNonNegativeFiniteNumber('service.cost', service.cost);
    final nextDueOdometer = service.nextDueOdometer;
    if (nextDueOdometer != null) {
      _requireNonNegativeInteger('service.nextDueOdometer', nextDueOdometer);
    }
  }

  static void validateExpense(VehicleExpense expense) {
    _requireNonNegativeInteger('expense.odometer', expense.odometer);
    _requireNonNegativeFiniteNumber('expense.amount', expense.amount);
  }

  static void validateReminder(MaintenanceReminder reminder) {
    final dueOdometer = reminder.dueOdometer;
    if (dueOdometer != null) {
      _requireNonNegativeInteger('reminder.dueOdometer', dueOdometer);
    }
  }

  static void validateSnapshot({
    required List<Vehicle> vehicles,
    required List<ServiceRecord> services,
    required List<VehicleExpense> expenses,
    required List<MaintenanceReminder> reminders,
  }) {
    for (final vehicle in vehicles) {
      validateVehicle(vehicle);
    }
    for (final service in services) {
      validateService(service);
    }
    final serviceById = {for (final service in services) service.id: service};
    for (final expense in expenses) {
      validateExpense(expense);
      final sourceServiceId = expense.sourceServiceId;
      if (sourceServiceId != null) {
        final service = serviceById[sourceServiceId];
        if (service == null || service.vehicleId != expense.vehicleId) {
          throw ArgumentError.value(
            sourceServiceId,
            'expense.sourceServiceId',
            'Must reference an existing service for the same vehicle.',
          );
        }
      }
    }
    final linkedTotals = <String, double>{};
    for (final expense in expenses) {
      final sourceServiceId = expense.sourceServiceId;
      if (sourceServiceId != null) {
        linkedTotals.update(
          sourceServiceId,
          (total) => total + expense.amount,
          ifAbsent: () => expense.amount,
        );
      }
    }
    for (final entry in linkedTotals.entries) {
      if (entry.value > serviceById[entry.key]!.cost) {
        throw ArgumentError.value(
          entry.value,
          'expense.sourceServiceId',
          'Linked expense total cannot exceed the source service cost.',
        );
      }
    }
    for (final reminder in reminders) {
      validateReminder(reminder);
    }
  }

  static void _requireNonNegativeInteger(String field, int value) {
    if (value < 0) {
      throw ArgumentError.value(value, field, 'Must be zero or greater.');
    }
  }

  static void _requireNonNegativeFiniteNumber(String field, double value) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        field,
        'Must be a finite number that is zero or greater.',
      );
    }
  }
}
