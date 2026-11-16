import '../models/expense.dart';
import '../models/maintenance_reminder.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';

/// Converts existing Maintainly domain models to and from SQLite row maps.
///
/// DateTime values are stored as Unix epoch microseconds. Nullable dates stay
/// SQL NULL. Boolean values are stored as SQLite INTEGER 0/1. The domain models retain backwards-compatible JSON defaults for newly optional fields.
abstract final class MaintainlyDatabaseMapper {
  static Map<String, Object?> vehicleToRow(Vehicle value) => {
    'id': value.id,
    'name': value.name,
    'type': value.type,
    'make': value.make,
    'model': value.model,
    'year': value.year,
    'registration': value.registration,
    'odometer': value.odometer,
    'purchase_date': _dateToSql(value.purchaseDate),
    'purchase_price': value.purchasePrice,
    'is_archived': value.isArchived ? 1 : 0,
  };

  static Vehicle vehicleFromRow(Map<String, Object?> row) => Vehicle(
    id: _requiredString(row, 'id'),
    name: _requiredString(row, 'name'),
    type: _requiredString(row, 'type'),
    make: _requiredString(row, 'make'),
    model: _requiredString(row, 'model'),
    year: _requiredInt(row, 'year'),
    registration: _requiredString(row, 'registration'),
    odometer: _requiredInt(row, 'odometer'),
    purchaseDate: _dateFromSql(row['purchase_date'], 'purchase_date'),
    purchasePrice: _requiredDouble(row, 'purchase_price'),
    isArchived: _requiredBool(row, 'is_archived'),
  );

  static Map<String, Object?> serviceRecordToRow(ServiceRecord value) => {
    'id': value.id,
    'vehicle_id': value.vehicleId,
    'title': value.title,
    'category': value.category,
    'date': _dateToSql(value.date),
    'odometer': value.odometer,
    'cost': value.cost,
    'mechanic': value.mechanic,
    'notes': value.notes,
    'next_due_date': _dateToSql(value.nextDueDate),
    'next_due_odometer': value.nextDueOdometer,
  };

  static ServiceRecord serviceRecordFromRow(Map<String, Object?> row) =>
      ServiceRecord(
        id: _requiredString(row, 'id'),
        vehicleId: _requiredString(row, 'vehicle_id'),
        title: _requiredString(row, 'title'),
        category: _requiredString(row, 'category'),
        date: _requiredDate(row, 'date'),
        odometer: _requiredInt(row, 'odometer'),
        cost: _requiredDouble(row, 'cost'),
        mechanic: _requiredString(row, 'mechanic'),
        notes: _requiredString(row, 'notes'),
        nextDueDate: _dateFromSql(row['next_due_date'], 'next_due_date'),
        nextDueOdometer: _nullableInt(row, 'next_due_odometer'),
      );

  static Map<String, Object?> expenseToRow(VehicleExpense value) => {
    'id': value.id,
    'vehicle_id': value.vehicleId,
    'category': value.category,
    'description': value.description,
    'date': _dateToSql(value.date),
    'amount': value.amount,
    'odometer': value.odometer,
    'source_service_id': value.sourceServiceId,
  };

  static VehicleExpense expenseFromRow(Map<String, Object?> row) =>
      VehicleExpense(
        id: _requiredString(row, 'id'),
        vehicleId: _requiredString(row, 'vehicle_id'),
        category: _requiredString(row, 'category'),
        description: _requiredString(row, 'description'),
        date: _requiredDate(row, 'date'),
        amount: _requiredDouble(row, 'amount'),
        odometer: _requiredInt(row, 'odometer'),
        sourceServiceId: row['source_service_id'] as String?,
      );

  static Map<String, Object?> reminderToRow(MaintenanceReminder value) => {
    'id': value.id,
    'vehicle_id': value.vehicleId,
    'title': value.title,
    'due_date': _dateToSql(value.dueDate),
    'due_odometer': value.dueOdometer,
    'notes': value.notes,
    'completed': value.completed ? 1 : 0,
    'source_service_id': value.sourceServiceId,
  };

  static MaintenanceReminder reminderFromRow(Map<String, Object?> row) =>
      MaintenanceReminder(
        id: _requiredString(row, 'id'),
        vehicleId: _requiredString(row, 'vehicle_id'),
        title: _requiredString(row, 'title'),
        dueDate: _dateFromSql(row['due_date'], 'due_date'),
        dueOdometer: _nullableInt(row, 'due_odometer'),
        notes: _requiredString(row, 'notes'),
        completed: _requiredBool(row, 'completed'),
        sourceServiceId: row['source_service_id'] as String?,
      );

  static int? _dateToSql(DateTime? value) => value?.microsecondsSinceEpoch;

  static DateTime? _dateFromSql(Object? value, String field) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMicrosecondsSinceEpoch(value);
    if (value is num && value.isFinite) {
      return DateTime.fromMicrosecondsSinceEpoch(value.toInt());
    }
    throw FormatException('Expected an integer epoch for "$field".');
  }

  static DateTime _requiredDate(Map<String, Object?> row, String field) {
    final value = _dateFromSql(row[field], field);
    if (value == null) {
      throw FormatException('Required date "$field" is NULL.');
    }
    return value;
  }

  static String _requiredString(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is String) return value;
    throw FormatException('Expected a string for "$field".');
  }

  static int _requiredInt(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.toInt()) {
      return value.toInt();
    }
    throw FormatException('Expected an integer for "$field".');
  }

  static int? _nullableInt(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.toInt()) {
      return value.toInt();
    }
    throw FormatException('Expected an integer or NULL for "$field".');
  }

  static double _requiredDouble(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Expected a finite number for "$field".');
  }

  static bool _requiredBool(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value == 0) return false;
    if (value == 1) return true;
    throw FormatException('Expected 0 or 1 for "$field".');
  }
}
