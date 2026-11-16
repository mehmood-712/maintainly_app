import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../../core/data/legacy_storage_keys.dart';
import '../../core/data/local_store.dart';
import '../../core/database/maintainly_database.dart';
import '../mappers/maintainly_database_mapper.dart';
import '../migration/legacy_data_inspector.dart';
import '../migration/legacy_json_to_sqlite_migrator.dart';
import '../models/expense.dart';
import '../models/maintenance_reminder.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';
import '../validation/maintainly_data_validator.dart';

class MaintainlyData {
  const MaintainlyData({
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

class MaintainlyRepository {
  MaintainlyRepository(
    this._store, {
    MaintainlyDatabase? database,
    bool autoMigrateLegacyDataOnLoad = false,
  }) : _database = database,
       _autoMigrateLegacyDataOnLoad = autoMigrateLegacyDataOnLoad;

  /// When true, the current in-memory snapshot was loaded from SQLite. If the
  /// Step 5 legacy write path is used afterward, subsequent launches fall back
  /// to that newer SharedPreferences snapshot until the SQLite write path is
  /// introduced in Step 6. This prevents stale SQLite reads from hiding edits.
  static const String sqliteReadFallbackKey =
      'maintainly.sqlite.read_fallback_after_legacy_write';
  static const String sqliteMigrationCompletedKey =
      'maintainly.sqlite.legacy_migration_completed';

  final LocalStore _store;
  final MaintainlyDatabase? _database;
  final bool _autoMigrateLegacyDataOnLoad;
  static final _uuid = Uuid();
  bool _loadedFromSqlite = false;
  bool _migrationKnownComplete = false;
  bool _sqliteUnavailable = false;

  Future<MaintainlyData> load() async {
    _migrationKnownComplete =
        _migrationKnownComplete || _store.readBool(sqliteMigrationCompletedKey);
    MaintainlyData? sqliteData;
    try {
      sqliteData = await _loadFromSqliteIfMigrated();
    } catch (error) {
      // Until Step 6 adds SQLite writes, the unchanged legacy snapshot remains
      // a safe recovery source if the migrated database fails its integrity
      // checks. Keep the app usable and make the fallback visible in logs.
      _sqliteUnavailable = true;
      debugPrint(
        'Maintainly SQLite read failed verification; using preserved legacy data: $error',
      );
    }
    if (sqliteData != null) return sqliteData;

    // Load the untouched legacy snapshot first. If automatic migration is
    // enabled, the migrator creates and verifies its backup before importing.
    // A blocked migration leaves this legacy snapshot as the active fallback.
    final legacyData = await _loadLegacyData();
    final database = _database;
    if (database == null ||
        !_autoMigrateLegacyDataOnLoad ||
        _sqliteUnavailable ||
        _store.readBool(sqliteReadFallbackKey)) {
      return legacyData;
    }

    LegacyMigrationResult migration;
    try {
      migration = await LegacyJsonToSqliteMigrator(
        store: _store,
        database: database,
      ).migrate();
    } catch (error) {
      // The migrator is transactional and retains the source JSON. A failure
      // therefore leaves the previous repository usable. Do not retry SQLite
      // again during this repository instance's lifetime.
      _sqliteUnavailable = true;
      debugPrint(
        'Maintainly legacy migration did not complete; using preserved legacy data: $error',
      );
      return legacyData;
    }
    if (!migration.didMigrate) {
      debugPrint(
        'Maintainly legacy migration is blocked; using preserved legacy data: ${migration.blockedReason}',
      );
      return legacyData;
    }

    // The ledger is committed in the same transaction as all four collections.
    // Re-read through the same verified path rather than returning the JSON
    // objects used during import.
    try {
      return await _loadFromSqliteIfMigrated() ?? legacyData;
    } catch (error) {
      _sqliteUnavailable = true;
      debugPrint(
        'Maintainly migrated data could not be read; using preserved legacy data: $error',
      );
      return legacyData;
    }
  }

  /// Reads the migrated SQLite snapshot only when the migration ledger proves
  /// that the complete legacy import committed successfully. Returns null
  /// when no database was supplied, migration has not completed, or the
  /// legacy repository has since accepted newer writes. A ledger/count
  /// mismatch throws internally; [load] logs it and falls back to the
  /// preserved SharedPreferences snapshot because Step 5 has no SQLite writes.
  Future<MaintainlyData?> _loadFromSqliteIfMigrated() async {
    final database = _database;
    if (database == null ||
        _sqliteUnavailable ||
        _store.readBool(sqliteReadFallbackKey)) {
      return null;
    }

    List<QueryRow> ledgerRows;
    try {
      await database.open();
      ledgerRows = await database
          .customSelect(
            '''
        SELECT vehicle_count, service_count, expense_count, reminder_count,
               total_record_count
        FROM maintainly_migrations
        WHERE migration_key = ?
        ''',
            variables: [
              Variable.withString(LegacyJsonToSqliteMigrator.migrationKey),
            ],
          )
          .get();
    } catch (error) {
      // SQLite initialization can be unavailable on a platform whose Web
      // assets or native database setup is incomplete. Step 5 has no SQLite
      // write path yet, and the original JSON remains intact, so keep the app
      // usable through its legacy repository while reporting the reason.
      _sqliteUnavailable = true;
      debugPrint(
        'Maintainly SQLite read unavailable; using preserved legacy data: $error',
      );
      return null;
    }
    if (ledgerRows.isEmpty) return null;
    if (ledgerRows.length != 1) {
      throw StateError(
        'SQLite contains duplicate Maintainly migration ledger rows.',
      );
    }

    _migrationKnownComplete = true;
    await _store.writeBool(sqliteMigrationCompletedKey, true);

    final ledger = ledgerRows.single.data;
    final expectedCounts = <String, int>{
      'vehicles': _ledgerCount(ledger, 'vehicle_count'),
      'service_records': _ledgerCount(ledger, 'service_count'),
      'vehicle_expenses': _ledgerCount(ledger, 'expense_count'),
      'maintenance_reminders': _ledgerCount(ledger, 'reminder_count'),
    };
    final expectedTotal = _ledgerCount(ledger, 'total_record_count');
    final expectedSum = expectedCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    if (expectedTotal != expectedSum) {
      throw StateError(
        'SQLite migration ledger is inconsistent: total_record_count does not match its collection counts.',
      );
    }

    // rowid preserves the insertion order from the original JSON arrays.
    final vehicleRows = await _readSqliteRows(database, 'vehicles');
    final serviceRows = await _readSqliteRows(database, 'service_records');
    final expenseRows = await _readSqliteRows(database, 'vehicle_expenses');
    final reminderRows = await _readSqliteRows(
      database,
      'maintenance_reminders',
    );
    final actualCounts = <String, int>{
      'vehicles': vehicleRows.length,
      'service_records': serviceRows.length,
      'vehicle_expenses': expenseRows.length,
      'maintenance_reminders': reminderRows.length,
    };
    for (final entry in expectedCounts.entries) {
      if (actualCounts[entry.key] != entry.value) {
        throw StateError(
          'SQLite migration verification failed for ${entry.key}: expected ${entry.value} rows, found ${actualCounts[entry.key]}. The legacy snapshot remains available for recovery.',
        );
      }
    }

    final data = MaintainlyData(
      vehicles: vehicleRows
          .map(MaintainlyDatabaseMapper.vehicleFromRow)
          .toList(),
      services: serviceRows
          .map(MaintainlyDatabaseMapper.serviceRecordFromRow)
          .toList(),
      expenses: expenseRows
          .map(MaintainlyDatabaseMapper.expenseFromRow)
          .toList(),
      reminders: reminderRows
          .map(MaintainlyDatabaseMapper.reminderFromRow)
          .toList(),
    );
    _loadedFromSqlite = true;
    return data;
  }

  Future<List<Map<String, Object?>>> _readSqliteRows(
    MaintainlyDatabase database,
    String table,
  ) async {
    // Table names are fixed internal constants at call sites, never user input.
    final rows = await database
        .customSelect('SELECT * FROM $table ORDER BY rowid ASC')
        .get();
    return rows.map((row) => Map<String, Object?>.from(row.data)).toList();
  }

  int _ledgerCount(Map<String, Object?> ledger, String field) {
    final value = ledger[field];
    if (value is int && value >= 0) return value;
    throw StateError(
      'SQLite migration ledger contains an invalid $field value.',
    );
  }

  Future<MaintainlyData> _loadLegacyData() async {
    final seedMarker = _store.readRaw(LegacyStorageKeys.seeded);
    final hasAnyLegacyCollectionKey = LegacyStorageKeys.collections.any(
      _store.containsKey,
    );

    // Seed sample data only on a genuinely empty first launch. Older builds
    // only checked the marker, so a missing marker could overwrite record keys
    // that already existed. Preserve those keys for the migration/recovery flow.
    if (seedMarker == null && !hasAnyLegacyCollectionKey) {
      final sample = _sampleData();
      await save(sample);
      return sample;
    }

    return MaintainlyData(
      vehicles: _decode(LegacyStorageKeys.vehicles, Vehicle.fromJson),
      services: _decode(LegacyStorageKeys.services, ServiceRecord.fromJson),
      expenses: _decode(LegacyStorageKeys.expenses, VehicleExpense.fromJson),
      reminders: _decode(
        LegacyStorageKeys.reminders,
        MaintenanceReminder.fromJson,
      ),
    );
  }

  List<T> _decode<T>(String key, T Function(Map<String, dynamic>) factory) {
    final storedValue = _store.readRaw(key);
    if (storedValue is! String || storedValue.isEmpty) return <T>[];
    final raw = storedValue;
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      return values
          .map((item) => factory(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return <T>[];
    }
  }

  /// Restores a user-selected full backup into the authoritative SQLite
  /// snapshot. Restore is intentionally disabled until a verified migration
  /// ledger exists; the legacy SharedPreferences path has no multi-key
  /// transaction and must not be used for destructive restore operations.
  Future<void> restore(MaintainlyData data) async {
    MaintainlyDataValidator.validateSnapshot(
      vehicles: data.vehicles,
      services: data.services,
      expenses: data.expenses,
      reminders: data.reminders,
    );

    final database = _database;
    if (database == null || !_migrationKnownComplete || _sqliteUnavailable) {
      throw StateError(
        'Restore is unavailable because the SQLite database is not ready. '
        'Your current data has not been changed.',
      );
    }

    final wasUsingLegacyFallback = _store.readBool(sqliteReadFallbackKey);
    // Switch reads to SQLite before the transaction. If the transaction fails,
    // restore the previous marker so the prior source remains authoritative.
    await _store.writeBool(sqliteReadFallbackKey, false);
    try {
      await _saveToSqlite(database, data);
      _loadedFromSqlite = true;
    } catch (_) {
      if (wasUsingLegacyFallback) {
        await _store.writeBool(sqliteReadFallbackKey, true);
      }
      rethrow;
    }
  }

  Future<void> save(MaintainlyData data) async {
    MaintainlyDataValidator.validateSnapshot(
      vehicles: data.vehicles,
      services: data.services,
      expenses: data.expenses,
      reminders: data.reminders,
    );
    final inspection = LegacyDataInspector(_store).inspect();
    if (inspection.hasUnsafeLegacyCollections) {
      throw StateError(
        'Legacy records are malformed, incomplete, or relationally inconsistent. '
        'They were not overwritten. Create and review a legacy backup before '
        'repairing these records.',
      );
    }

    final database = _database;
    if (database != null && _migrationKnownComplete && !_sqliteUnavailable) {
      await _saveToSqlite(database, data);
      // SQLite becomes authoritative only after the complete transaction commits.
      await _store.writeBool(sqliteReadFallbackKey, false);
      _loadedFromSqlite = true;
      return;
    }

    // Before migration (or for legacy-only repository construction), retain
    // the existing SharedPreferences write path.
    await _store.write(
      LegacyStorageKeys.vehicles,
      jsonEncode(data.vehicles.map((e) => e.toJson()).toList()),
    );
    await _store.write(
      LegacyStorageKeys.services,
      jsonEncode(data.services.map((e) => e.toJson()).toList()),
    );
    await _store.write(
      LegacyStorageKeys.expenses,
      jsonEncode(data.expenses.map((e) => e.toJson()).toList()),
    );
    await _store.write(
      LegacyStorageKeys.reminders,
      jsonEncode(data.reminders.map((e) => e.toJson()).toList()),
    );

    if (_loadedFromSqlite || _migrationKnownComplete) {
      await _store.writeBool(sqliteReadFallbackKey, true);
      _loadedFromSqlite = false;
    }
    await _store.write(LegacyStorageKeys.seeded, 'yes');
  }

  /// Atomically replaces all four collections and updates the migration
  /// ledger counts, preserving the existing whole-snapshot repository API.
  Future<void> _saveToSqlite(
    MaintainlyDatabase database,
    MaintainlyData data,
  ) async {
    await database.transaction(() async {
      final ledgerRows = await database
          .customSelect(
            'SELECT backup_key FROM maintainly_migrations WHERE migration_key = ?',
            variables: [
              Variable.withString(LegacyJsonToSqliteMigrator.migrationKey),
            ],
          )
          .get();
      if (ledgerRows.length != 1) {
        throw StateError(
          'SQLite write stopped: completed migration ledger is missing or duplicated.',
        );
      }

      // Delete dependent rows first, then parents. Insert in the reverse order.
      await database.customStatement('DELETE FROM service_records');
      await database.customStatement('DELETE FROM vehicle_expenses');
      await database.customStatement('DELETE FROM maintenance_reminders');
      await database.customStatement('DELETE FROM vehicles');

      for (final vehicle in data.vehicles) {
        final row = MaintainlyDatabaseMapper.vehicleToRow(vehicle);
        await database.customInsert(
          'INSERT INTO vehicles (id, name, type, make, model, year, registration, odometer, purchase_date, purchase_price, is_archived) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: _variablesForSqliteRow(row, const [
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
            'is_archived',
          ]),
        );
      }
      for (final service in data.services) {
        final row = MaintainlyDatabaseMapper.serviceRecordToRow(service);
        await database.customInsert(
          'INSERT INTO service_records (id, vehicle_id, title, category, date, odometer, cost, mechanic, notes, next_due_date, next_due_odometer) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: _variablesForSqliteRow(row, const [
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
      for (final expense in data.expenses) {
        final row = MaintainlyDatabaseMapper.expenseToRow(expense);
        await database.customInsert(
          'INSERT INTO vehicle_expenses (id, vehicle_id, category, description, date, amount, odometer, source_service_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          variables: _variablesForSqliteRow(row, const [
            'id',
            'vehicle_id',
            'category',
            'description',
            'date',
            'amount',
            'odometer',
            'source_service_id',
          ]),
        );
      }
      for (final reminder in data.reminders) {
        final row = MaintainlyDatabaseMapper.reminderToRow(reminder);
        await database.customInsert(
          'INSERT INTO maintenance_reminders (id, vehicle_id, title, due_date, due_odometer, notes, completed, source_service_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          variables: _variablesForSqliteRow(row, const [
            'id',
            'vehicle_id',
            'title',
            'due_date',
            'due_odometer',
            'notes',
            'completed',
            'source_service_id',
          ]),
        );
      }

      final counts = <String, int>{
        'vehicles': data.vehicles.length,
        'service_records': data.services.length,
        'vehicle_expenses': data.expenses.length,
        'maintenance_reminders': data.reminders.length,
      };
      for (final entry in counts.entries) {
        final result = await database
            .customSelect('SELECT COUNT(*) AS row_count FROM ${entry.key}')
            .getSingle();
        if (result.read<int>('row_count') != entry.value) {
          throw StateError(
            'SQLite write verification failed for ${entry.key}; transaction rolled back.',
          );
        }
      }

      await database.customStatement(
        'UPDATE maintainly_migrations SET completed_at_utc = ?, vehicle_count = ?, service_count = ?, expense_count = ?, reminder_count = ?, total_record_count = ? WHERE migration_key = ?',
        [
          DateTime.now().toUtc().toIso8601String(),
          data.vehicles.length,
          data.services.length,
          data.expenses.length,
          data.reminders.length,
          data.vehicles.length +
              data.services.length +
              data.expenses.length +
              data.reminders.length,
          LegacyJsonToSqliteMigrator.migrationKey,
        ],
      );
    });
  }

