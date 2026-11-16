import 'dart:convert';

import '../models/expense.dart';
import '../models/maintenance_reminder.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';
import '../validation/maintainly_data_validator.dart';

/// A portable, versioned backup of the complete Maintainly data snapshot.
///
/// This is deliberately separate from [LegacyBackupSnapshot]: that older
/// snapshot preserves raw SharedPreferences values for migration recovery,
/// while this format represents the current domain data in a user-exportable
/// JSON structure.
class MaintainlyBackup {
  MaintainlyBackup({
    required this.createdAtUtc,
    required List<Vehicle> vehicles,
    required List<ServiceRecord> services,
    required List<VehicleExpense> expenses,
    required List<MaintenanceReminder> reminders,
  }) : vehicles = List.unmodifiable(vehicles),
       services = List.unmodifiable(services),
       expenses = List.unmodifiable(expenses),
       reminders = List.unmodifiable(reminders) {
    _validate();
  }

  static const String format = 'maintainly.full-backup';
  static const int formatVersion = 1;

  final DateTime createdAtUtc;
  final List<Vehicle> vehicles;
  final List<ServiceRecord> services;
  final List<VehicleExpense> expenses;
  final List<MaintenanceReminder> reminders;

  Map<String, Object?> toJson() => {
    'format': format,
    'formatVersion': formatVersion,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'source': 'maintainly',
    'data': {
      'vehicles': vehicles.map((item) => item.toJson()).toList(),
      'services': services.map((item) => item.toJson()).toList(),
      'expenses': expenses.map((item) => item.toJson()).toList(),
      'reminders': reminders.map((item) => item.toJson()).toList(),
    },
  };

  String encode({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  factory MaintainlyBackup.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Backup is not valid JSON: ${error.message}');
    }

    final root = _asMap(decoded, 'backup');
    if (root['format'] != format) {
      throw const FormatException('This file is not a Maintainly backup.');
    }
    if (root['formatVersion'] != formatVersion) {
      throw FormatException(
        'Unsupported Maintainly backup version: ${root['formatVersion']}.',
      );
    }
    if (root['source'] != 'maintainly') {
      throw const FormatException('Backup source metadata is invalid.');
    }

    final createdAtUtc = _requiredDate(root, 'createdAtUtc', 'backup');
    final data = _asMap(root['data'], 'backup.data');
    final vehicles = _requiredList(data, 'vehicles', 'backup.data')
        .asMap()
        .entries
        .map((entry) => _decodeVehicle(entry.value, 'vehicles[${entry.key}]'))
        .toList();
    final services = _requiredList(data, 'services', 'backup.data')
        .asMap()
        .entries
        .map((entry) => _decodeService(entry.value, 'services[${entry.key}]'))
        .toList();
    final expenses = _requiredList(data, 'expenses', 'backup.data')
        .asMap()
        .entries
        .map((entry) => _decodeExpense(entry.value, 'expenses[${entry.key}]'))
        .toList();
    final reminders = _requiredList(data, 'reminders', 'backup.data')
        .asMap()
        .entries
        .map((entry) => _decodeReminder(entry.value, 'reminders[${entry.key}]'))
        .toList();

    return MaintainlyBackup(
      createdAtUtc: createdAtUtc,
      vehicles: vehicles,
      services: services,
      expenses: expenses,
      reminders: reminders,
    );
  }

