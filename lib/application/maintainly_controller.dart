import 'package:flutter/foundation.dart';

import '../data/models/expense.dart';
import '../data/models/maintenance_reminder.dart';
import '../data/models/service_record.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/maintainly_repository.dart';
import '../data/validation/maintainly_data_validator.dart';

class MaintainlyController extends ChangeNotifier {
  MaintainlyController(this._repository);
  final MaintainlyRepository _repository;

  bool isReady = false;
  bool isDark = false;
  List<Vehicle> vehicles = [];
  List<ServiceRecord> services = [];
  List<VehicleExpense> expenses = [];
  List<MaintenanceReminder> reminders = [];

  Future<void> initialize() async {
    final data = await _repository.load();
    vehicles = data.vehicles;
    services = data.services;
    expenses = data.expenses;
    reminders = data.reminders;
    isReady = true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    isDark = !isDark;
    notifyListeners();
  }

  /// Replaces the complete in-memory snapshot only after the repository has
  /// committed the restore successfully.
  Future<void> restoreData(MaintainlyData data) async {
    await _repository.restore(data);
    vehicles = List.unmodifiable(data.vehicles);
    services = List.unmodifiable(data.services);
    expenses = List.unmodifiable(data.expenses);
    reminders = List.unmodifiable(data.reminders);
    notifyListeners();
  }

  Future<void> _persist() async {
    await _repository.save(
      MaintainlyData(
        vehicles: vehicles,
        services: services,
        expenses: expenses,
        reminders: reminders,
      ),
    );
    notifyListeners();
  }

  Vehicle? vehicleById(String id) {
    for (final vehicle in vehicles) {
      if (vehicle.id == id) return vehicle;
    }
    return null;
  }

  String vehicleName(String id) => vehicleById(id)?.name ?? 'Deleted vehicle';

  String? serviceTitleById(String? id) {
    if (id == null) return null;
    for (final service in services) {
      if (service.id == id) return service.title;
    }
    return null;
  }

  Future<void> saveVehicle(Vehicle vehicle) async {
    MaintainlyDataValidator.validateVehicle(vehicle);
    final index = vehicles.indexWhere((item) => item.id == vehicle.id);
    if (index < 0) {
      vehicles = [...vehicles, vehicle];
    } else {
      final copy = [...vehicles];
      copy[index] = vehicle;
      vehicles = copy;
    }
    await _persist();
  }

  List<Vehicle> get activeVehicles =>
      vehicles.where((v) => !v.isArchived).toList();
  List<Vehicle> get archivedVehicles =>
      vehicles.where((v) => v.isArchived).toList();

  /// Archives a vehicle without deleting its service, expense, or reminder history.
  Future<void> archiveVehicle(String id) async {
    vehicles = vehicles
        .map((v) => v.id == id ? v.copyWith(isArchived: true) : v)
        .toList();
    await _persist();
  }

  /// Backwards-compatible alias; vehicle removal now means reversible archive.
  Future<void> deleteVehicle(String id) => archiveVehicle(id);

  Future<void> restoreVehicle(String id) async {
    vehicles = vehicles
        .map((v) => v.id == id ? v.copyWith(isArchived: false) : v)
        .toList();
    await _persist();
  }

  Future<void> addService(ServiceRecord record) async => saveService(record);

