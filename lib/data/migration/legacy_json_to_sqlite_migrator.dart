import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/data/legacy_storage_keys.dart';
import '../../core/data/local_store.dart';
import '../../core/database/maintainly_database.dart';
import '../mappers/maintainly_database_mapper.dart';
import '../models/expense.dart';
import '../models/maintenance_reminder.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';
import 'legacy_data_inspector.dart';

enum LegacyMigrationStatus { migrated, alreadyMigrated, blocked }

/// Result of an explicit legacy SharedPreferences -> SQLite migration attempt.
///
/// A blocked result is an expected safety outcome (for example malformed JSON
/// or missing fields). Unexpected database/storage failures are thrown so the
/// caller cannot mistake a failed migration for a successful one.
class LegacyMigrationResult {
  const LegacyMigrationResult({
    required this.status,
    required this.report,
    required this.backupKey,
    required this.vehicleCount,
    required this.serviceCount,
    required this.expenseCount,
    required this.reminderCount,
    required this.completedAtUtc,
    this.blockedReason,
  });

  final LegacyMigrationStatus status;
  final LegacyDataInspectionReport report;
  final String backupKey;
  final int vehicleCount;
  final int serviceCount;
  final int expenseCount;
  final int reminderCount;
  final DateTime? completedAtUtc;
  final String? blockedReason;

  int get totalRecordCount =>
      vehicleCount + serviceCount + expenseCount + reminderCount;

  bool get didMigrate =>
      status == LegacyMigrationStatus.migrated ||
      status == LegacyMigrationStatus.alreadyMigrated;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'backupKey': backupKey,
    'vehicleCount': vehicleCount,
    'serviceCount': serviceCount,
    'expenseCount': expenseCount,
    'reminderCount': reminderCount,
    'totalRecordCount': totalRecordCount,
    'completedAtUtc': completedAtUtc?.toIso8601String(),
    'blockedReason': blockedReason,
    'inspection': report.toJson(),
  };
}

/// Imports all four legacy JSON collections into SQLite atomically.
///
/// Safety guarantees:
/// - A raw-value backup is persisted and read-back verified before import.
/// - The inspector must report migration-safe data before rows are imported.
/// - Existing SQLite data without a migration ledger entry is never replaced.
/// - All four collections and the completion ledger row commit in one
///   database transaction.
/// - A failed transaction rolls back all imported rows.
/// - Original SharedPreferences source keys are never deleted or rewritten.
/// - Repeated calls return [LegacyMigrationStatus.alreadyMigrated].
class LegacyJsonToSqliteMigrator {
  LegacyJsonToSqliteMigrator({
    required LocalStore store,
    required MaintainlyDatabase database,
  }) : _store = store,
       _database = database,
       _inspector = LegacyDataInspector(store);

  static const String migrationKey = 'legacy_shared_preferences_to_sqlite_v1';
  static const String _migrationLedger = 'maintainly_migrations';

  final LocalStore _store;
  final MaintainlyDatabase _database;
  final LegacyDataInspector _inspector;

