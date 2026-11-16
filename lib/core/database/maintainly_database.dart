import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'maintainly_schema.dart';

/// Opens Maintainly's local SQLite database on native and web platforms.
///
/// This is the database foundation only. The existing SharedPreferences
/// repository remains the active application store until the migration and
/// repository-integration steps are completed.
class MaintainlyDatabase extends GeneratedDatabase {
  MaintainlyDatabase({
    DatabaseConnection? connection,
    String databaseName = _databaseName,
  }) : super(
         connection ??
             driftDatabase(
               name: databaseName,
               web: DriftWebOptions(
                 sqlite3Wasm: Uri.parse(_sqlite3WasmPath),
                 driftWorker: Uri.parse(_driftWorkerPath),
               ),
             ),
       );

  static const String _databaseName = 'maintainly';
  static const String _sqlite3WasmPath = 'sqlite3.wasm';
  static const String _driftWorkerPath = 'drift_worker.js';

  static const int latestSchemaVersion = MaintainlySchema.version;

  bool _isClosed = false;

  @override
  int get schemaVersion => MaintainlyDatabase.latestSchemaVersion;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      // A brand-new database is created directly at the latest schema.
      await MaintainlySchema.create(this);
    },
    onUpgrade: (migrator, from, to) async {
      if (to < from) {
        throw StateError(
          'Maintainly database downgrade from v$from to v$to is not supported.',
        );
      }
      // Step 1 created schema version 1 without application tables.
      // Step 2 introduced the relational data tables and indexes.
      if (from < 2 && to >= 2) {
        await MaintainlySchema.createV2(this);
      }
      // Step 4 introduces a ledger so the JSON import can be idempotent and
      // its completion marker can commit atomically with the imported rows.
      if (from < 3 && to >= 3) {
        await MaintainlySchema.createV3(this);
      }
      if (from < 4 && to >= 4) {
        await MaintainlySchema.createV4(this);
      }
      if (from < 5 && to >= 5) {
        await MaintainlySchema.createV5(this);
      }
    },
    beforeOpen: (_) async {
      // Keep SQLite foreign-key checks enabled on every opened connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Ensures the database is opened and its initial migration has completed.
  Future<void> open() {
    if (_isClosed) {
      return Future<void>.error(
        StateError('MaintainlyDatabase has already been closed.'),
      );
    }
    return doWhenOpened((_) async {});
  }

  /// Returns the SQLite engine version after opening the database.
  Future<String> get sqliteVersion async {
    await open();
    final row = await customSelect('SELECT sqlite_version() AS sqlite_version')
        .getSingle();
    return row.read<String>('sqlite_version');
  }

  /// Returns the schema version currently stored by SQLite.
  Future<int> get currentSchemaVersion async {
    await open();
    final row = await customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  /// Confirms whether SQLite foreign-key enforcement is enabled.
  Future<bool> get foreignKeysEnabled async {
    await open();
    final row = await customSelect('PRAGMA foreign_keys').getSingle();
    return row.read<int>('foreign_keys') == 1;
  }

  /// Closes the database. Repeated close calls are safe.
  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await super.close();
  }
}
