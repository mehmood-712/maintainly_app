# Legacy data inspection and SQLite migration

Maintainly's pre-SQLite records are stored in five SharedPreferences keys:

- `maintainly.vehicles`
- `maintainly.services`
- `maintainly.expenses`
- `maintainly.reminders`
- `maintainly.seeded`

The four collection values are JSON arrays. The seed marker is expected to be
the string `yes` after the existing repository has seeded or saved a complete
dataset.

## Inspection and recovery

`LegacyDataInspector` reads the raw values without changing them. It detects
missing, empty, valid, partially valid, malformed, and unexpected-type data;
checks duplicate IDs and orphaned vehicle references; and reports invalid
dates/numbers or fields that the legacy JSON parsers would silently default.

`createBackupSnapshot()` captures key presence, original value type, and raw
value for all five source keys. Its JSON representation is versioned and keeps
malformed source JSON as an unchanged string. Step 3 exposed this as an
in-memory snapshot; Step 4's migrator persists and verifies it before import.

## Transactional migration (schema v3)

`LegacyJsonToSqliteMigrator` performs a one-time transactional import. Step 5
connects it to the application repository's startup read path: the repository
first opens SQLite and checks the migration ledger; if no completed migration
exists, the app loads the preserved legacy snapshot, then runs the migrator
automatically when the source passes inspection. A blocked or failed migration
keeps SharedPreferences as the active fallback.

Migration sequence:

1. Open SQLite and check the `maintainly_migrations` ledger for the migration
   key `legacy_shared_preferences_to_sqlite_v1`.
2. Inspect the current legacy values and create a versioned raw-value snapshot.
3. Persist and read-back verify the snapshot in SharedPreferences under
   `maintainly.legacy.backup.v1` before attempting any SQLite import. If an
   earlier backup exists but source values have since changed, preserve the old
   backup and write a separately named attempt snapshot.
4. Block import when the inspection report contains errors, warnings, missing
   defaulted fields, duplicate IDs, orphan references, or a seed-marker risk.
   The backup is still kept so the original values can be reviewed/recovered.
5. A completely fresh installation with no legacy keys and no seed marker is
   blocked rather than recorded as an empty successful migration; the normal
   first-launch seed flow must establish the intended initial dataset first.
6. Within one Drift transaction, ensure all target tables are empty, insert
   vehicles before child records, verify row counts, and insert the migration
   ledger row.
7. If any insert or verification fails, the whole SQLite transaction rolls
   back. The SharedPreferences source keys and backup snapshots remain intact.
8. Repeated calls return `alreadyMigrated` when the ledger row exists; they do
   not insert duplicate records.

The `maintainly_migrations` table is introduced in schema version 3. Its
completion row commits in the same transaction as the imported vehicle,
service, expense, and reminder records.

## Repository read path (Step 5)

- The application provider supplies a `MaintainlyDatabase` to the existing
  `MaintainlyRepository` boundary.
- When a successful migration ledger row exists, the repository reads all four
  collections from SQLite and verifies table row counts against the ledger
  before mapping rows to the existing domain models.
- If there is no completed ledger, the repository loads the legacy snapshot.
  The app then attempts the backup-first migrator automatically when enabled.
- If migration is blocked, SQLite cannot initialize, or a migrated snapshot
  fails its read checks, the repository keeps using the preserved JSON source
  and reports the fallback reason through debug logging.
- The original JSON source keys and `maintainly.seeded` marker are not deleted.
- The current write path still saves to SharedPreferences. After a snapshot
  loaded from SQLite is saved through that legacy path, a fallback marker makes
  the newer JSON snapshot authoritative on the next launch. Step 6 will replace
  this temporary bridge with SQLite writes.
- The backup snapshot remains in SharedPreferences; external file export and a
  restore UI are not implemented yet.
