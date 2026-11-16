import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/data/backup/maintainly_backup.dart';
import 'package:maintainly/data/models/expense.dart';
import 'package:maintainly/data/models/maintenance_reminder.dart';
import 'package:maintainly/data/models/service_record.dart';
import 'package:maintainly/data/models/vehicle.dart';

void main() {
  final createdAt = DateTime.utc(2026, 11, 16, 12);

  Vehicle vehicle({String id = 'vehicle-1', bool archived = true}) => Vehicle(
    id: id,
    name: 'Test car',
    type: 'Car',
    make: 'Toyota',
    model: 'Corolla',
    year: 2022,
    registration: 'ABC-123',
    odometer: 12000,
    purchaseDate: DateTime(2022, 1, 1),
    purchasePrice: 2500000,
    isArchived: archived,
  );

  ServiceRecord service({String id = 'service-1', String vehicleId = 'vehicle-1'}) =>
      ServiceRecord(
        id: id,
        vehicleId: vehicleId,
        title: 'Oil change',
        category: 'Maintenance',
        date: DateTime(2026, 10, 1),
        odometer: 11000,
        cost: 1000,
        mechanic: 'Ali',
        notes: 'Synthetic oil',
        nextDueDate: DateTime(2027, 4, 1),
        nextDueOdometer: 16000,
      );

  VehicleExpense expense({String? sourceServiceId = 'service-1'}) => VehicleExpense(
    id: 'expense-1',
    vehicleId: 'vehicle-1',
    category: 'Parts',
    description: 'Oil filter',
    date: DateTime(2026, 10, 1),
    amount: 500,
    odometer: 11000,
    sourceServiceId: sourceServiceId,
  );

  MaintenanceReminder reminder() => MaintenanceReminder(
    id: 'reminder-1',
    vehicleId: 'vehicle-1',
    title: 'Next oil change',
    dueDate: DateTime(2027, 4, 1),
    dueOdometer: 16000,
    notes: 'Linked to service',
    completed: false,
    sourceServiceId: 'service-1',
  );

  MaintainlyBackup validBackup({
    List<Vehicle>? vehicles,
    List<ServiceRecord>? services,
    List<VehicleExpense>? expenses,
    List<MaintenanceReminder>? reminders,
  }) => MaintainlyBackup(
    createdAtUtc: createdAt,
    vehicles: vehicles ?? [vehicle()],
    services: services ?? [service()],
    expenses: expenses ?? [expense()],
    reminders: reminders ?? [reminder()],
  );

  test('encodes and decodes a complete versioned backup', () {
    final original = validBackup();
    final decoded = MaintainlyBackup.decode(original.encode());

    expect(decoded.createdAtUtc, createdAt);
    expect(decoded.vehicles.single.isArchived, isTrue);
    expect(decoded.expenses.single.sourceServiceId, 'service-1');
    expect(decoded.reminders.single.sourceServiceId, 'service-1');
    expect(decoded.services.single.nextDueOdometer, 16000);
  });

  test('supports an empty but structurally complete backup', () {
    final decoded = MaintainlyBackup.decode(
      validBackup(
        vehicles: [],
        services: [],
        expenses: [],
        reminders: [],
      ).encode(),
    );

    expect(decoded.vehicles, isEmpty);
    expect(decoded.services, isEmpty);
    expect(decoded.expenses, isEmpty);
    expect(decoded.reminders, isEmpty);
  });

  test('rejects invalid JSON, an unknown format, and unsupported versions', () {
    expect(
      () => MaintainlyBackup.decode('{not json'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MaintainlyBackup.decode(jsonEncode({'format': 'other'})),
      throwsA(isA<FormatException>()),
    );

    final unsupported = jsonDecode(validBackup().encode()) as Map<String, dynamic>;
    unsupported['formatVersion'] = 99;
    expect(
      () => MaintainlyBackup.decode(jsonEncode(unsupported)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects missing or incorrectly typed required record fields', () {
    final json = jsonDecode(validBackup().encode()) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;
    final vehicles = data['vehicles'] as List<dynamic>;
    final firstVehicle = Map<String, dynamic>.from(vehicles.single as Map);
    firstVehicle.remove('isArchived');
    data['vehicles'] = [firstVehicle];

    expect(
      () => MaintainlyBackup.decode(jsonEncode(json)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate record IDs and missing vehicle references', () {
    expect(
      () => validBackup(vehicles: [vehicle(), vehicle()]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validBackup(services: [service(vehicleId: 'missing-vehicle')]),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid expense and reminder service relationships', () {
    expect(
      () => validBackup(expenses: [expense(sourceServiceId: 'missing-service')]),
      throwsA(isA<FormatException>()),
    );

    final invalidReminder = MaintenanceReminder(
      id: 'reminder-1',
      vehicleId: 'vehicle-1',
      title: 'Reminder',
      dueDate: null,
      dueOdometer: null,
      notes: '',
      completed: false,
      sourceServiceId: 'missing-service',
    );
    expect(
      () => validBackup(reminders: [invalidReminder]),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects linked expenses whose total exceeds the service cost', () {
    final lowCostService = ServiceRecord(
      id: 'service-1',
      vehicleId: 'vehicle-1',
      title: 'Oil change',
      category: 'Maintenance',
      date: DateTime(2026, 10, 1),
      odometer: 11000,
      cost: 100,
      mechanic: '',
      notes: '',
    );
    expect(
      () => validBackup(services: [lowCostService]),
      throwsA(isA<FormatException>()),
    );
  });
}
