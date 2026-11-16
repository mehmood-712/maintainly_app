# Local database foundation and schema

Maintainly uses Drift 2.35.4 with `drift_flutter` 0.3.1 as its cross-platform
SQLite foundation for Android and Flutter Web.

## Current schema version 5

The manually versioned schema creates:

- `vehicles` — vehicle profile, non-negative odometer/purchase price, and an
  `is_archived` 0/1 flag. Existing vehicles upgrade as active.
- `service_records` — service history with a required vehicle foreign key.
- `vehicle_expenses` — expense records with a required vehicle foreign key and
  an optional `source_service_id` link. Deleting a service sets this link to
  NULL, preserving the expense as a standalone record.
- `maintenance_reminders` — date/mileage reminders with a required vehicle
  foreign key, a 0/1 completion flag, and an optional source service link for
  reminders generated from service history.
- `maintainly_migrations` — migration ledger used to record a completed,
  idempotent import in the same transaction as imported records.

Child records retain `ON DELETE CASCADE` as the database-level hard-delete
safeguard. The normal application vehicle action is reversible archive, not a
hard delete. Dates are stored as Unix epoch microseconds in SQLite INTEGER
columns. Nullable model dates remain SQL NULL. Money values remain SQLite REAL
values. Boolean flags are stored as INTEGER 0 or 1.

## Schema upgrades

- New databases are created directly at schema version 5.
- A schema v1 database upgrades through v2 relational tables/indexes, v3
  migration ledger, v4 service/reminder relationship, and v5 archive/expense
  relationship.
- Schema v2 and v3 databases continue through the missing migrations in order.
- A schema v4 database adds the vehicle archive flag and nullable expense to
  service link in v5.
- Foreign-key enforcement is enabled before normal database operations.
- Future schema changes must increment `MaintainlySchema.version` and add an
  explicit upgrade path in `MaintainlyDatabase.migration`.

## Model mapping and compatibility

`lib/data/mappers/maintainly_database_mapper.dart` maps domain models to and
from SQL row maps. Older JSON without `isArchived` or `sourceServiceId` remains
compatible: vehicles default to active and expenses default to standalone.
Required database fields are mapped strictly rather than silently defaulted.

## Financial integrity rule

An expense linked to a service is treated as an itemized component already
included in that service's recorded cost. It remains visible in the expense
history but is excluded from standalone expense totals. The service cost is
counted once. The controller and repository validator require a linked service
to belong to the same vehicle and ensure linked itemized expense totals do not
exceed the service cost. No automatic matching by category, amount, or date is
performed.

## Platform storage

- Native platforms store the database in the app documents directory through
  `drift_flutter`.
- Web uses Drift's WebAssembly SQLite engine and worker. Install the pinned Web
  assets with `tool/setup_drift_web_assets.ps1` on Windows or
  `tool/setup_drift_web_assets.sh` on Bash-compatible environments.

## Repository integration

`MaintainlyRepository` reads migrated records from SQLite after verifying the
migration ledger and stored row counts. Snapshot writes run in a transaction,
replace all four collections, preserve foreign-key ordering, and update the
migration ledger counts in the same transaction. The legacy SharedPreferences
JSON remains a guarded fallback/recovery source for migration or database
unavailability. The source JSON is not removed by the current flow.