  Future<LegacyMigrationResult> migrate({DateTime? completedAt}) async {
    await _database.open();

    final existing = await _readMigrationRecord();
    if (existing != null) {
      return _resultFromRecord(LegacyMigrationStatus.alreadyMigrated, existing);
    }

    // Capture and persist the untouched source values before validation or any
    // SQLite writes. Invalid legacy data is backed up too, for manual recovery.
    final report = _inspector.inspect();
    final snapshot = _inspector.createBackupSnapshot(createdAt: completedAt);
    final backupKey = await _persistOrVerifyBackup(snapshot);

    final hasAnyLegacyKey = LegacyStorageKeys.all.any(_store.containsKey);
    final blockedReason = !report.isReadyForMigration
        ? 'Legacy inspection found data that needs review before import.'
        : !hasAnyLegacyKey
        ? 'No legacy records or seed marker exist. This looks like a fresh '
              'installation; initialize the intended first-launch dataset before migration.'
        : null;
    if (blockedReason != null) {
      return LegacyMigrationResult(
        status: LegacyMigrationStatus.blocked,
        report: report,
        backupKey: backupKey,
        vehicleCount: 0,
        serviceCount: 0,
        expenseCount: 0,
        reminderCount: 0,
        completedAtUtc: null,
        blockedReason: blockedReason,
      );
    }

    final legacyData = _readLegacyModels();
    final timestamp = (completedAt ?? DateTime.now()).toUtc();
    LegacyMigrationResult? result;

    await _database.transaction(() async {
      // Re-check inside the transaction to make concurrent/repeated calls
      // safe. The transaction serializes this check with the actual import.
      final completedRecord = await _readMigrationRecord();
      if (completedRecord != null) {
        result = _resultFromRecord(
          LegacyMigrationStatus.alreadyMigrated,
          completedRecord,
        );
        return;
      }

      final existingCounts = await _readTargetCounts();
      if (existingCounts.values.any((count) => count != 0)) {
        throw StateError(
          'SQLite already contains Maintainly records but has no legacy '
          'migration ledger entry. Import was stopped to avoid overwriting '
          'or duplicating existing data.',
        );
      }

      // Parent rows must be inserted before child rows because the schema
      // enforces vehicle foreign keys.
      for (final vehicle in legacyData.vehicles) {
        final row = MaintainlyDatabaseMapper.vehicleToRow(vehicle);
        await _database.customInsert(
          '''
          INSERT INTO vehicles (
            id, name, type, make, model, year, registration, odometer,
            purchase_date, purchase_price
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          variables: _variablesForRow(row, const [
            'id',
            'name',
            'type',
            'make',
            'model',
            'year',
            'registration',
            'odometer',
            'purchase_date',
            'purchase_price',
          ]),
        );
      }

      for (final service in legacyData.services) {
        final row = MaintainlyDatabaseMapper.serviceRecordToRow(service);
        await _database.customInsert(
          '''
          INSERT INTO service_records (
            id, vehicle_id, title, category, date, odometer, cost, mechanic,
            notes, next_due_date, next_due_odometer
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          variables: _variablesForRow(row, const [
            'id',
            'vehicle_id',
            'title',
            'category',
            'date',
            'odometer',
            'cost',
            'mechanic',
            'notes',
            'next_due_date',
            'next_due_odometer',
          ]),
        );
      }

      for (final expense in legacyData.expenses) {
        final row = MaintainlyDatabaseMapper.expenseToRow(expense);
        await _database.customInsert(
          '''
          INSERT INTO vehicle_expenses (
            id, vehicle_id, category, description, date, amount, odometer
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          variables: _variablesForRow(row, const [
            'id',
            'vehicle_id',
            'category',
            'description',
            'date',
            'amount',
            'odometer',
          ]),
        );
      }

      for (final reminder in legacyData.reminders) {
        final row = MaintainlyDatabaseMapper.reminderToRow(reminder);
        await _database.customInsert(
          '''
          INSERT INTO maintenance_reminders (
            id, vehicle_id, title, due_date, due_odometer, notes, completed
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          variables: _variablesForRow(row, const [
            'id',
            'vehicle_id',
            'title',
            'due_date',
            'due_odometer',
            'notes',
            'completed',
          ]),
        );
      }

      final importedCounts = await _readTargetCounts();
      final expectedCounts = <String, int>{
        'vehicles': legacyData.vehicles.length,
        'service_records': legacyData.services.length,
        'vehicle_expenses': legacyData.expenses.length,
        'maintenance_reminders': legacyData.reminders.length,
      };
      if (!_countsMatch(importedCounts, expectedCounts)) {
        throw StateError(
          'SQLite row-count verification failed. The import transaction '
          'will be rolled back. Expected $expectedCounts, found $importedCounts.',
        );
      }

      final total = expectedCounts.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      await _database.customInsert(
        '''
        INSERT INTO $_migrationLedger (
          migration_key, completed_at_utc, backup_key, vehicle_count,
          service_count, expense_count, reminder_count, total_record_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable.withString(migrationKey),
          Variable.withString(timestamp.toIso8601String()),
          Variable.withString(backupKey),
          Variable.withInt(legacyData.vehicles.length),
          Variable.withInt(legacyData.services.length),
          Variable.withInt(legacyData.expenses.length),
          Variable.withInt(legacyData.reminders.length),
          Variable.withInt(total),
        ],
      );

      result = LegacyMigrationResult(
        status: LegacyMigrationStatus.migrated,
        report: report,
        backupKey: backupKey,
        vehicleCount: legacyData.vehicles.length,
        serviceCount: legacyData.services.length,
        expenseCount: legacyData.expenses.length,
        reminderCount: legacyData.reminders.length,
        completedAtUtc: timestamp,
      );
    });

    final completedResult = result;
    if (completedResult == null) {
      throw StateError('Migration transaction finished without a result.');
    }
    return completedResult;
  }

  Future<String> _persistOrVerifyBackup(LegacyBackupSnapshot snapshot) async {
    final encoded = snapshot.encode();
    final baseKey = LegacyStorageKeys.migrationBackup;
    final currentEntries = jsonEncode(snapshot.toJson()['entries']);

    // Keep the first recovery snapshot immutable. If source values have been
    // repaired since an earlier blocked attempt, retain that earlier backup
    // and write a separately named snapshot for the repaired source state.
    if (_store.containsKey(baseKey)) {
      final existingBase = _store.readRaw(baseKey);
      if (existingBase is! String) {
        throw StateError(
          'The existing legacy migration backup key has an unexpected type. '
          'It was not overwritten.',
        );
      }
      if (_backupEntriesMatch(existingBase, currentEntries)) return baseKey;

      final timestamp = snapshot.createdAtUtc.microsecondsSinceEpoch;
      var attemptKey = '$baseKey.$timestamp';
      var suffix = 1;
      while (_store.containsKey(attemptKey)) {
        final existingAttempt = _store.readRaw(attemptKey);
        if (existingAttempt is String &&
            _backupEntriesMatch(existingAttempt, currentEntries)) {
          return attemptKey;
        }
        attemptKey = '$baseKey.$timestamp.$suffix';
        suffix++;
      }
      await _store.writeVerified(attemptKey, encoded);
      return attemptKey;
    }

    await _store.writeVerified(baseKey, encoded);
    return baseKey;
  }

  bool _backupEntriesMatch(String encodedBackup, String currentEntries) {
    try {
      final decoded = jsonDecode(encodedBackup);
      if (decoded is! Map ||
          decoded['format'] != 'maintainly.legacy-shared-preferences-backup' ||
          decoded['formatVersion'] != 1 ||
          decoded['entries'] is! Map) {
        return false;
      }
      return jsonEncode(decoded['entries']) == currentEntries;
    } on FormatException {
      return false;
    }
  }

  _LegacyModelCollections _readLegacyModels() {
    return _LegacyModelCollections(
      vehicles: _decodeCollection(LegacyStorageKeys.vehicles, Vehicle.fromJson),
      services: _decodeCollection(
        LegacyStorageKeys.services,
        ServiceRecord.fromJson,
      ),
      expenses: _decodeCollection(
        LegacyStorageKeys.expenses,
        VehicleExpense.fromJson,
      ),
      reminders: _decodeCollection(
        LegacyStorageKeys.reminders,
        MaintenanceReminder.fromJson,
      ),
    );
  }

  List<T> _decodeCollection<T>(
    String key,
    T Function(Map<String, dynamic>) factory,
  ) {
    final raw = _store.readRaw(key);
    if (raw == null || (raw is String && raw.trim().isEmpty)) return <T>[];
    if (raw is! String) {
      throw FormatException('Legacy key "$key" is not stored as a string.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Legacy key "$key" is not a JSON array.');
    }
    return decoded
        .map((item) {
          if (item is! Map) {
            throw FormatException(
              'Legacy key "$key" contains a non-object row.',
            );
          }
          return factory(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
  }

  Future<Map<String, Object?>?> _readMigrationRecord() async {
    final rows = await _database
        .customSelect(
          '''
      SELECT migration_key, completed_at_utc, backup_key, vehicle_count,
             service_count, expense_count, reminder_count, total_record_count
      FROM $_migrationLedger
      WHERE migration_key = ?
      ''',
          variables: [Variable.withString(migrationKey)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  LegacyMigrationResult _resultFromRecord(
    LegacyMigrationStatus status,
    Map<String, Object?> record,
  ) {
    final report = _inspector.inspect();
    return LegacyMigrationResult(
      status: status,
      report: report,
      backupKey:
          record['backup_key'] as String? ?? LegacyStorageKeys.migrationBackup,
      vehicleCount: record['vehicle_count'] as int? ?? 0,
      serviceCount: record['service_count'] as int? ?? 0,
      expenseCount: record['expense_count'] as int? ?? 0,
      reminderCount: record['reminder_count'] as int? ?? 0,
      completedAtUtc: DateTime.tryParse(
        record['completed_at_utc'] as String? ?? '',
      ),
    );
  }

  Future<Map<String, int>> _readTargetCounts() async {
    const tables = [
      'vehicles',
      'service_records',
      'vehicle_expenses',
      'maintenance_reminders',
    ];
    final counts = <String, int>{};
    for (final table in tables) {
      final row = await _database
          .customSelect('SELECT COUNT(*) AS row_count FROM $table')
          .getSingle();
      counts[table] = row.read<int>('row_count');
    }
    return counts;
  }

  bool _countsMatch(Map<String, int> actual, Map<String, int> expected) {
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  static List<Variable<Object>> _variablesForRow(
    Map<String, Object?> row,
    List<String> columns,
  ) {
    return columns
        .map((column) {
          final value = row[column];
          if (value == null) return Variable<int>(null);
          if (value is String) return Variable.withString(value);
          if (value is int) return Variable.withInt(value);
          if (value is double) return Variable.withReal(value);
          if (value is bool) return Variable.withBool(value);
          throw UnsupportedError(
            'Unsupported SQLite migration value for "$column": ${value.runtimeType}.',
          );
        })
        .toList(growable: false);
  }
}

class _LegacyModelCollections {
  const _LegacyModelCollections({
    required this.vehicles,
    required this.services,
    required this.expenses,
    required this.reminders,
  });

  final List<Vehicle> vehicles;
  final List<ServiceRecord> services;
  final List<VehicleExpense> expenses;
  final List<MaintenanceReminder> reminders;
}