  Future<void> saveService(ServiceRecord record) async {
    MaintainlyDataValidator.validateService(record);
    final linkedVehicle = vehicleById(record.vehicleId);
    if (linkedVehicle == null ||
        (linkedVehicle.isArchived &&
            !services.any((item) => item.id == record.id))) {
      throw ArgumentError('New service records require an active vehicle.');
    }
    final index = services.indexWhere((item) => item.id == record.id);
    final previousService = index < 0 ? null : services[index];
    final linkedExpenseTotal = expenses
        .where((expense) => expense.sourceServiceId == record.id)
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    if ((previousService == null ||
            previousService.vehicleId == record.vehicleId) &&
        linkedExpenseTotal > record.cost) {
      throw ArgumentError(
        'Service cost cannot be lower than the total of expenses included in it.',
      );
    }
    final isNew = index < 0;
    if (isNew) {
      services = [record, ...services];
    } else {
      final copy = [...services];
      copy[index] = record;
      services = copy;
    }
    final vehicle = vehicleById(record.vehicleId);
    if (vehicle != null && record.odometer > vehicle.odometer) {
      final vehicleIndex = vehicles.indexWhere((v) => v.id == vehicle.id);
      final copy = [...vehicles];
      copy[vehicleIndex] = vehicle.copyWith(odometer: record.odometer);
      vehicles = copy;
    }
    if (previousService != null &&
        previousService.vehicleId != record.vehicleId) {
      expenses = expenses
          .map(
            (expense) => expense.sourceServiceId == record.id
                ? VehicleExpense(
                    id: expense.id,
                    vehicleId: expense.vehicleId,
                    category: expense.category,
                    description: expense.description,
                    date: expense.date,
                    amount: expense.amount,
                    odometer: expense.odometer,
                  )
                : expense,
          )
          .toList();
    }
    final linkedReminderIndex = reminders.indexWhere(
      (reminder) => reminder.sourceServiceId == record.id,
    );
    final hasNextDue =
        record.nextDueDate != null || record.nextDueOdometer != null;
    if (!hasNextDue) {
      if (linkedReminderIndex >= 0) {
        reminders = reminders
            .where((reminder) => reminder.sourceServiceId != record.id)
            .toList();
      }
    } else if (linkedReminderIndex >= 0) {
      final linkedReminder = reminders[linkedReminderIndex];
      final updatedReminder = MaintenanceReminder(
        id: linkedReminder.id,
        vehicleId: record.vehicleId,
        title: record.title,
        dueDate: record.nextDueDate,
        dueOdometer: record.nextDueOdometer,
        notes: linkedReminder.notes,
        completed: false,
        sourceServiceId: record.id,
      );
      final reminderCopy = [...reminders];
      reminderCopy[linkedReminderIndex] = updatedReminder;
      reminders = reminderCopy;
    } else {
      reminders = [
        MaintenanceReminder(
          id: MaintainlyRepository.newId(),
          vehicleId: record.vehicleId,
          title: record.title,
          dueDate: record.nextDueDate,
          dueOdometer: record.nextDueOdometer,
          notes: 'Created from service history.',
          completed: false,
          sourceServiceId: record.id,
        ),
        ...reminders,
      ];
    }
    await _persist();
  }

  Future<void> deleteService(String id) async {
    services = services.where((s) => s.id != id).toList();
    reminders = reminders
        .where((reminder) => reminder.sourceServiceId != id)
        .toList();
    expenses = expenses
        .map(
          (expense) => expense.sourceServiceId == id
              ? VehicleExpense(
                  id: expense.id,
                  vehicleId: expense.vehicleId,
                  category: expense.category,
                  description: expense.description,
                  date: expense.date,
                  amount: expense.amount,
                  odometer: expense.odometer,
                )
              : expense,
        )
        .toList();
    await _persist();
  }

  Future<void> addExpense(VehicleExpense expense) async => saveExpense(expense);