  List<Variable<Object>> _variablesForSqliteRow(
    Map<String, Object?> row,
    List<String> columns,
  ) => columns
      .map((column) {
        final value = row[column];
        if (value == null) return Variable<int>(null);
        if (value is String) return Variable.withString(value);
        if (value is int) return Variable.withInt(value);
        if (value is double) return Variable.withReal(value);
        if (value is bool) return Variable.withBool(value);
        throw UnsupportedError(
          'Unsupported SQLite value for "$column": ${value.runtimeType}.',
        );
      })
      .toList(growable: false);

  static String newId() => _uuid.v4();

  MaintainlyData _sampleData() {
    final now = DateTime.now();
    final v1 = Vehicle(
      id: 'veh-1',
      name: 'Daily Drive',
      type: 'Car',
      make: 'Toyota',
      model: 'Corolla GLi',
      year: 2021,
      registration: 'LEA-21-4587',
      odometer: 68420,
      purchaseDate: DateTime(2022, 3, 12),
      purchasePrice: 4250000,
    );
    final v2 = Vehicle(
      id: 'veh-2',
      name: 'City Runner',
      type: 'Motorcycle',
      make: 'Honda',
      model: 'CB 150F',
      year: 2023,
      registration: 'LEK-23-9012',
      odometer: 18350,
      purchaseDate: DateTime(2023, 7, 8),
      purchasePrice: 485000,
    );
    final v3 = Vehicle(
      id: 'veh-3',
      name: 'Delivery Van',
      type: 'Commercial',
      make: 'Suzuki',
      model: 'Every',
      year: 2020,
      registration: 'LEB-20-7721',
      odometer: 112800,
      purchaseDate: DateTime(2021, 1, 19),
      purchasePrice: 1980000,
    );
    final services = <ServiceRecord>[
      ServiceRecord(
        id: 'srv-1',
        vehicleId: v1.id,
        title: 'Engine oil & filter',
        category: 'Oil change',
        date: now.subtract(const Duration(days: 54)),
        odometer: 65000,
        cost: 14500,
        mechanic: 'AutoCare Workshop',
        notes: 'Synthetic oil and OEM filter.',
        nextDueDate: now.add(const Duration(days: 36)),
        nextDueOdometer: 70000,
      ),
      ServiceRecord(
        id: 'srv-2',
        vehicleId: v2.id,
        title: 'Chain adjustment',
        category: 'Repair',
        date: now.subtract(const Duration(days: 22)),
        odometer: 17800,
        cost: 2200,
        mechanic: 'City Motors',
        notes: 'Chain cleaned and adjusted.',
      ),
      ServiceRecord(
        id: 'srv-3',
        vehicleId: v3.id,
        title: 'Brake pads replaced',
        category: 'Parts replacement',
        date: now.subtract(const Duration(days: 88)),
        odometer: 108000,
        cost: 18500,
        mechanic: 'Fleet Workshop',
        notes: 'Front brake pads replaced.',
      ),
    ];
    final expenses = <VehicleExpense>[
      VehicleExpense(
        id: 'exp-1',
        vehicleId: v1.id,
        category: 'Fuel',
        description: 'Petrol refill',
        date: now.subtract(const Duration(days: 3)),
        amount: 9500,
        odometer: 68210,
      ),
      VehicleExpense(
        id: 'exp-2',
        vehicleId: v1.id,
        category: 'Parts',
        description: 'Wiper blades',
        date: now.subtract(const Duration(days: 18)),
        amount: 3200,
        odometer: 67800,
      ),
      VehicleExpense(
        id: 'exp-3',
        vehicleId: v2.id,
        category: 'Fuel',
        description: 'Petrol refill',
        date: now.subtract(const Duration(days: 2)),
        amount: 1800,
        odometer: 18310,
      ),
      VehicleExpense(
        id: 'exp-4',
        vehicleId: v3.id,
        category: 'Labour',
        description: 'Routine inspection',
        date: now.subtract(const Duration(days: 12)),
        amount: 2500,
        odometer: 112200,
      ),
    ];
    final reminders = <MaintenanceReminder>[
      MaintenanceReminder(
        id: 'rem-1',
        vehicleId: v1.id,
        title: 'Oil and filter change',
        dueDate: now.add(const Duration(days: 36)),
        dueOdometer: 70000,
        notes: 'Use recommended engine oil grade.',
        completed: false,
      ),
      MaintenanceReminder(
        id: 'rem-2',
        vehicleId: v2.id,
        title: 'Brake inspection',
        dueDate: now.subtract(const Duration(days: 2)),
        dueOdometer: 18500,
        notes: 'Check front and rear brakes.',
        completed: false,
      ),
      MaintenanceReminder(
        id: 'rem-3',
        vehicleId: v3.id,
        title: 'Tyre rotation',
        dueDate: now.add(const Duration(days: 7)),
        dueOdometer: 115000,
        notes: 'Inspect tyre condition and pressure.',
        completed: false,
      ),
    ];
    return MaintainlyData(
      vehicles: [v1, v2, v3],
      services: services,
      expenses: expenses,
      reminders: reminders,
    );
  }
}
