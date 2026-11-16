import 'package:drift/drift.dart';

/// The manually versioned SQL schema for Maintainly.
///
/// Keep the existing v2 relational tables stable. New schema changes must add
/// a new versioned statement and an explicit upgrade path in
/// [MaintainlyDatabase.migration].
abstract final class MaintainlySchema {
  static const int version = 5;

  static const List<String> tableNames = [
    'vehicles',
    'service_records',
    'vehicle_expenses',
    'maintenance_reminders',
    'maintainly_migrations',
  ];

  /// Tables and indexes introduced in schema v2.
  static const List<String> createV2Statements = [
    '''
    CREATE TABLE IF NOT EXISTS vehicles (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      make TEXT NOT NULL DEFAULT '',
      model TEXT NOT NULL DEFAULT '',
      year INTEGER NOT NULL,
      registration TEXT NOT NULL DEFAULT '',
      odometer INTEGER NOT NULL DEFAULT 0 CHECK (odometer >= 0),
      purchase_date INTEGER NULL,
      purchase_price REAL NOT NULL DEFAULT 0 CHECK (purchase_price >= 0)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS service_records (
      id TEXT NOT NULL PRIMARY KEY,
      vehicle_id TEXT NOT NULL,
      title TEXT NOT NULL,
      category TEXT NOT NULL,
      date INTEGER NOT NULL,
      odometer INTEGER NOT NULL CHECK (odometer >= 0),
      cost REAL NOT NULL DEFAULT 0 CHECK (cost >= 0),
      mechanic TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      next_due_date INTEGER NULL,
      next_due_odometer INTEGER NULL
        CHECK (next_due_odometer IS NULL OR next_due_odometer >= 0),
      FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS vehicle_expenses (
      id TEXT NOT NULL PRIMARY KEY,
      vehicle_id TEXT NOT NULL,
      category TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      date INTEGER NOT NULL,
      amount REAL NOT NULL CHECK (amount >= 0),
      odometer INTEGER NOT NULL CHECK (odometer >= 0),
      FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS maintenance_reminders (
      id TEXT NOT NULL PRIMARY KEY,
      vehicle_id TEXT NOT NULL,
      title TEXT NOT NULL,
      due_date INTEGER NULL,
      due_odometer INTEGER NULL
        CHECK (due_odometer IS NULL OR due_odometer >= 0),
      notes TEXT NOT NULL DEFAULT '',
      completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
      FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_service_records_vehicle_date
    ON service_records (vehicle_id, date DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_vehicle_expenses_vehicle_date
    ON vehicle_expenses (vehicle_id, date DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_vehicle_expenses_category_date
    ON vehicle_expenses (category, date)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_maintenance_reminders_vehicle
    ON maintenance_reminders (vehicle_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_maintenance_reminders_open_due_date
    ON maintenance_reminders (due_date)
    WHERE completed = 0 AND due_date IS NOT NULL
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_maintenance_reminders_open_due_odometer
    ON maintenance_reminders (due_odometer)
    WHERE completed = 0 AND due_odometer IS NOT NULL
    ''',
  ];

  /// Migration ledger introduced in schema v3. Its row is committed in the
  /// same transaction as the imported legacy records.
  static const String createV3MigrationLedger = '''
    CREATE TABLE IF NOT EXISTS maintainly_migrations (
      migration_key TEXT NOT NULL PRIMARY KEY,
      completed_at_utc TEXT NOT NULL,
      backup_key TEXT NOT NULL,
      vehicle_count INTEGER NOT NULL CHECK (vehicle_count >= 0),
      service_count INTEGER NOT NULL CHECK (service_count >= 0),
      expense_count INTEGER NOT NULL CHECK (expense_count >= 0),
      reminder_count INTEGER NOT NULL CHECK (reminder_count >= 0),
      total_record_count INTEGER NOT NULL CHECK (total_record_count >= 0)
    )
  ''';

  static Future<void> createV2(GeneratedDatabase database) async {
    for (final statement in createV2Statements) {
      await database.customStatement(statement);
    }
  }

  static Future<void> createV3(GeneratedDatabase database) async {
    await database.customStatement(createV3MigrationLedger);
  }

  /// Adds an optional service-history link to generated reminders. Existing
  /// reminders remain unlinked and therefore retain their manual behaviour.
  static Future<void> createV4(GeneratedDatabase database) async {
    await database.customStatement(
      'ALTER TABLE maintenance_reminders ADD COLUMN source_service_id TEXT NULL REFERENCES service_records (id) ON DELETE CASCADE',
    );
    await database.customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maintenance_reminders_source_service ON maintenance_reminders (source_service_id) WHERE source_service_id IS NOT NULL',
    );
  }

  /// Adds vehicle archival and an explicit expense-to-service relationship.
  /// Existing rows remain active and unlinked by default.
  static Future<void> createV5(GeneratedDatabase database) async {
    await database.customStatement(
      'ALTER TABLE vehicles ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1))',
    );
    await database.customStatement(
      'ALTER TABLE vehicle_expenses ADD COLUMN source_service_id TEXT NULL REFERENCES service_records (id) ON DELETE SET NULL',
    );
    await database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_vehicle_expenses_source_service ON vehicle_expenses (source_service_id) WHERE source_service_id IS NOT NULL',
    );
  }

  /// Creates the current schema on a brand-new database.
  static Future<void> create(GeneratedDatabase database) async {
    await createV2(database);
    await createV3(database);
    await createV4(database);
    await createV5(database);
  }
}