  Future<void> saveExpense(VehicleExpense expense) async {
    MaintainlyDataValidator.validateExpense(expense);
    final linkedVehicle = vehicleById(expense.vehicleId);
    final existingExpense = expenses.any((item) => item.id == expense.id);
    if (linkedVehicle == null ||
        (linkedVehicle.isArchived && !existingExpense)) {
      throw ArgumentError('New expenses require an active vehicle.');
    }
    final sourceServiceId = expense.sourceServiceId;
    if (sourceServiceId != null) {
      final matchingServices = services.where(
        (service) => service.id == sourceServiceId,
      );
      final sourceService = matchingServices.isEmpty
          ? null
          : matchingServices.first;
      if (sourceService == null ||
          sourceService.vehicleId != expense.vehicleId) {
        throw ArgumentError(
          'Linked service must belong to the same vehicle as the expense.',
        );
      }
      final existingLinkedTotal = expenses
          .where(
            (item) =>
                item.id != expense.id &&
                item.sourceServiceId == sourceServiceId,
          )
          .fold<double>(0, (sum, item) => sum + item.amount);
      if (existingLinkedTotal + expense.amount > sourceService.cost) {
        throw ArgumentError(
          'Linked expense total cannot exceed the service cost.',
        );
      }
    }
    final index = expenses.indexWhere((item) => item.id == expense.id);
    if (index < 0) {
      expenses = [expense, ...expenses];
    } else {
      final copy = [...expenses];
      copy[index] = expense;
      expenses = copy;
    }
    final vehicle = vehicleById(expense.vehicleId);
    if (vehicle != null && expense.odometer > vehicle.odometer) {
      final vehicleIndex = vehicles.indexWhere((v) => v.id == vehicle.id);
      final copy = [...vehicles];
      copy[vehicleIndex] = vehicle.copyWith(odometer: expense.odometer);
      vehicles = copy;
    }
    await _persist();
  }

  Future<void> deleteExpense(String id) async {
    expenses = expenses.where((e) => e.id != id).toList();
    await _persist();
  }

  Future<void> addReminder(MaintenanceReminder reminder) async {
    MaintainlyDataValidator.validateReminder(reminder);
    if (vehicleById(reminder.vehicleId)?.isArchived != false) {
      throw ArgumentError('Reminders require an active vehicle.');
    }
    reminders = [reminder, ...reminders];
    await _persist();
  }

  Future<void> toggleReminder(String id) async {
    reminders = reminders
        .map((r) => r.id == id ? r.copyWith(completed: !r.completed) : r)
        .toList();
    await _persist();
  }

  Future<void> deleteReminder(String id) async {
    reminders = reminders.where((r) => r.id != id).toList();
    await _persist();
  }

  bool isOverdue(MaintenanceReminder reminder) {
    if (reminder.completed) return false;
    final now = DateTime.now();
    final date = reminder.dueDate;
    final vehicle = vehicleById(reminder.vehicleId);
    final dateOverdue =
        date != null &&
        DateTime(
          date.year,
          date.month,
          date.day,
        ).isBefore(DateTime(now.year, now.month, now.day));
    final mileageOverdue =
        reminder.dueOdometer != null &&
        vehicle != null &&
        vehicle.odometer >= reminder.dueOdometer!;
    return dateOverdue || mileageOverdue;
  }

  bool isDueSoon(MaintenanceReminder reminder) {
    if (reminder.completed || isOverdue(reminder)) return false;
    final now = DateTime.now();
    final date = reminder.dueDate;
    final dateSoon =
        date != null &&
        date.difference(DateTime(now.year, now.month, now.day)).inDays <= 30;
    final vehicle = vehicleById(reminder.vehicleId);
    final mileageSoon =
        reminder.dueOdometer != null &&
        vehicle != null &&
        reminder.dueOdometer! - vehicle.odometer <= 1000;
    return dateSoon || mileageSoon;
  }

  /// Expenses linked to a service are itemized components of that service cost
  /// and are shown in history, but are not added to totals a second time.
  double get totalExpenses => expenses
      .where((item) => item.sourceServiceId == null)
      .fold(0, (sum, item) => sum + item.amount);
  double get serviceSpend => services.fold(0, (sum, item) => sum + item.cost);
  double get totalSpend => totalExpenses + serviceSpend;
  double expenseTotal(Iterable<VehicleExpense> items) => items
      .where((item) => item.sourceServiceId == null)
      .fold(0, (sum, item) => sum + item.amount);
  int get overdueCount => reminders
      .where(
        (r) => vehicleById(r.vehicleId)?.isArchived != true && isOverdue(r),
      )
      .length;
  int get upcomingCount => reminders
      .where(
        (r) => vehicleById(r.vehicleId)?.isArchived != true && isDueSoon(r),
      )
      .length;
}