  void _validate() {
    _requireUniqueIds(vehicles.map((item) => item.id), 'vehicle');
    _requireUniqueIds(services.map((item) => item.id), 'service');
    _requireUniqueIds(expenses.map((item) => item.id), 'expense');
    _requireUniqueIds(reminders.map((item) => item.id), 'reminder');

    final vehicleById = {for (final item in vehicles) item.id: item};
    final serviceById = {for (final item in services) item.id: item};

    for (final service in services) {
      if (!vehicleById.containsKey(service.vehicleId)) {
        throw FormatException(
          'Service "${service.id}" refers to missing vehicle "${service.vehicleId}".',
        );
      }
    }
    for (final expense in expenses) {
      if (!vehicleById.containsKey(expense.vehicleId)) {
        throw FormatException(
          'Expense "${expense.id}" refers to missing vehicle "${expense.vehicleId}".',
        );
      }
    }
    for (final reminder in reminders) {
      if (!vehicleById.containsKey(reminder.vehicleId)) {
        throw FormatException(
          'Reminder "${reminder.id}" refers to missing vehicle "${reminder.vehicleId}".',
        );
      }
      final sourceServiceId = reminder.sourceServiceId;
      if (sourceServiceId != null) {
        final service = serviceById[sourceServiceId];
        if (service == null || service.vehicleId != reminder.vehicleId) {
          throw FormatException(
            'Reminder "${reminder.id}" has an invalid source service link.',
          );
        }
      }
    }

    try {
      MaintainlyDataValidator.validateSnapshot(
        vehicles: vehicles,
        services: services,
        expenses: expenses,
        reminders: reminders,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Backup data failed validation: ${error.message}');
    }
  }

  static void _requireUniqueIds(Iterable<String> ids, String kind) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.trim().isEmpty || !seen.add(id)) {
        throw FormatException('Backup contains an empty or duplicate $kind ID.');
      }
    }
  }

  static Vehicle _decodeVehicle(Object? value, String path) {
    final json = _asMap(value, path);
    return Vehicle(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      type: _requiredString(json, 'type', path),
      make: _requiredString(json, 'make', path),
      model: _requiredString(json, 'model', path),
      year: _requiredInt(json, 'year', path),
      registration: _requiredString(json, 'registration', path),
      odometer: _requiredInt(json, 'odometer', path),
      purchaseDate: _optionalDate(json, 'purchaseDate', path),
      purchasePrice: _requiredDouble(json, 'purchasePrice', path),
      isArchived: _requiredBool(json, 'isArchived', path),
    );
  }

  static ServiceRecord _decodeService(Object? value, String path) {
    final json = _asMap(value, path);
    return ServiceRecord(
      id: _requiredString(json, 'id', path),
      vehicleId: _requiredString(json, 'vehicleId', path),
      title: _requiredString(json, 'title', path),
      category: _requiredString(json, 'category', path),
      date: _requiredDate(json, 'date', path),
      odometer: _requiredInt(json, 'odometer', path),
      cost: _requiredDouble(json, 'cost', path),
      mechanic: _requiredString(json, 'mechanic', path),
      notes: _requiredString(json, 'notes', path),
      nextDueDate: _optionalDate(json, 'nextDueDate', path),
      nextDueOdometer: _optionalInt(json, 'nextDueOdometer', path),
    );
  }

  static VehicleExpense _decodeExpense(Object? value, String path) {
    final json = _asMap(value, path);
    return VehicleExpense(
      id: _requiredString(json, 'id', path),
      vehicleId: _requiredString(json, 'vehicleId', path),
      category: _requiredString(json, 'category', path),
      description: _requiredString(json, 'description', path),
      date: _requiredDate(json, 'date', path),
      amount: _requiredDouble(json, 'amount', path),
      odometer: _requiredInt(json, 'odometer', path),
      sourceServiceId: _optionalString(json, 'sourceServiceId', path),
    );
  }

  static MaintenanceReminder _decodeReminder(Object? value, String path) {
    final json = _asMap(value, path);
    return MaintenanceReminder(
      id: _requiredString(json, 'id', path),
      vehicleId: _requiredString(json, 'vehicleId', path),
      title: _requiredString(json, 'title', path),
      dueDate: _optionalDate(json, 'dueDate', path),
      dueOdometer: _optionalInt(json, 'dueOdometer', path),
      notes: _requiredString(json, 'notes', path),
      completed: _requiredBool(json, 'completed', path),
      sourceServiceId: _optionalString(json, 'sourceServiceId', path),
    );
  }

  static Map<String, dynamic> _asMap(Object? value, String path) {
    if (value is! Map) {
      throw FormatException('$path must be a JSON object.');
    }
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw FormatException('$path contains invalid object keys.');
    }
  }

  static List<dynamic> _requiredList(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value is! List) {
      throw FormatException('$path.$key must be a JSON array.');
    }
    return value;
  }

  static String _requiredString(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('$path.$key must be a string.');
    }
    return value;
  }

  static String? _optionalString(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    if (!json.containsKey(key)) {
      throw FormatException('$path.$key is missing.');
    }
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$path.$key must be a string or null.');
    }
    return value;
  }

  static int _requiredInt(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value is! num || !value.isFinite || value % 1 != 0) {
      throw FormatException('$path.$key must be a whole number.');
    }
    return value.toInt();
  }

  static int? _optionalInt(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    if (!json.containsKey(key)) {
      throw FormatException('$path.$key is missing.');
    }
    final value = json[key];
    if (value == null) return null;
    if (value is! num || !value.isFinite || value % 1 != 0) {
      throw FormatException('$path.$key must be a whole number or null.');
    }
    return value.toInt();
  }

  static double _requiredDouble(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('$path.$key must be a finite number.');
    }
    return value.toDouble();
  }

  static bool _requiredBool(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException('$path.$key must be true or false.');
    }
    return value;
  }

  static DateTime _requiredDate(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('$path.$key must be an ISO-8601 date string.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$path.$key contains an invalid date.');
    }
    return parsed;
  }

  static DateTime? _optionalDate(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    if (!json.containsKey(key)) {
      throw FormatException('$path.$key is missing.');
    }
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$path.$key must be an ISO-8601 date string or null.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$path.$key contains an invalid date.');
    }
    return parsed;
  }
}
