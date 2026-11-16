# Maintainly — Incremental SQLite Integration Log

## Project progress

- **Project:** Maintainly (Flutter vehicle maintenance application)
- **Current step:** Step 8 — Reliability, backup, and recovery (Substeps 8.1–8.2 completed and user-verified; Substep 8.3 implementation prepared, verification pending)
- **Step 0 status:** Completed; full source/code review and baseline findings recorded
- **Step 1 status:** Completed and approved by the user on 12 November 2026 at 11:35 PM PKT
- **Step 2 status:** Schema v2 and model mapping delivered. User reported 8/8 database tests and 5/5 mapper tests passing on the preceding revision; a Drift duplicate-database warning was reported. Fix 2 was delivered to clean up that test fixture; no post-Fix-2 native test output has been supplied yet.
- **Step 2 Web status:** The Chrome automated Web test remained at loading for about 15 minutes and was not confirmed. The user later ran `flutter build web` successfully on Flutter 3.47.5. This confirms Web compilation of the current app but does not prove SQLite Web runtime compatibility because SQLite is not yet connected to the app's repository.
- **Step 3 status:** User authorized progression to Step 4 by sending `next step go` on 13 November 2026. The final Step 3 inspector test output was not supplied in the conversation, so no user-side test pass is claimed.
- **Step 4 status:** Completed and user-approved on 13 November 2026. User reported all Step 4 test suites passed. Latest `flutter analyze` reported 0 errors, 0 warnings, and 43 info-level suggestions.
- **SQLite implementation progress:** Versioned relational schema, model mappers, legacy inspection/recovery, transactional JSON import, verified SQLite reads, and the Step 6 transactional SQLite snapshot write path are implemented. Step 6 routes repository saves to SQLite after migration is confirmed; legacy-only and SQLite-unavailable fallback behaviour is retained.
- **Step 6 status:** User approved Step 6 after reporting all six regression suites passed (53/53 individual tests).
- **Step 7 status:** Implementation of Substeps 1–3 accepted as complete for progression. The user reported that all non-browser tests passed after the latest manual test fixes. The Chrome database test remained stuck at loading and is explicitly deferred for re-check during Step 9. Full manual regression remains deferred until Step 10.

> This file is the permanent development log. Keep all completed step history. Update it inside every delivered project ZIP.

---

## Step 0 — Complete Code Review

### Objective

Inspect the uploaded project before making code changes. Understand the existing architecture, data flow, storage, UI, dependencies, platform setup, and risks that affect a safe SQLite migration.

### Review coverage

Inspected all 19 Dart source files (1,666 Dart lines), the root README, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.gitignore`, the web entry point and manifest, plus the data-source and remote-layer placeholder documentation.

The Dart source files reviewed were:

- `lib/main.dart`
- `lib/app.dart`
- `lib/application/providers.dart`
- `lib/application/maintainly_controller.dart`
- `lib/core/data/local_store.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/utils/formatters.dart`
- `lib/data/models/vehicle.dart`
- `lib/data/models/service_record.dart`
- `lib/data/models/expense.dart`
- `lib/data/models/maintenance_reminder.dart`
- `lib/data/repositories/maintainly_repository.dart`
- `lib/presentation/dialogs/forms.dart`
- `lib/presentation/screens/dashboard_screen.dart`
- `lib/presentation/screens/vehicles_screen.dart`
- `lib/presentation/screens/maintenance_screen.dart`
- `lib/presentation/screens/expenses_screen.dart`
- `lib/presentation/screens/reports_screen.dart`
- `lib/presentation/widgets/common_widgets.dart`

### Current architecture

```text
main.dart
  └── ProviderScope
      └── MaintainlyApp
          └── maintainlyControllerProvider
              ├── LocalStore (SharedPreferences)
              ├── MaintainlyRepository
              └── MaintainlyController (ChangeNotifier)
                  └── UI screens
```

The application currently loads four complete record lists into memory:

1. `Vehicle`
2. `ServiceRecord`
3. `VehicleExpense`
4. `MaintenanceReminder`

`MaintainlyRepository` currently exposes `load()` and `save(MaintainlyData)`. Each controller mutation updates its in-memory lists and then calls `_persist()`, which saves all four lists as separate JSON strings in SharedPreferences.

### Current project inventory

- **State management:** `flutter_riverpod` with a `ChangeNotifierProvider`.
- **Controller:** `MaintainlyController`.
- **Repository:** `MaintainlyRepository`.
- **Local storage:** `LocalStore` wrapping `SharedPreferences`.
- **Screens:** Dashboard, Vehicles, Maintenance, Expenses, Reports.
- **Models:** Vehicle, ServiceRecord, VehicleExpense, MaintenanceReminder.
- **Other current capabilities:** PDF report generation through `pdf` and `printing`, date/number formatting through `intl`, and UUID record IDs.
- **Backend:** None configured. No Firebase, Supabase, API client, or remote repository is present.
- **Database dependency:** No SQLite or relational database package is currently declared.

### Confirmed findings and risks

#### Critical — data safety

1. **Corrupted JSON can be silently treated as empty data.** In `lib/data/repositories/maintainly_repository.dart`, `_decode()` catches every parsing error and returns an empty list. A later save writes the in-memory lists back to SharedPreferences, which can overwrite the unreadable original records. Migration must preserve raw legacy values and report parsing failures rather than silently dropping records.
2. **First-launch seeding depends only on `maintainly.seeded`.** If this marker is missing while one or more JSON record keys already contain data, `load()` creates sample data and saves it over those keys. Migration must inspect existing record keys before deciding whether this is a genuinely empty first launch.
3. **The four JSON collections are written separately.** `save()` writes vehicles, services, expenses, and reminders sequentially, without one atomic transaction. A failure partway through can leave a mixed snapshot.
4. **Initialization has no recovery/error state.** `MaintainlyController.initialize()` does not catch repository errors. The app can remain on its loading screen if initialization fails.
5. **There is no backup/restore feature.** The PDF is a printable report, not a restorable data backup.

#### High — business logic and relationships

1. **Service-generated reminders have no source-service relationship.** A new service can create a reminder, but the reminder only stores `vehicleId`; it does not store the originating service ID. Editing a service does not update its generated reminder, and deleting a service leaves that reminder behind.
2. **Service and expense totals can be double-counted.** Dashboard totals, vehicle-card spend, and PDF totals add service costs to all expenses. If a user enters a service's labour/parts cost in both places, the same real-world cost is counted twice. The data model currently has no link or shared-cost rule to prevent this.
3. **Odometer validation is incomplete.** Forms validate that readings can be parsed as integers, but do not reject negative values or warn about readings lower than the latest known odometer. Editing a vehicle can also replace its current odometer with a lower value.
4. **Money validation is incomplete.** Vehicle purchase price, service cost, and expense amount accept negative numeric values.
5. **Reminder rules are hard-coded.** `isDueSoon()` uses a fixed 30-day and 1,000-km window. The data model does not define reusable service intervals in months or kilometres. Reaching the exact due odometer is currently counted as overdue.
6. **Reminder management is limited.** Reminders can be created, toggled complete/open, and deleted. There is no reminder edit or snooze action. Completing a reminder does not automatically schedule its next interval.
7. **Vehicle deletion is permanent.** The controller removes the vehicle and all its service, expense, and reminder records. There is no archive/sold state to preserve history.

#### Medium — UI and product gaps

1. **Vehicle type filters are currently disabled in the UI.** The filter-chip code in `vehicles_screen.dart` is commented out, while `_filter` remains `All`. The horizontal filter container is effectively empty.
2. **Theme choice is not persisted.** `toggleTheme()` changes the in-memory flag but does not call `LocalStore.writeBool()`; the app starts in light mode after a restart.
3. **Delete confirmation is inconsistent.** Vehicle deletion has a confirmation dialog, but service, expense, and reminder deletion are direct menu actions.
4. **Some form input edge cases are not validated.** For example, the optional next-service odometer can fail parsing and silently become `null`; numeric validators mostly check parseability rather than valid ranges.
5. **Reports are record/PDF summaries rather than analytical insights.** There are no date-range summaries, charts, CSV exports, or fuel-efficiency calculations in the current implementation.
6. **Operating-system notifications are not implemented.** Reminders are evaluated and shown inside the app only.

### Platform and configuration findings

1. The uploaded project contains `web/`, but does not contain an `android/` directory. The README describes generating the Android wrapper with `flutter create --platforms=android .`; Android native build configuration cannot be verified from this ZIP.
2. There is no `test/` directory and no automated test files in the uploaded project.
3. There is no `assets/` directory in the uploaded project.
4. The README says Flutter 3.27 or later, while the checked-in `pubspec.lock` records SDK constraints of Dart `>=3.13.0` and Flutter `>=3.47.0`. The README/runtime requirements need to be reconciled before implementation.
5. The `pubspec.yaml` Dart environment constraint is `>=3.6.0 <4.0.0`, which is broader/older than the SDK minimum recorded in the lockfile.
6. The ZIP includes generated `.dart_tool/`, `build/`, and `.flutter-plugins-dependencies` content. These are machine-generated and should not be carried into each delivery ZIP. The generated plugin file also contains absolute paths from the original Windows machine.
7. No `ios/`, `linux/`, `macos/`, or `windows/` platform directories are present.

### Database migration implications

- Preserve the current four model identities and existing UUID/string IDs during migration.
- Use relational foreign keys for `service_records.vehicle_id`, `vehicle_expenses.vehicle_id`, and `maintenance_reminders.vehicle_id`.
- Decide and test deletion policy explicitly. Current vehicle deletion cascades its related records in controller logic; database constraints must preserve the intended behaviour.
- Add a nullable source-service reference to reminders only after deciding the expected edit/delete behaviour for service-generated reminders.
- Store dates in a consistent ISO-8601/text representation or another explicitly documented representation, and preserve the existing time values.
- Preserve current numeric values during import; do not silently round costs or odometer values.
- Use database transactions for schema setup, migration, and related multi-record updates.
- Keep the original SharedPreferences JSON untouched until migration is verified and a recovery path is available.
- Migration must be idempotent and must not re-import/duplicate records if the app restarts midway.
- Do not replace all data with sample data when the legacy storage is partially populated or its seed marker is missing.

### Database technology research note

No database package has been added or selected in Step 0. Because the README describes both Android and Web as targets, database selection must account for both platforms. Drift is a strong candidate to evaluate because its current package documentation lists Android and Web support; its Web deployment requires additional WebAssembly/worker setup. The `sqflite_common_ffi_web` route is described by the sqflite package documentation as experimental. Final selection belongs to Step 1 after confirming target platforms and the actual Flutter SDK available to the user.

References reviewed:

- Drift Web platform guide: https://drift.simonbinder.eu/platforms/web/
- Drift package: https://pub.dev/packages/drift
- sqflite package and platform matrix: https://pub.dev/packages/sqflite

### Tests and verification performed

- ZIP archive listing and integrity were inspected.
- Source/configuration files were read statically.
- **Flutter/Dart commands were not run:** Flutter and Dart executables are not available in this review environment.
- **No compilation or runtime test was performed.**
- **No automated tests exist in the uploaded project.**
- Therefore, this step confirms source inspection only; it does not claim that the app currently builds or passes tests.

### Files changed in Step 0

- Added: `Incremental approach.md`
- Modified: none
- Deleted: none
- Application source code and the original `README.md` are unchanged.

### Manual review requested from the user

1. Open the delivered ZIP and confirm the project root contains `Incremental approach.md`.
2. Read the findings and confirm the current Android + Web target expectation.
3. Confirm whether the next step should preserve both Android and Web, or whether a platform can be excluded from SQLite support.
4. Do not run a new implementation step until you explicitly send `next step go`.

### Step 0 completion criteria

- [x] Inspect the complete uploaded source tree.
- [x] Read all Dart source files and key configuration/documentation files.
- [x] Map current architecture and persistence flow.
- [x] Record data-loss, integrity, business-logic, UI, and platform risks.
- [x] Prepare a staged SQLite roadmap.
- [x] Add this permanent progress log to the project root.
- [x] Generate and verify a clean project ZIP.
- [x] User reviewed Step 0 and authorized progression with `next step go`.

---

## Step 1 — Database strategy and foundation

### Objective

Select a cross-platform SQLite approach for Maintainly and add an isolated database-opening foundation without changing the active SharedPreferences data flow.

### Database decision

Selected **Drift 2.35.4** with **drift_flutter 0.3.1**.

Reasons:

- Drift's current package/platform information lists Android and Web as supported targets.
- `drift_flutter` provides one database connection setup for native Flutter and Web.
- Native platforms store the database in the application documents directory.
- Drift Web uses a WebAssembly SQLite engine and a worker, with browser storage selected according to available browser APIs.
- Drift provides typed tables, transactions, and schema migration facilities for later steps.

Official references checked during Step 1:

- Drift package/platform support: https://pub.dev/packages/drift
- drift_flutter package and platform support: https://pub.dev/packages/drift_flutter
- Drift Web setup and storage behaviour: https://drift.simonbinder.eu/platforms/web/
- Drift 2.35.4 release assets: https://github.com/simolus3/drift/releases/tag/drift-2.35.4

### Changes implemented

1. Added `drift: ^2.35.4` and `drift_flutter: ^0.3.1` to `pubspec.yaml`.
2. Aligned the declared SDK floor with the existing lockfile's recorded SDK floor: Dart 3.13.0+ and Flutter 3.47.0+.
3. Added `lib/core/database/maintainly_database.dart` as an isolated database lifecycle foundation. It:
   - creates the platform-specific Drift connection;
   - supports injected connections for tests;
   - opens once and shares concurrent open requests;
   - exposes the SQLite engine version and schema version;
   - enables SQLite foreign-key enforcement;
   - closes the connection safely and idempotently.
4. Reserved empty database schema version 1. The class exposes this initial value as `initialSchemaVersion`, while Drift reads it through the required instance `schemaVersion` getter. No application tables have been created yet.
5. Added native in-memory database tests in `test/core/database/maintainly_database_test.dart`.
6. Added a browser-side database smoke test in `test/core/database/maintainly_database_web_test.dart`.
7. Added a Windows PowerShell setup script and a Bash setup script to fetch the official Drift 2.35.4 Web assets and verify their SHA-256 hashes.
8. Updated the README's stated Flutter/Dart minimum versions to match the project's declared SDK floor.

### Web asset details

The Drift Web integration requires these two files under `web/`:

- `web/sqlite3.wasm`
- `web/drift_worker.js`

They are intentionally not fetched from the application at runtime. The project includes scripts to download the files once during development from the pinned Drift 2.35.4 release and verify their hashes before use.

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\setup_drift_web_assets.ps1
```

macOS/Linux/Git Bash:

```bash
bash ./tool/setup_drift_web_assets.sh
```

The official Drift Web documentation also notes that modern browsers select persistent storage based on available APIs. Some browsers may use slower fallback storage, and unsupported/private browsing contexts may not provide durable persistence. Production deployment should serve `.wasm` files with `Content-Type: application/wasm`. COOP/COEP headers can improve the preferred OPFS implementation but must be tested with the rest of the app before enabling them.

### Files changed in Step 1

- Modified: `pubspec.yaml`
- Modified: `README.md` (requirements section only: Flutter/Dart minimum versions)
- Added: `lib/core/database/maintainly_database.dart`
- Added: `lib/core/database/README.md`
- Added: `tool/setup_drift_web_assets.ps1`
- Added: `tool/setup_drift_web_assets.sh`
- Added: `tool/README.md`
- Added: `test/core/database/maintainly_database_test.dart`
- Added: `test/core/database/maintainly_database_web_test.dart`
- Updated: `Incremental approach.md`
- Unchanged: `pubspec.lock` (the Flutter/Dart CLI is not installed in this work environment, so dependency resolution could not be run here)
- Unchanged: SharedPreferences repository, controller, providers, screens, forms, and existing data models

### Data safety and scope boundaries

- SharedPreferences remains the active application storage.
- No existing records were read, migrated, deleted, or rewritten by this step.
- The new SQLite database is not connected to the app's providers or screens yet.
- No vehicle/service/expense/reminder tables have been created yet.
- No data migration has started.
- Android platform files are still absent from the supplied project ZIP. The existing README's Android scaffold command remains necessary before native Android testing.

### Tests and verification performed

- Static review of the new Dart source and project configuration completed.
- Confirmed the selected package versions and documented platform support against current official package/documentation pages.
- Confirmed the release asset names and SHA-256 checksums from the official Drift 2.35.4 release page.
- The generated ZIP will be checked for archive integrity and required files.
- **Flutter/Dart commands were not executed:** Flutter and Dart executables are not installed in this work environment.
- **`flutter pub get`, `flutter analyze`, native tests, Web tests, and Android/Web builds have not been run here.**
- `pubspec.lock` must be regenerated on the user's machine by running `flutter pub get`.

### User testing instructions

Run these commands from the project root in the following order:

1. Confirm the installed SDK:

```powershell
flutter --version
```

Expected: Flutter 3.47.0+ with Dart 3.13.0+.

2. Resolve the new Drift dependencies and regenerate the lockfile:

```powershell
flutter pub get
```

3. Run static analysis and the native database tests:

```powershell
flutter analyze
flutter test test/core/database/maintainly_database_test.dart
```

Expected: analysis completes without new errors, and all five native database foundation tests pass.

4. Install the pinned Web assets:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\setup_drift_web_assets.ps1
```

Expected: both files are placed in `web/` and their SHA-256 checksums are verified.

5. Run the Web database smoke test and build:

```powershell
flutter test --platform chrome test/core/database/maintainly_database_web_test.dart
flutter build web
```

Expected: the Web database smoke test opens SQLite, reports its engine/schema versions, and confirms foreign-key enforcement. The Web build completes successfully.

6. Android is not scaffolded in the supplied ZIP. After backing up the extracted project, create the Android wrapper and test it:

```powershell
flutter create --platforms=android .
flutter devices
flutter run -d <android-device-id>
```

Expected: the existing app still launches. Step 1 does not yet wire SQLite into the application boot flow, so app-screen data will still come from SharedPreferences.

### Completion and approval state

- [x] Select the cross-platform database package.
- [x] Add database dependencies and declare the SDK floor.
- [x] Add the isolated database opening/closing foundation.
- [x] Add native and Web database smoke tests.
- [x] Add checksummed Web asset setup scripts.
- [x] Keep SharedPreferences active and avoid application data migration.
- [x] Update this permanent progress log with the previous and upcoming steps.
- [x] Generate and verify the Step 1 project ZIP.
- [ ] User runs the dependency resolution, analysis, and tests.
- [x] User authorized progression to Step 2 by sending `next step go` on 13 November 2026.

---

## Step 2 — Database schema design and model mapping

### Objective

Create the first relational SQLite schema for the four existing domain models and add explicit conversion between those models and SQLite row values. Keep the current SharedPreferences repository and all application screens/controllers active and unchanged.

### Schema version and migration decision

- Increased the database schema version from 1 to 2.
- A new database creates the v2 schema directly.
- A Step 1 database at user_version 1 is upgraded to v2 by creating the new tables and indexes.
- The v2 schema is defined in `lib/core/database/maintainly_schema.dart` and is executed by Drift's `onCreate` and `onUpgrade` migration hooks.
- Foreign-key enforcement remains enabled in `beforeOpen`.

### Tables and model mapping

1. `vehicles` maps all current `Vehicle` fields: string ID, name, type, make, model, year, registration, odometer, nullable purchase date, and purchase price.
2. `service_records` maps all current `ServiceRecord` fields and references `vehicles.id` through `vehicle_id`.
3. `vehicle_expenses` maps all current `VehicleExpense` fields and references `vehicles.id` through `vehicle_id`.
4. `maintenance_reminders` maps all current `MaintenanceReminder` fields and references `vehicles.id` through `vehicle_id`.

All IDs remain TEXT primary keys to preserve existing UUID/string identifiers. Child-to-vehicle foreign keys use `ON DELETE CASCADE`, matching the current controller's vehicle deletion behaviour. Indexes support vehicle/date history, expense category/date filtering, vehicle reminder lookup, and open reminder due-date/odometer lookup.

### Storage representation and constraints

- DateTime values use INTEGER Unix epoch microseconds. Nullable model dates are stored as SQL NULL. Microseconds avoid truncating the precision supported by Dart DateTime.
- Monetary values remain SQLite REAL to map the existing Dart `double` fields without introducing a new currency/minor-unit conversion rule in this step.
- Odometer, purchase price, service cost, and expense amount have non-negative CHECK constraints.
- Reminder completion is stored as INTEGER 0/1 with a CHECK constraint.
- Required model fields are NOT NULL; fields nullable in the existing models remain nullable in SQLite.
- No `source_service_id` relationship was introduced for reminders because the current domain model has no such field. Service/reminder lifecycle logic remains scheduled for Step 7.

### Model mapper

Added `lib/data/mappers/maintainly_database_mapper.dart` with strict row-to-model and model-to-row conversions for all four existing domain models. The mapper does not change model classes or their JSON formats. Missing/invalid required row values throw `FormatException` rather than silently defaulting data.

### Tooling decision and deviation from the initial roadmap

The original Step 2 plan proposed adding `drift_dev` and `build_runner` and committing generated Drift table code. The implementation environment has no Flutter/Dart SDK, so generated files could not be produced or verified. To avoid adding unverified generated output or changing dependency locks, this step uses explicit SQL DDL through Drift's migration hooks plus a separately tested model mapper. `drift_dev` and `build_runner` were not added. This is a deliberate implementation choice, not a claim that generated code was produced. If typed generated Drift tables are required later, introduce code generation in a separate controlled step using the user's installed Flutter/Dart SDK.

### Tests and verification performed

- Added schema tests for fresh database creation, schema version 2, expected tables/indexes, v1-to-v2 upgrade, foreign-key enforcement, orphan rejection, cascade deletion, and numeric constraints.
- Added model-mapper round-trip tests for all four models, nullable dates, the reminder boolean, and invalid boolean rejection.
- Updated the Web smoke test to expect the latest schema version.
- Ran a Python SQLite sanity check against the actual DDL extracted from `maintainly_schema.dart`: all 4 tables and indexes created, foreign-key rejection worked, and deleting a vehicle cascaded to all 3 child tables.
- ZIP/archive integrity and required file presence will be checked before delivery.
- **Flutter/Dart commands were not run:** Flutter and Dart executables are unavailable in this implementation environment. `flutter pub get`, `flutter analyze`, `flutter test`, Web tests/build, and Android tests remain for user-side verification.
- The Python SQLite sanity check is not a substitute for running Drift/Flutter tests.

### Files changed in Step 2

- Modified: `lib/core/database/maintainly_database.dart` (schema version 2 and migration hooks)
- Added: `lib/core/database/maintainly_schema.dart` (tables, constraints, indexes, DDL)
- Added: `lib/data/mappers/maintainly_database_mapper.dart` (model/row conversions)
- Modified: `lib/core/database/README.md` (schema and storage representation)
- Modified: `test/core/database/maintainly_database_test.dart` (schema/migration/relationship tests)
- Modified: `test/core/database/maintainly_database_web_test.dart` (schema version expectation)
- Added: `test/data/maintainly_database_mapper_test.dart` (mapping tests)
- Modified: `Incremental approach.md` (this progress log)
- Unchanged: `pubspec.yaml`, `pubspec.lock`, domain models, repository, controller, providers, screens, forms, and root `README.md`

### Data safety and scope boundaries

- SharedPreferences remains the active application storage.
- No legacy JSON records were read, migrated, rewritten, or deleted.
- SQLite is not connected to the app's providers/screens for application data yet.
- Existing models and `toJson`/`fromJson` methods remain unchanged.
- Service-to-reminder linkage and related business rules are deferred to Step 7.

### User testing instructions

Run from the extracted project root:

```powershell
flutter pub get
flutter analyze
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
```

Expected: dependency resolution succeeds, analyzer reports no new errors, all schema/migration tests pass, and all model mapping round-trip tests pass.

For Web, install the already-pinned assets if they are not present, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\setup_drift_web_assets.ps1
flutter test --platform chrome test/core/database/maintainly_database_web_test.dart
flutter build web
```

Expected: Web database startup reports schema version 2 and foreign keys enabled, and the Web build succeeds. The application itself must continue using SharedPreferences in this step; SQLite tables should exist independently without changing current screen behaviour.

### Step 2 completion criteria

- [x] Define the four relational tables and indexes.
- [x] Add the v1-to-v2 schema upgrade path and fresh-create path.
- [x] Add explicit mapping for all four existing domain models.
- [x] Preserve current domain models and JSON serialization.
- [x] Add schema, relationship, constraint, and mapper tests.
- [x] Keep SharedPreferences active and avoid legacy data migration.
- [x] Update this progress log with previous history and upcoming steps.
- [x] Run a direct SQLite sanity check against the authored DDL.
- [x] Generate and verify a complete Step 2 ZIP.
- [ ] User runs Flutter dependency resolution, analysis, native tests, and Web verification.
- [ ] User accepts Step 2 and authorizes Step 3 with `next step go`.

---

## Remaining implementation roadmap (Step 6 is current)

Step 6 is the currently authorized implementation step. Steps 7–10 remain plans only and must be completed one at a time. Each step requires a separate complete ZIP delivery and the user's explicit `next step go` instruction after local testing.

### Step 3 — Legacy data inspection and recovery preparation (implemented; user progressed)

- Build a non-destructive reader for all four existing SharedPreferences JSON keys and the seed marker.
- Detect missing, empty, partially populated, malformed, and valid legacy data.
- Preserve raw legacy values and prepare a recoverable backup snapshot representation.
- Add test fixtures for valid and corrupted legacy records.
- Keep normal reads/writes on SharedPreferences.
- User sent `next step go` to authorize Step 4; the final Step 3 test output was not provided, so no pass is claimed.

### Step 4 — Transactional, idempotent JSON-to-SQLite migration (completed)

- Persist and verify a versioned raw-value backup before any SQLite import.
- Require the Step 3 inspector to report migration-safe source collections.
- Import vehicles before their service, expense, and reminder child records.
- Use a single Drift transaction for all four collections and the completion ledger row.
- Verify imported row counts before committing the ledger.
- Refuse to import over non-empty SQLite tables when no migration ledger exists.
- Preserve all original SharedPreferences source keys and keep recovery snapshots.
- Make repeated calls return `alreadyMigrated` without inserting duplicates.
- Test rollback, invalid source data, existing target data, backup preservation, and retry behaviour.

### Step 5 — SQLite read path (implemented and user-approved)

- Inject the local Drift database through the existing repository provider.
- On startup, check the migration ledger and read all four collections from SQLite only after a completed migration is verified.
- When no migration exists, load the legacy snapshot first and run the backup-first migrator automatically when enabled by the app provider.
- Keep SharedPreferences as a recovery fallback if migration is blocked or SQLite cannot initialize/read safely.
- Verify ledger totals against actual table row counts before mapping records to existing models.
- Preserve the current controller and UI API.
- Keep legacy writes temporarily and mark the JSON snapshot as authoritative after a save from an SQLite-loaded session, preventing stale SQLite data from hiding edits until Step 6.

### Step 6 — SQLite write path and CRUD integration (implemented; user testing pending)

- Route the existing repository whole-snapshot `save(MaintainlyData)` operation to SQLite after a successful migration ledger has been confirmed.
- Replace all four SQLite collections in one Drift transaction, deleting child collections before vehicles and inserting vehicles before child records to respect foreign keys.
- Verify each table's resulting row count before commit and update the migration ledger counts in the same transaction so the Step 5 read-path integrity check remains valid.
- Clear the Step 5 legacy-write fallback marker only after the SQLite transaction commits successfully.
- Retain SharedPreferences writes when the repository has not completed migration, when it is constructed without a database, or when SQLite has become unavailable; do not claim those fallback writes as SQLite writes.
- Keep existing controller and screen method contracts unchanged; their current save calls now reach the SQLite repository path after migration.
- Add regression coverage for SQLite save/reload, ledger count updates, transaction rollback on a foreign-key violation, and transition from the Step 5 compatibility fallback to SQLite.
- User must run the provided tests and manual CRUD/restart checks before Step 7 is authorized.

### Step 7 — Relationships and business-rule integrity (completed for progression; Chrome database test deferred to Step 9)

- [x] Define service-to-reminder linkage and behaviour on service edit/delete; implemented in Substep 1.
- [x] Add non-negative/finite numeric validation at form, controller, and repository boundaries; implemented in Substep 2. Existing SQLite and legacy-import constraints are reused.
- [x] Define how service costs and expense entries combine without double-counting.
- [x] Enforce vehicle foreign keys and decide the archive/sold versus permanent-delete policy.
- [ ] Define historical and out-of-order odometer handling without blocking legitimate past records.
- [x] Add regression coverage for the implemented relationship and business rules.

### Step 8 — Reliability, backup, and recovery (in progress)

- Add versioned schema migrations for future releases.
- Prepare JSON backup and restore with validation and confirmation.
- Preserve recovery options until backup/restore is verified.
- Handle database-open, read, write, and migration failures with clear user-facing states.

### Step 9 — Automated tests and platform verification (not started)

- Add model mapping, repository CRUD, transaction, foreign-key, and migration tests.
- Test database upgrades and repeated migration attempts.
- Verify Android and Web separately, including Web database assets/worker and browser persistence.
- Run formatter, analyzer, and tests using the user's installed Flutter SDK.

### Step 10 — Final regression and documentation (not started)

- Recheck dashboard, vehicles, maintenance, expenses, and PDF reports.
- Check for data loss, duplicate rows, broken relationships, and calculation regressions.
- Update the main README only to describe features that are actually implemented.
- Record remaining limitations and deliver the final verified project ZIP.

---

## Delivery protocol (applies to every step)

1. Implement only the single authorized step.
2. Update this file without deleting previous step history.
3. Package the complete updated project, including this file, into a fresh ZIP.
4. Verify the ZIP opens and contains the expected project files.
5. Provide the ZIP and exact manual test instructions.
6. Stop and wait for the user's feedback.
7. Start the next step only after the user sends `next step go`.

If the user reports a failed test, fix the current step and redeliver it before advancing.

### User acceptance record

- **Status:** User confirmed: "Step 1 done".
- **Date and time supplied by user:** 12 November 2026, 11:35 PM (Pakistan Standard Time, UTC+05:00).
- **Interpretation:** Step 1 is accepted/closed. This confirmation does not imply that tests not reported by the user were executed or passed.
- **Next action:** Step 2 — Database schema design and model mapping. This was authorized on 13 November 2026 and delivered; user testing/approval is pending.

### Step 2 delivery and acceptance record

> Historical status at initial delivery; the later Step 2 progression decision below supersedes the then-pending approval wording.

- **Status:** Step 2 implementation delivered; user testing and approval pending.
- **Authorized by user:** `next step go` on 13 November 2026.
- **Implementation scope:** Schema v2 and model mapping only. SharedPreferences remains the active store.
- **Verification boundary:** SQL DDL sanity-checked with Python SQLite; Flutter/Dart compilation and tests have not been run in this environment.
- **Next action:** User tests Step 2 and sends `next step go` only after accepting it. The next planned implementation step is Step 3 — Legacy data inspection and recovery preparation.

### Step 2 — User test feedback and corrective revision (13 November 2026)

> Historical test state before the user later authorized Step 3. The progression decision is recorded below.

The user tested the delivered Step 2 ZIP on **Flutter 3.47.5**. The user's `flutter pub get` completed sufficiently for the pinned Drift Web assets to be downloaded and SHA-256 verified. Flutter 3.47.5 bundles Dart 3.13.4; this satisfies the project's declared constraints (`flutter: >=3.47.0` and `sdk: >=3.13.0`). Package SDK metadata for Drift 2.35.4 and drift_flutter 0.3.1 also lists minimum Dart 3.10, so the selected versions are within the installed SDK's declared compatibility range.

User-reported test results:

- `flutter analyze`: reported 43 issues. The complete diagnostics were not included in the user's message, so the individual findings are not yet classified or fixed. Request the full analyzer output before changing unrelated application code.
- `flutter test test/core/database/maintainly_database_test.dart`: the schema-upgrade test failed with `Bad state: Tried to run an operation without first calling QueryExecutor.ensureOpen()!` at the direct `legacyExecutor.runCustom()` call.
- `flutter test test/data/maintainly_database_mapper_test.dart`: all mapper tests passed.
- `flutter test --platform chrome test/core/database/maintainly_database_web_test.dart`: remained at `loading ...` for approximately 15 minutes according to the user. This is not a confirmed successful test. The process should be interrupted with Ctrl+C, then rerun with `--verbose` to capture whether it is blocked during compilation, browser startup, test loading, or database/worker initialization.
- The Windows Web asset setup script downloaded both assets and verified their checksums successfully.

Corrective source change in this revision:

- Modified `test/core/database/maintainly_database_test.dart` so the v1 test database seeds `PRAGMA user_version = 1` using the `NativeDatabase.memory(setup: ...)` callback. This initializes the SQLite fixture before Drift runs `ensureOpen()`, instead of executing `runCustom()` on an unopened executor.

Verification boundary:

- The correction is based on Drift's documented `NativeDatabase.memory` setup callback API. Flutter/Dart are not installed in this implementation environment, so the corrected test has **not** been executed here.
- The analyzer's 43 diagnostics remain unclassified until the user provides the full output.
- The Chrome web-test startup hang remains under investigation until verbose logs are available.
- Step 2 is still **awaiting user retest and approval**. Step 3 must not start yet.

Recommended retest commands from the project root:

```powershell
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
```

For analyzer diagnostics, capture the complete output:

```powershell
flutter analyze 2>&1 | Tee-Object -FilePath analyze-output.txt
```

For the Web test, stop the currently hanging run with Ctrl+C, then capture verbose output:

```powershell
flutter test --platform chrome --verbose test/core/database/maintainly_database_web_test.dart 2>&1 | Tee-Object -FilePath web-test-output.txt
```

Do not start Step 3 until the current Step 2 issues have been reviewed and the user explicitly approves progression with `next step go`.

### Step 2 — Latest user test results and test-fixture cleanup (13 November 2026)

> Historical test state before the user later authorized Step 3. The progression decision is recorded below.

The user ran the commands from the Step 2 Fix 1 project on Windows using Flutter 3.47.5 / Dart 3.13.4 and shared the following results:

- `flutter pub get`: completed. Pub reported that 11 packages have newer releases that do not satisfy the current dependency constraints. This is an informational version notice; dependencies should not be upgraded automatically as part of Step 2.
- `flutter analyze`: reported 43 `info` diagnostics and no `warning` or `error` diagnostics in the supplied output. These consist mainly of existing style suggestions (`prefer_const_constructors`, `prefer_final_fields`, curly braces) and deprecations in existing UI/form code (`DropdownButtonFormField.value`, `Color.withOpacity`). The test code also reported deprecated `DatabaseConnection.fromExecutor` use. Unrelated UI lint cleanup is outside Step 2 and should not be mixed into database schema work.
- `flutter test test/core/database/maintainly_database_test.dart`: all 8 tests passed. Drift emitted a duplicate-database warning during the schema-upgrade test because the suite-level `setUp` created an otherwise unused database while that test created its own migration database. The test result passed, but the fixture was unnecessarily instantiating two database objects in that test.
- `flutter test test/data/maintainly_database_mapper_test.dart`: all 5 tests passed.
- The previous Web test remained at the loading stage for roughly 15 minutes. Web test verification is still unresolved; it must be rerun with verbose output after interrupting any stuck process.

Corrective change in this follow-up revision:

- Refactored `test/core/database/maintainly_database_test.dart` to create one independent in-memory database per test instead of constructing an unused database in every `setUp` plus another database in the migration test.
- Replaced deprecated `DatabaseConnection.fromExecutor(...)` with `DatabaseConnection(...)` in that test.
- The test helper registers each database for teardown. The explicit close/idempotency test remains covered.
- This change is intended to remove the avoidable duplicate-instance warning and clear the two test-only deprecation diagnostics.

Verification boundary:

- User already confirmed all 8 native database tests and all 5 mapper tests passed before this fixture cleanup.
- The fixture cleanup has been applied to source, but has **not yet been run** with Flutter/Dart in the assistant environment. User must rerun both native test commands on the new ZIP to verify the warning is gone and tests remain green.
- The 43 analyzer diagnostics were all `info` in the supplied log; no analyzer errors or warnings were shown. Existing UI deprecations/style suggestions remain deliberately unchanged.
- Step 2 is **still awaiting Web test verification and explicit user approval**. Do not start Step 3 until the user accepts Step 2 and sends `next step go`.

Recommended next commands from the project root:

```powershell
flutter pub get
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
```

Then stop any currently hanging Chrome test with Ctrl+C and capture verbose output:

```powershell
flutter devices
flutter test --platform chrome --verbose test/core/database/maintainly_database_web_test.dart 2>&1 | Tee-Object -FilePath web-test-output.txt
```



---

## Step 2 — User progression decision (13 November 2026)

The user reported these results from local testing:

- `flutter test test/core/database/maintainly_database_test.dart`: 8 tests passed on the revision tested, with a Drift warning about creating multiple database instances in the migration test.
- `flutter test test/data/maintainly_database_mapper_test.dart`: all 5 tests passed.
- `flutter analyze`: 43 diagnostics were all `info` items in the supplied output; no analyzer warning/error diagnostics were shown.
- A follow-up Step 2 Fix 2 ZIP was delivered to remove the avoidable duplicate-database test fixture warning and replace deprecated test-only `DatabaseConnection.fromExecutor` usage. The user did not provide a post-Fix-2 test result before authorizing Step 3.
- The Chrome automated Web test was not completed because it remained at the loading stage for around 15 minutes. The user preferred to avoid that potentially hanging test-runner path.
- The user ran `flutter build web` and reported a successful build at `build/web`. This proves that the current project compiled for Web, but not SQLite-in-browser data persistence because the SQLite repository is not yet connected to application data.

The user then sent `next step go`, authorizing progression to Step 3. This progression decision is recorded without claiming that the skipped Web database test passed.

---

## Step 3 — Legacy data inspection and recovery preparation

### Objective

Prepare a safe, non-destructive path from the existing SharedPreferences JSON records to SQLite. Inspect the four record collections and the seed marker, detect data problems before import, and create a portable representation of the original raw values for recovery. Keep SQLite disconnected from the active application repository.

### Changes implemented

1. Added `lib/core/data/legacy_storage_keys.dart` as the single source of truth for the five legacy SharedPreferences keys:
   - `maintainly.vehicles`
   - `maintainly.services`
   - `maintainly.expenses`
   - `maintainly.reminders`
   - `maintainly.seeded`
2. Extended `LocalStore` with read-only `readRaw()` and `containsKey()` methods. These allow inspection of unexpected stored value types without calling `getString()` and throwing a type-cast exception.
3. Added `lib/data/migration/legacy_data_inspector.dart`:
   - Distinguishes missing, empty, valid, partially valid, malformed JSON, and unexpected SharedPreferences value types.
   - Inspects all four current JSON collections using the existing model field formats.
   - Reports required ID/vehicle ID problems, invalid dates, invalid numeric values, negative values rejected by the SQLite schema, duplicate IDs, and child records that reference missing vehicles.
   - Reports warning-level missing optional fields where the existing `fromJson` factories would silently supply defaults.
   - Detects the first-launch sample-data overwrite risk when the seed marker is not exactly `yes` while one or more record keys already exist.
   - Produces a structured report with counts, statuses, and issues; it never edits SharedPreferences or SQLite.
4. Added a versioned `LegacyBackupSnapshot` representation. It captures all five known keys, whether each key existed, its stored type, and its original raw value. `encode()` returns portable JSON while preserving malformed JSON strings exactly. Step 3 does not automatically write a file or implement restore; a caller can persist the returned string in a later backup/export feature.
5. Added a repository safety guard:
   - Sample data is seeded only when the seed marker is absent and none of the four legacy record keys exists.
   - If the marker is missing but any record key exists, the repository loads the existing values rather than replacing them with sample data.
   - A wrong-type legacy record key is treated as unreadable rather than triggering a cast exception in `_decode()`; the inspector records the issue and the raw value remains intact.
   - `save()` refuses to rewrite the four JSON collections when inspection finds malformed records, invalid types, duplicate IDs, orphaned vehicle references, or other record integrity errors. This prevents a later normal save from silently replacing unreadable raw data with empty lists.
   - The seed marker is set to `yes` only after all four collection writes complete successfully.
6. Added `lib/data/migration/README.md` documenting the read-only scope, known keys, report statuses, backup snapshot, and what is intentionally deferred.
7. Added automated test coverage for the inspector and repository's legacy-data safety behaviour.

### Test coverage added

`test/data/migration/legacy_data_inspector_test.dart` contains 10 tests covering:

- Valid data across all four collections and valid vehicle relationships.
- Missing keys versus present-but-empty values.
- Malformed JSON with raw value retention.
- Partially valid arrays without silently dropping bad records from the source.
- Duplicate IDs and orphaned vehicle references.
- Invalid dates and negative values that cannot be imported into the current SQLite schema.
- First-launch sample-data overwrite risk.
- A legacy record key stored with an unexpected SharedPreferences type.
- Backup snapshot preservation of raw values and key-presence metadata.
- Warnings for missing optional fields which the existing model parsers would default.

`test/data/repositories/maintainly_repository_legacy_safety_test.dart` contains 6 tests covering:

- Existing record keys are not replaced by sample data when the seed marker is missing.
- Sample data is seeded only on a genuinely empty first launch.
- Malformed legacy JSON is preserved and does not trigger first-launch seeding.
- Saving is blocked when it would overwrite malformed legacy JSON.
- Saving is blocked when optional/missing fields would be silently defaulted and normalized.
- A missing seed marker is repaired only after a complete save of valid legacy data.

### Files changed in Step 3

- Added: `lib/core/data/legacy_storage_keys.dart`
- Modified: `lib/core/data/local_store.dart`
- Added: `lib/data/migration/legacy_data_inspector.dart`
- Added: `lib/data/migration/README.md`
- Modified: `lib/data/repositories/maintainly_repository.dart`
- Added: `test/data/migration/legacy_data_inspector_test.dart`
- Added: `test/data/repositories/maintainly_repository_legacy_safety_test.dart`
- Modified: `Incremental approach.md`
- Unchanged: SQLite schema v2, database connection, SQLite mappers, existing domain models, controller/provider APIs, forms, screens, and root `README.md`

### Data-safety boundaries

- SharedPreferences remains the active app store. SQLite is not connected to the application data flow.
- Step 3 does not import, delete, normalize, or rewrite any existing legacy record during inspection or backup-snapshot creation.
- The backup snapshot is an in-memory versioned JSON representation returned to the caller; it is not automatically saved to a file or restored in this step.
- The repository now blocks a save if current legacy collections contain data-integrity errors or missing/defaulted fields. This is intentional protection against silently overwriting unreadable or incomplete data. The current UI does not yet provide a dedicated recovery screen; a failed save will surface as an error until the later recovery UX is implemented.
- The existing `_decode()` method still returns an empty in-memory list for malformed JSON, but the raw preference remains unchanged and the new save guard prevents that empty list from being written over the malformed original.
- This step does not change the PDF report, add cloud/backend functionality, or change Android/Web deployment configuration.

### Verification performed in this environment

- Read the latest Step 2 Fix 2 ZIP as the base project and checked its file inventory and current progress log.
- Reviewed current model JSON formats, LocalStore, repository loading/seeding/saving behaviour, and SQLite v2 constraints before implementing the inspector.
- Reviewed the new source and test files statically.
- Confirmed Step 3 did not modify `pubspec.yaml`, `pubspec.lock`, SQLite schema version, UI screens, or controller/provider flow.
- **Flutter/Dart SDK is not installed in this implementation environment.** Therefore `flutter pub get`, `flutter analyze`, `flutter test`, Android runtime, and Web runtime tests have not been executed here. The 16 new tests are added but must be run by the user.
- ZIP integrity and required-file presence are checked before delivery.

### User testing instructions

Run the following from the project root after extracting this ZIP into the existing working `maintainly_app` project directory:

```powershell
flutter pub get
flutter analyze
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/repositories/maintainly_repository_legacy_safety_test.dart
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
```

Expected for the new Step 3 tests:

- Inspector suite: 10 tests pass.
- Repository safety suite: 6 tests pass.
- Existing Step 2 native database suite: 8 tests should continue to pass.
- Existing mapper suite: 5 tests should continue to pass.

Then run the existing application in Chrome using the user's preferred development workflow:

```powershell
flutter run -d chrome
```

This checks that the current Web app still launches. SQLite remains unconnected to normal app data, so this is not a test of SQLite Web persistence. A separate SQLite Web runtime verification remains planned for the later platform-verification step; the previously long-running Chrome automated test is not required for this Step 3 delivery.

### Step 3 completion criteria

- [x] Centralize the known legacy SharedPreferences keys.
- [x] Add raw-value and key-presence reads without mutating preferences.
- [x] Inspect all four JSON collections and the seed marker.
- [x] Detect malformed, partial, unexpected-type, duplicate-ID, orphan-reference, invalid-date, and SQLite-constraint issues.
- [x] Detect and guard against sample-data overwrite when legacy record keys already exist but the seed marker is missing.
- [x] Block repository saves that would overwrite malformed or relationally invalid legacy records.
- [x] Add a versioned raw-value backup snapshot representation.
- [x] Add 16 tests for inspection and repository safety.
- [x] Preserve all Step 0, Step 1, and Step 2 history and upcoming steps.
- [x] Generate and verify a complete Step 3 ZIP.
- [ ] User runs the new and regression test suites and checks Chrome app launch (final output not supplied in the conversation).
- [x] User authorizes progression to Step 4 by sending `next step go` on 13 November 2026.

### Step 3 progression decision

The user sent `next step go` on 13 November 2026 at 10:15 PM PKT, authorizing Step 4. No final Step 3 test output was supplied after the import fix, so the log records user-directed progression but does not claim the inspector suite passed on the user's machine.


---

## Step 3 — Test import correction (follow-up)

The user reported unresolved `LegacyStorageKeys` references throughout `test/data/migration/legacy_data_inspector_test.dart`.

### Root cause

- `LegacyStorageKeys` is declared in `lib/core/data/legacy_storage_keys.dart`.
- `legacy_data_inspector.dart` imports that file for its own use, but Dart imports are not automatically re-exported to libraries that import `legacy_data_inspector.dart`.
- The test imported `legacy_data_inspector.dart` and `local_store.dart`, but did not directly import the library that declares `LegacyStorageKeys`.

### Fix applied

- Added the explicit test import: `package:maintainly/core/data/legacy_storage_keys.dart`.
- No application/runtime source, database schema, repository behaviour, dependencies, or UI files were changed.
- This resolves the undefined `LegacyStorageKeys` references in the provided test source.

### Verification boundary

- The import path was checked against the existing project file tree and class declaration.
- Flutter/Dart CLI is not available in this environment, so the test suite has not been executed here.
- User should rerun the inspector test on this corrected ZIP.

### User retest command

```powershell
flutter test test/data/migration/legacy_data_inspector_test.dart
```

Expected: 10 tests pass with no `Undefined name 'LegacyStorageKeys'` errors. Step 3 remains open until the user completes testing and approves it.


---

## Step 4 — Transactional, idempotent JSON-to-SQLite migration

### Objective

Implement an explicit migration service that imports the existing four SharedPreferences JSON collections into SQLite while preserving the original source values and ensuring a failed import cannot leave a partial dataset.

### Changes implemented

1. Incremented the SQLite schema from v2 to v3 and added the `maintainly_migrations` ledger table. The ledger stores the migration key, completion timestamp, backup key, and imported counts for each collection.
2. Preserved the v2 relational table definitions and indexes as a distinct schema stage. New databases create the complete current schema; v1 databases upgrade through v2 and then v3; v2 databases add only the v3 ledger.
3. Added `LegacyStorageKeys.migrationBackup` as a separate backup key. It is deliberately excluded from the list of legacy source keys so a backup never recursively captures itself.
4. Added `LocalStore.writeVerified()`, which checks that SharedPreferences accepted the backup write and can read the exact snapshot back before migration continues.
5. Added `LegacyJsonToSqliteMigrator`:
   - Opens the current SQLite database and checks the migration ledger before doing work.
   - Creates and persists a versioned snapshot of the raw source values before validating/importing.
   - Blocks import when the Step 3 inspection report has errors, warnings/defaulted fields, duplicate IDs, orphan references, malformed values, or a seed-marker risk. The backup is kept even when migration is blocked.
   - Preserves an existing matching backup. If a previous backup exists but source values have since changed, it preserves the old backup and writes a separately named snapshot for the new source state.
   - Parses and maps all four collections using the current domain models and `MaintainlyDatabaseMapper`.
   - Inserts vehicles before child rows to satisfy foreign keys.
   - Runs all inserts, row-count verification, and the migration-ledger insert inside a single Drift transaction.
   - Refuses to write over non-empty SQLite tables when there is no migration ledger entry.
   - Returns `alreadyMigrated` on repeat calls rather than inserting duplicates.
   - Never deletes or rewrites the original four source keys or the `maintainly.seeded` marker.
6. Updated the database migration test to cover the v1-to-v3 and v2-to-v3 upgrade paths.
7. Added `test/data/migration/legacy_json_to_sqlite_migrator_test.dart` with ten scenarios: complete import and field checks, idempotent retry, malformed-source blocking with backup, partially-valid-source blocking, full rollback on a forced child-insert failure, successful retry after rollback, protection of pre-existing target rows, empty valid migration, blocking a completely fresh unseeded installation, and preserving an earlier backup when the source changes.
8. Updated the migration and database README files to document schema v3 and the exact migration safety boundaries.
9. Updated this log and retained all prior Step 0–3 history and Steps 5–10 roadmap entries.

### Data-safety boundaries

- The migrator is an explicit service and is not automatically invoked at app startup.
- The application's active controller/repository and UI still use SharedPreferences in this step.
- The original JSON source keys are not deleted, normalized, or rewritten.
- The pre-import snapshot is persisted inside SharedPreferences under `maintainly.legacy.backup.v1`; it is not yet a user-selected file export or a restore interface.
- A blocked migration keeps the backup but inserts no rows and no migration ledger entry.
- Any unexpected insert/verification error should roll back all rows and the ledger entry through the same SQLite transaction.
- If target tables contain records without a ledger row, migration stops instead of merging or overwriting them.

### Files changed in Step 4

- Modified: `lib/core/data/legacy_storage_keys.dart`
- Modified: `lib/core/data/local_store.dart`
- Modified: `lib/core/database/maintainly_schema.dart`
- Modified: `lib/core/database/maintainly_database.dart`
- Added: `lib/data/migration/legacy_json_to_sqlite_migrator.dart`
- Modified: `lib/data/migration/README.md`
- Modified: `lib/core/database/README.md`
- Modified: `test/core/database/maintainly_database_test.dart`
- Added: `test/data/migration/legacy_json_to_sqlite_migrator_test.dart`
- Modified: `Incremental approach.md`

### Verification performed in this environment

- Reviewed the latest Step 3 Fix 1 ZIP as the base project and inspected the existing models, raw JSON keys, repository, inspector, mapper, database, schema, and existing tests.
- Checked the Drift 2.35.4 APIs used by the implementation against the package API: parameterized `customInsert`/`customSelect`, typed `Variable` values, and `transaction()`.
- Reviewed the schema upgrade path from v1 to v3 and v2 to v3.
- Reviewed the migration ordering, backup-first flow, source immutability, duplicate-import guard, pre-existing target-row guard, and transaction rollback test design.
- **Flutter/Dart SDK is not installed in this implementation environment.** Therefore `flutter pub get`, `flutter analyze`, `flutter test`, Android runtime, and Web runtime tests have not been executed here. Do not treat the new ten tests as passed until they are run in the user's Flutter 3.47.5 environment.
- ZIP integrity and required files will be checked before delivery.

### User testing instructions

Run from the project root after replacing the current `maintainly_app` folder with this complete Step 4 ZIP:

```powershell
flutter pub get
flutter analyze
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/repositories/maintainly_repository_legacy_safety_test.dart
flutter test test/data/migration/legacy_json_to_sqlite_migrator_test.dart
flutter run -d chrome
```

Expected new migration suite: 10 tests pass. The database schema/upgrade suite now has 9 tests; the mapper suite has 5, legacy inspector suite has 10, and repository safety suite has 6. These are regression checks for schema upgrades, mappers, legacy inspection, and repository protection. `flutter run -d chrome` checks that the existing Web app still launches; it does not yet test SQLite-backed repository persistence because the controller/repository cutover is intentionally deferred.

### Step 4 completion criteria

- [x] Add schema v3 migration ledger table.
- [x] Preserve v2 schema and add explicit v1→v3 and v2→v3 upgrade paths.
- [x] Persist and verify raw SharedPreferences backup before import.
- [x] Block unsafe legacy source data before any SQLite row import.
- [x] Add a one-transaction import for all four collections.
- [x] Verify record counts before writing the completion ledger.
- [x] Make repeat migration calls idempotent.
- [x] Refuse to overwrite untracked pre-existing SQLite rows.
- [x] Keep original SharedPreferences source data unchanged.
- [x] Add ten migration scenarios and update database upgrade tests.
- [x] Block a completely fresh unseeded installation from being marked migrated.
- [x] Preserve previous step history and upcoming steps.
- [x] User reports all Step 4 migration and regression test suites passed in Flutter 3.47.5.
- [x] User reports the existing Chrome development run works; a previous `flutter build web` also completed successfully. This is not a SQLite Web persistence test.
- [x] User ran `flutter analyze`: 0 errors, 0 warnings, and 43 informational suggestions.
- [x] Removed four analyzer-confirmed unused imports from `legacy_data_inspector.dart`.
- [x] Removed the analyzer-confirmed unnecessary non-null assertion from `maintainly_database_test.dart`.
- [x] User explicitly authorized Step 5 by sending `next step go` on 13 November 2026.

### Step 6 delivery status

**Step 6 — SQLite write path and CRUD integration.** Implemented in this delivery. User testing and approval are pending. Step 7 remains blocked until the user confirms the Step 6 tests and sends `next step go`.

## Step 4 — Fix 1: Migration test matcher compatibility

- **Status:** Prepared for user testing; Step 4 remains open.
- **Date:** 2026-11-13.
- **Scope:** Test-only correction in `test/data/migration/legacy_json_to_sqlite_migrator_test.dart`.
- **Change:** Replaced unsupported `isNotNull` matcher references with the equivalent `isNot(isNull)` matcher expression exported by the Flutter test matcher API.
- **Production code:** No changes to the migrator, database schema, repository, controller, providers, UI, or SharedPreferences data handling.
- **Tests executed here:** Static source verification only. Flutter/Dart tests were not executed in this environment.
- **User verification:** Run `flutter test test/data/migration/legacy_json_to_sqlite_migrator_test.dart` and share the result.
- **Next pending action:** Resolve any remaining Step 4 test issues, then user acceptance. Step 5 remains not started.


## Step 4 — Fix 2: Remove nullable matcher dependency from migration tests

- **Status:** Prepared for user testing; Step 4 remains open.
- **Date:** 2026-11-13.
- **Scope:** Test-only correction in `test/data/migration/legacy_json_to_sqlite_migrator_test.dart`.
- **Reason:** The previous `isNotNull` matcher was not recognized in the user's test environment, and the replacement `isNot(isNull)` also produced an error.
- **Change:** Replaced all seven null matcher assertions with plain boolean expectations, for example `expect(value != null, true)`. This avoids relying on either `isNotNull` or `isNot(isNull)`.
- **Production code:** No changes to the migrator, database schema, repository, controller, providers, UI, or SharedPreferences handling.
- **Tests executed here:** Static inspection only. Flutter/Dart CLI is not available in this environment, so the test was not executed here.
- **User verification:** Run `flutter test test/data/migration/legacy_json_to_sqlite_migrator_test.dart` and share the complete output if it still fails.
- **Next pending action:** Finish Step 4 test verification and obtain user approval. Step 5 remains not started.


## Step 4 — Final user verification and analyzer cleanup

- **Status:** Implementation and user-reported test verification complete; waiting for explicit authorization before Step 5.
- **Date:** 2026-11-13.
- **User-reported automated tests:** All Step 4 tests passed. The migration test suite specifically reported `+10: All tests passed!`; the user subsequently confirmed that all remaining tests passed as well.
- **Latest user-reported `flutter analyze`:** 43 issues, all `info`; zero warnings and zero errors.
- **Analyzer cleanup included in this project package:** Removed four unused model imports from `lib/data/migration/legacy_data_inspector.dart`; removed the unnecessary `!` from `test/core/database/maintainly_database_test.dart`. The user's subsequent analyzer output confirms that warnings are cleared.
- **Remaining informational suggestions:** Existing `prefer_const_constructors`, deprecated `value`/`withOpacity` APIs, `prefer_final_fields`, flow-control braces, and one initializing-formal suggestion. These are non-blocking info-level suggestions and are intentionally not mixed into the SQLite migration scope.
- **Storage state:** SharedPreferences remains the active application repository. The transactional JSON-to-SQLite migrator is implemented and tested but is not automatically invoked and is not yet wired into the app's read/write flow.
- **Chrome state:** The user previously confirmed `flutter run -d chrome` works and reported a successful `flutter build web`. Neither result proves SQLite-backed Web persistence; that must be checked when the Web read/write path is integrated.
- **Step 5:** Subsequently implemented, tested, and explicitly approved by the user; see the Step 5 delivery and verification record below.
- **Next action at the time of this historical entry:** Awaited explicit authorization for Step 5. This was later supplied by the user.


## Step 5 — SQLite read path and guarded startup migration

### Objective

Connect the existing repository boundary to SQLite reads without changing the controller or screen APIs. Only use SQLite as the read source after the migration ledger confirms that all four collections were imported and verified. Preserve SharedPreferences as a recovery and temporary write fallback until Step 6.

### Changes implemented

1. Added an optional `MaintainlyDatabase` dependency to `MaintainlyRepository`, preserving the original `MaintainlyRepository(store)` construction used by legacy-only tests and callers.
2. Added a private SQLite read path that checks the `maintainly_migrations` ledger for `legacy_shared_preferences_to_sqlite_v1` before reading application tables.
3. Reads the four collections (`vehicles`, `service_records`, `vehicle_expenses`, and `maintenance_reminders`) in their SQLite row insertion order and maps them through `MaintainlyDatabaseMapper` into the existing domain model lists.
4. Verifies each table's actual row count against the migration ledger and verifies `total_record_count` against the sum of the four ledger counts before returning a SQLite snapshot. Inconsistent or incomplete data is never returned as a valid partial dataset.
5. Updated the application provider to supply `MaintainlyDatabase` and enable backup-first automatic migration during startup. The repository loads the legacy snapshot first; a valid migration then completes and the repository re-reads from SQLite. If the inspector blocks migration, the legacy snapshot remains active.
6. Added a graceful legacy fallback for SQLite open/ledger-read failures and migration exceptions. The original JSON data is retained; the fallback reason is written to debug logs.
7. Kept the existing SharedPreferences `save()` path in place for this step. When a repository session reads from SQLite and subsequently saves through the legacy path, it writes a read-fallback marker after the four JSON collection writes. The next launch uses the newer SharedPreferences snapshot instead of stale SQLite data until Step 6 implements SQLite writes.
8. Persisted a small migration-completed preference marker after a successful ledger read. This allows the repository to recognize a previously migrated installation if SQLite is temporarily unavailable on a later launch, so a subsequent legacy save can still activate the safe fallback marker.
9. Added `test/data/repositories/maintainly_repository_sqlite_read_test.dart` with 11 tests for legacy fallback, SQLite reads for all four collections, auto-migration, fresh-install seeding, blocked migration, ledger count mismatch, post-SQLite legacy-write fallback, migration-completed marker handling, and database-open failure handling.
10. Updated database/migration documentation and the root README storage description to reflect the actual transitional implementation.

### Files changed in Step 5

- Modified: `lib/data/repositories/maintainly_repository.dart`
- Modified: `lib/application/providers.dart`
- Added: `test/data/repositories/maintainly_repository_sqlite_read_test.dart`
- Modified: `lib/data/migration/README.md`
- Modified: `lib/core/database/README.md`
- Modified: `README.md`
- Modified: `Incremental approach.md`

### Behaviour and safety boundaries

- The application provider enables automatic migration at startup, after the repository first loads the legacy snapshot. The migrator still performs its existing backup-first inspection and one-transaction import.
- If migration is blocked, the app continues with SharedPreferences. Original legacy keys and backup snapshots are not deleted.
- If SQLite initialization or its migration-ledger read fails, the app logs the fallback reason and uses SharedPreferences. No SQLite write operation is performed by this step.
- If the migration ledger exists but row counts or mapping are inconsistent, the repository does not return a partial SQLite dataset; it falls back to the preserved legacy snapshot and logs the issue.
- Controller methods, screens, navigation, and UI widgets are unchanged.
- Writes remain on SharedPreferences in this step. A fallback marker prevents a later launch from displaying stale SQLite data after a save from a SQLite-loaded session.
- Cloud sync, external backup export, restore UI, and the full SQLite CRUD write path are not implemented here.

### Verification performed in this environment

- Reviewed the Step 4 completed ZIP as the base project and rechecked the repository, provider, controller contract, SQLite schema, migration ledger, and mapper APIs.
- Checked the read queries against the Step 4 schema table and migration-ledger column names.
- Verified the four read table names match the existing schema and migrator.
- Confirmed that the repository's new method is private, so the provider's `_DeferredRepository implements MaintainlyRepository` contract remains limited to its existing `load` and `save` methods.
- Confirmed the new tests avoid `isNotNull` matchers and exercise the legacy fallback path.
- Flutter/Dart CLI is not installed in this implementation environment; local compilation and execution were therefore performed by the user in Flutter 3.47.5.
- User-reported `flutter analyze`: 45 issues, all `info`; 0 errors and 0 warnings. The info suggestions include initializing-formal/const suggestions and existing deprecation/style suggestions; they were not treated as blocking issues.
- User-reported automated test results: SQLite read path 11/11; database schema 9/9; model mapper 5/5; legacy data inspector 10/10; JSON-to-SQLite migrator 10/10; repository legacy-safety 6/6. Total: 51/51 tests passed.
- User ran `flutter run -d chrome`; Flutter connected to Chrome and started the application successfully. The output included a notice that Flutter replaced the existing viewport meta tag and selected `WasmStorageImplementation.sharedIndexedDb` because some browser features were unavailable. The user confirmed the app was running and approved Step 5. These messages were non-fatal in the reported run.
- No claim is made that a separate production Web build, cross-browser persistence test, or automated Chrome test was run in this final Step 5 verification.
- ZIP integrity and required project files are checked before delivery.

### User testing instructions

Run from the project root after replacing the current working `maintainly_app` folder with this complete Step 5 ZIP:

```powershell
flutter pub get
flutter analyze
flutter test test/data/repositories/maintainly_repository_sqlite_read_test.dart
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/migration/legacy_json_to_sqlite_migrator_test.dart
flutter test test/data/repositories/maintainly_repository_legacy_safety_test.dart
```

Expected new Step 5 suite: 11 tests pass. Existing regression suites should also continue to pass. `flutter analyze` may still report existing info-level style/deprecation suggestions; there should be no new errors or warnings from Step 5.

For Web manual testing, make sure Drift's Web assets exist in `web/` (the full-project ZIP keeps the setup scripts but does not package generated WASM/worker files). On Windows, run the following once if those assets are not already present:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\setup_drift_web_assets.ps1
flutter run -d chrome
```

Do not run the long Chrome automated test as part of this step. The user prefers manual browser testing. Confirm that the app opens, the dashboard and all four data screens render, and existing records appear. When migration is valid and database initialization succeeds, the provider should migrate and read through SQLite; if not, it should log a fallback and load preserved JSON data.

### Step 5 completion criteria

- [x] Add SQLite read path behind the existing repository boundary.
- [x] Gate SQLite reads on the committed migration ledger.
- [x] Verify ledger totals and actual table counts before mapping records.
- [x] Add startup migration orchestration in the application provider.
- [x] Preserve SharedPreferences fallback for blocked migration and SQLite initialization/read errors.
- [x] Protect newer legacy saves from being hidden by stale SQLite reads.
- [x] Add 11 repository read-path tests.
- [x] Preserve previous step history and update the upcoming Step 6–10 roadmap.
- [x] Generate and verify the complete Step 5 project ZIP.
- [x] User ran the SQLite repository read-path suite: 11/11 passed.
- [x] User ran the database schema regression suite: 9/9 passed.
- [x] User ran the model mapper regression suite: 5/5 passed.
- [x] User ran the legacy data inspector suite: 10/10 passed.
- [x] User ran the JSON-to-SQLite migration suite: 10/10 passed.
- [x] User ran the repository legacy-safety suite: 6/6 passed.
- [x] User ran `flutter analyze`: 0 errors, 0 warnings, and 45 info-level suggestions.
- [x] User ran `flutter run -d chrome`; application launched successfully. The reported viewport-meta and SharedIndexedDB feature-selection notices were non-fatal.
- [x] User explicitly confirmed Step 5 is done.
- [x] User explicitly authorized Step 6 by sending `next step go` on 15 November 2026.

### Next planned step (not started)

**Step 7 — Relationships and business-rule integrity.** Review service/reminder linkage, vehicle deletion/archive policy, odometer validation, and expense/service cost rules. Do not begin until Step 6 is tested and explicitly approved by the user.


---

## Step 6 — SQLite write path and CRUD integration

### Status and objective

- **Status:** User-approved after local verification; all six requested test files passed (53/53 total) on 15 November 2026.
- **Authorization:** User sent `next step go` on 15 November 2026.
- **Objective:** Move the existing repository save path to SQLite after a successful legacy migration, while preserving the existing controller/UI contract and transaction safety.
- **Scope choice:** The current repository API saves a complete `MaintainlyData` snapshot rather than exposing per-record database methods. This step therefore implements an atomic four-collection snapshot write. Existing controller CRUD methods continue to call `_persist()` and do not require public API changes.

### Files changed

- `lib/data/repositories/maintainly_repository.dart` — added transactional SQLite snapshot replacement, row-count verification, migration-ledger count updates, and post-commit clearing of the Step 5 fallback marker. Retained legacy SharedPreferences writes for pre-migration, database-less, and SQLite-unavailable cases.
- `test/data/repositories/maintainly_repository_sqlite_read_test.dart` — updated the former Step 5 legacy-write expectation to assert SQLite writes; added rollback and compatibility-fallback cutover coverage.
- `Incremental approach.md` — updated project status and appended this Step 6 record.

### Technical behaviour

1. SQLite writes are enabled only when a database is supplied, the migration ledger has been confirmed, and SQLite has not already been marked unavailable in this repository session.
2. The repository checks that exactly one migration-ledger row exists before writing.
3. One database transaction deletes child rows first, then vehicles; it inserts vehicles first, followed by services, expenses, and reminders.
4. Each collection's row count is verified before commit. The migration ledger's timestamp and four collection counts plus total count are updated inside the same transaction.
5. The Step 5 legacy-write fallback marker is set to false only after the SQLite transaction commits. If the transaction throws, SQLite rolls back and the marker is not cleared.
6. The original SharedPreferences source and migration backup are not deleted or rewritten by the SQLite write path.
7. When migration has not completed, no database is configured, or SQLite is unavailable, the guarded legacy write path remains available.

### Tests added or updated

- Updated repository test: saving a changed vehicle snapshot writes the changed value to SQLite, reloads it from SQLite, and maintains correct migration-ledger counts.
- Added rollback test: an orphan service with a non-existent vehicle ID violates the foreign key; the full transaction must roll back and preserve the original SQLite snapshot.
- Added compatibility test: a Step 5 legacy-write fallback snapshot is read, then saved into SQLite; after commit, the fallback marker is cleared and the SQLite snapshot becomes authoritative.
- Existing tests continue to cover legacy-only construction and SharedPreferences fallback when SQLite is unavailable.

### Verification in this environment

- Inspected the Step 5 ZIP as the exact base and reviewed the repository, controller save contract, database schema, migration ledger, mapper, and existing tests.
- Confirmed all SQL table and ledger column names against the Step 5 schema and migration implementation.
- Flutter/Dart CLI is not installed in this implementation environment. No Flutter formatter, analyzer, or test command is claimed as executed here.
- User-side test results are pending.

### User testing instructions

Run from the project root after replacing the current `maintainly_app` folder with this complete Step 6 ZIP:

```powershell
flutter pub get
dart format lib/data/repositories/maintainly_repository.dart test/data/repositories/maintainly_repository_sqlite_read_test.dart
flutter analyze
flutter test test/data/repositories/maintainly_repository_sqlite_read_test.dart
flutter test test/data/repositories/maintainly_repository_legacy_safety_test.dart
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/migration/legacy_json_to_sqlite_migrator_test.dart
```

Expected: all tests pass; analyzer should report no errors or warnings. Existing info-level style suggestions may remain.

Manual app checks (Chrome and Android where available):

1. Start with a migrated dataset and confirm existing vehicles, services, expenses, and reminders appear.
2. Add a vehicle, edit its name/details, restart the app, and confirm the changes persist.
3. Add/edit/delete a service record and confirm the list remains correct after restart.
4. Add/edit/delete an expense and confirm it remains correct after restart.
5. Add/toggle/delete a reminder and confirm its completion state persists after restart.
6. Delete a vehicle and confirm its associated service, expense, and reminder records follow the app's existing cascade behaviour.
7. Confirm the dashboard, reports, and totals still render without duplicate records.

If any command fails, share the full error/output. Fix Step 6 first; do not move to Step 7 until the user confirms the step is complete.

### Step 6 completion checklist

- [x] Add transactional SQLite snapshot writes behind the existing repository save API.
- [x] Insert parent vehicles before child records and delete child records before parents.
- [x] Verify table row counts and update the migration ledger in the same transaction.
- [x] Clear the Step 5 fallback marker only after a successful SQLite commit.
- [x] Retain guarded SharedPreferences fallback for migration/database-unavailable cases.
- [x] Add/update repository tests for write/reload, rollback, and fallback cutover.
- [x] Preserve existing controller and screen APIs.
- [x] Update this incremental log and package a complete project ZIP.
- [x] User reports all six test files passed locally (53/53 total) on 15 November 2026.
- [x] User approved Step 6 and explicitly authorized Step 7 with `next step go`.

**Next pending step:** Step 7 — Relationships and business-rule integrity. Authorized; implementation is being delivered in small substeps.


## Step 7 — Substep 1: Service-to-reminder relationship integrity

### Status and objective

- **Status:** Implementation prepared; user testing and approval pending.
- **Authorization:** User sent `next step go` for Step 7 and then `next substep go` for this first substep on 15 November 2026.
- **Objective:** Make service-generated maintenance reminders explicitly traceable to their source service. Editing or deleting a service must affect only its linked reminder; manually created reminders must remain independent.

### Changes implemented

1. Added nullable `source_service_id` to maintenance reminders in schema v4. Existing reminders remain NULL/unlinked.
2. Added a foreign key from `source_service_id` to `service_records(id)` with `ON DELETE CASCADE`, plus a partial unique index so one service cannot own multiple generated reminders.
3. Added an explicit v3-to-v4 migration. New databases also create the v4 column/index through the normal schema creation path.
4. Extended the reminder model, JSON representation (backwards-compatible optional field), and SQLite mapper with `sourceServiceId`.
5. The controller now creates a linked reminder when a service has a next due date or odometer, updates the same reminder when that service is edited, removes it when due values are removed, and removes it when the service is deleted. Editing a service resets its linked reminder to incomplete.
6. Manual reminders have no source service ID and are not modified by service edits/deletes. Legacy reminders are not guessed/auto-linked.

### Files changed

- `lib/core/database/maintainly_schema.dart`
- `lib/core/database/maintainly_database.dart`
- `lib/data/models/maintenance_reminder.dart`
- `lib/data/mappers/maintainly_database_mapper.dart`
- `lib/data/repositories/maintainly_repository.dart`
- `lib/data/migration/legacy_data_inspector.dart` — validates the new optional source link when present without warning on older JSON records.
- `lib/application/maintainly_controller.dart`
- `test/core/database/maintainly_database_test.dart`
- `test/data/maintainly_database_mapper_test.dart`
- `test/data/migration/legacy_data_inspector_test.dart`
- `test/application/maintainly_controller_service_reminder_test.dart` (new)
- `Incremental approach.md`

### Tests added/updated

- Schema v3-to-v4 upgrade and new index presence.
- Service deletion cascades to its linked reminder but leaves a manual reminder untouched.
- Reminder mapper round-trip includes the optional source service ID.
- Legacy reminder inspection accepts an absent/null source link for backward compatibility and rejects a non-string value when the field is present (two regression tests).
- Controller tests cover linked reminder creation, update without duplication, deletion, and removal when next-due values are cleared.

### Verification in this environment

- Source and SQL migration paths were inspected after editing.
- Flutter/Dart CLI is not installed in this implementation environment; formatter, analyzer, and test execution have **not** been run here. No passing result is claimed.
- User must run the commands below and report actual results before this substep is approved.

### User testing instructions

Run from the project root:

```powershell
flutter pub get
dart format lib/core/database/maintainly_schema.dart lib/core/database/maintainly_database.dart lib/data/models/maintenance_reminder.dart lib/data/mappers/maintainly_database_mapper.dart lib/data/repositories/maintainly_repository.dart lib/application/maintainly_controller.dart test/core/database/maintainly_database_test.dart test/data/maintainly_database_mapper_test.dart test/application/maintainly_controller_service_reminder_test.dart
flutter analyze
flutter test test/application/maintainly_controller_service_reminder_test.dart
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/repositories/maintainly_repository_sqlite_read_test.dart
flutter test test/data/repositories/maintainly_repository_legacy_safety_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
flutter test test/data/migration/legacy_json_to_sqlite_migrator_test.dart
```

Manual checks: add a service with a next due value and verify one reminder appears; edit it and verify that same reminder updates without duplication; remove its next-due values and verify only the generated reminder disappears; add a manual reminder and verify it survives service edits/deletion; delete the service and verify its linked reminder disappears.

### Completion checklist

- [x] Add a nullable service source link and versioned schema migration.
- [x] Persist and restore the source link through JSON and SQLite.
- [x] Implement linked reminder create/update/delete behaviour.
- [x] Preserve independent manual reminders and leave legacy reminders unlinked.
- [x] Add schema, mapper, and controller regression tests.
- [ ] User runs formatter, analyzer, and listed tests.
- [ ] User performs manual checks and approves this substep.

**Next:** Wait for user test results; do not begin another Step 7 substep until this one is approved and the user explicitly authorizes it.


## Step 7 — Substep 2: Numeric and odometer input validation

### Status and objective

- **Status:** Implementation delivered; automated and manual verification pending.
- **Authorization:** User sent `next step go` on 16 November 2026. User requested that manual testing be deferred until the work through Step 10 is complete.
- **Objective:** Reject negative odometer values and negative/non-finite money values consistently in forms, controller operations, and repository persistence, without changing historical record ordering rules.

### Changes implemented

1. Added `MaintainlyDataValidator` as a shared validation boundary for vehicle, service, expense, and reminder records.
2. Controller save operations validate the incoming record before mutating in-memory lists, preventing invalid values from partially changing controller state.
3. Repository snapshot saves validate all four collections before either the legacy SharedPreferences write path or the SQLite transaction.
4. Vehicle, service, expense, and reminder forms now reject negative odometer values. Optional due-odometer inputs remain optional when blank, but invalid non-empty values no longer silently turn into `null`.
5. Purchase price, service cost, and expense amount must parse to finite numbers that are zero or greater. Decimal input keyboards are enabled for money fields.
6. No schema migration was needed: schema v2 already contains SQLite `CHECK` constraints for non-negative odometers and monetary values, and the Step 3 legacy inspector already rejects negative values in imported legacy collections.
7. Added controller regression tests for invalid vehicle/service/expense/reminder values and a repository-boundary regression test.

### Historical odometer policy deliberately not changed

- This substep does not require every newly saved service/expense odometer to be greater than the vehicle's current odometer. Older service records can legitimately be entered after newer ones, and rejecting them would damage historical entry workflows.
- A monotonic/current-odometer correction policy and user-facing warning for out-of-order records need a separate explicit rule and are deferred rather than guessed.
- The previously identified `Overdue` status behaviour is unchanged and remains a known issue from the original Step 0 code.

### Files changed

- Added `lib/data/validation/maintainly_data_validator.dart`
- `lib/application/maintainly_controller.dart`
- `lib/data/repositories/maintainly_repository.dart`
- `lib/presentation/dialogs/forms.dart`
- Added `test/application/maintainly_controller_numeric_validation_test.dart`
- Added `test/data/repositories/maintainly_repository_numeric_validation_test.dart`
- `Incremental approach.md`

### Verification boundary

- Source-level inspection completed.
- Existing SQLite `CHECK` constraints and legacy inspector numeric checks were inspected and reused; no schema version change was introduced.
- Flutter/Dart executables are not installed in this implementation environment. `dart format`, `flutter analyze`, and Flutter tests have not been run here; no pass is claimed.
- User-requested manual testing is deferred until Step 10 final regression.

### Suggested automated verification (run at final Step 10 testing)

```powershell
flutter pub get
dart format lib/data/validation/maintainly_data_validator.dart lib/application/maintainly_controller.dart lib/data/repositories/maintainly_repository.dart lib/presentation/dialogs/forms.dart test/application/maintainly_controller_numeric_validation_test.dart test/data/repositories/maintainly_repository_numeric_validation_test.dart
flutter analyze
flutter test test/application/maintainly_controller_numeric_validation_test.dart
flutter test test/data/repositories/maintainly_repository_numeric_validation_test.dart
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/migration/legacy_data_inspector_test.dart
```

### Completion checklist

- [x] Validate all numeric values in controller operations before state mutation.
- [x] Validate complete snapshots before repository persistence.
- [x] Reject negative and non-finite values in relevant forms.
- [x] Preserve optional due odometer semantics while rejecting invalid non-empty input.
- [x] Add focused regression tests.
- [ ] Run formatter, analyzer, and tests using the user's Flutter SDK during Step 10 final regression.
- [ ] Complete final manual checks during Step 10.

**Next:** Step 7 Substep 3 — decide and implement the service-cost/expense relationship to prevent double-counting, using an explicit data model rather than heuristic category matching.


## Step 7 — Substep 3 (combined): Financial integrity and vehicle-history preservation

### Status and scope

- **Status:** Implementation prepared; automated verification pending. Manual checks are intentionally deferred until Step 10 as requested.
- **Baseline:** User reported all 67 tests passed on the previous Substep 7-2 source state; this does not verify the current combined changes.
- **Authorization:** User explicitly authorized the combined Substeps 7-3 and 7-4 on 16 November 2026.
- **Combined scope:** (A) prevent service/expense double-counting through an explicit relationship; (B) replace destructive vehicle deletion in the application with reversible archiving so the vehicle's history remains available.

### Service and expense relationship

1. Added nullable `source_service_id` to `vehicle_expenses` in schema v5. The foreign key references `service_records(id)` with `ON DELETE SET NULL`, so deleting a service preserves its expense and converts it back to a standalone expense.
2. Added optional `sourceServiceId` to the expense model and backward-compatible JSON/SQLite mapping. Existing expenses remain unlinked and retain their previous totals.
3. The expense form now lets the user explicitly select the service whose recorded total already includes that expense. No category, amount, date, or description heuristics are used.
4. Linked expenses remain visible in the expense history but are excluded from standalone expense totals, dashboard total spending, vehicle-card spending, and PDF totals. The service cost remains counted once.
5. The controller and snapshot validator require the linked service to exist and belong to the same vehicle. The sum of linked itemized expenses cannot exceed the service's recorded cost.
6. Deleting a service or moving it to another vehicle unlinks associated expenses instead of deleting them. An unlinked expense then contributes to standalone spending.

### Vehicle history preservation

1. Added `is_archived` to vehicles in schema v5 and `isArchived` to the vehicle model/JSON mapper. Existing vehicles migrate as active (`false`).
2. The vehicle screen's former Delete action is now Archive. It removes the vehicle from active vehicle pickers and reminder attention counts but preserves the vehicle, services, expenses, and reminders.
3. Added Active / Archived views and a Restore action. Archived vehicles and their historical service/expense data remain available in reports and vehicle details.
4. New service, expense, and reminder records can only be assigned to active vehicles. Existing historical records attached to an archived vehicle remain viewable and editable without changing their vehicle association.
5. The database's underlying `ON DELETE CASCADE` constraints remain as a final relational safeguard for an actual database-level hard delete; the normal application action no longer issues a vehicle delete.

### Schema and compatibility

- Schema version advanced from v4 to v5 with an explicit upgrade path.
- New databases create v5 directly; v4 databases add the archive flag and expense link; older v1-v3 databases continue through v2, v3, v4, and v5 in order.
- Legacy JSON without `isArchived` or `sourceServiceId` remains compatible through defaults of active/unlinked.
- The existing whole-snapshot SQLite transaction now writes both new fields. Parent service rows are inserted before linked expense rows.

### Files changed

- `lib/core/database/maintainly_schema.dart`
- `lib/core/database/maintainly_database.dart`
- `lib/data/models/vehicle.dart`
- `lib/data/models/expense.dart`
- `lib/data/mappers/maintainly_database_mapper.dart`
- `lib/data/validation/maintainly_data_validator.dart`
- `lib/data/migration/legacy_data_inspector.dart`
- `lib/data/repositories/maintainly_repository.dart`
- `lib/application/maintainly_controller.dart`
- `lib/presentation/dialogs/forms.dart`
- `lib/presentation/screens/vehicles_screen.dart`
- `lib/presentation/screens/expenses_screen.dart`
- `lib/presentation/screens/maintenance_screen.dart`
- `lib/presentation/screens/dashboard_screen.dart`
- `lib/presentation/screens/reports_screen.dart`
- `test/core/database/maintainly_database_test.dart`
- `test/data/maintainly_database_mapper_test.dart`
- `test/data/repositories/maintainly_repository_numeric_validation_test.dart`
- `test/application/maintainly_controller_service_reminder_test.dart`
- `Incremental approach.md`

### Automated regression coverage added/updated

- Schema v4-to-v5 upgrade and new columns/index.
- Service deletion sets linked expense `source_service_id` to NULL without deleting the expense.
- Expense mapper round-trip includes the nullable service link; vehicle mapper round-trip includes archive status.
- Controller archiving/restoring preserves vehicle, service, expense, and reminder records.
- Legacy inspection validates the types of the new optional `isArchived` and expense `sourceServiceId` JSON fields while remaining compatible with older records.
- Linked expense amounts are excluded from totals while visible in history; deleting the service unlinks and re-counts the expense.
- Controller rejects linked expenses exceeding the service cost; repository snapshot validation rejects cross-vehicle or missing service links.

### Verification boundary

- Source and SQL paths were statically inspected and the project ZIP was prepared from the current source tree.
- Flutter/Dart CLI is unavailable in this implementation environment. `dart format`, `flutter analyze`, and tests have **not** been run here; no pass is claimed for this substep.
- The user subsequently reported the complete non-browser suite passing (81 passed, 1 skipped) on the project containing these Step 7 changes. The single skipped test is the Chrome database test, deferred to Step 9.
- Manual testing remains deferred until Step 10, per the user's instruction.

### Suggested automated verification

Run from the project root in PowerShell:

```powershell
flutter pub get
dart format lib/core/database/maintainly_schema.dart lib/core/database/maintainly_database.dart lib/data/models/vehicle.dart lib/data/models/expense.dart lib/data/mappers/maintainly_database_mapper.dart lib/data/validation/maintainly_data_validator.dart lib/data/repositories/maintainly_repository.dart lib/application/maintainly_controller.dart lib/presentation/dialogs/forms.dart lib/presentation/screens/vehicles_screen.dart lib/presentation/screens/expenses_screen.dart lib/presentation/screens/maintenance_screen.dart lib/presentation/screens/dashboard_screen.dart lib/presentation/screens/reports_screen.dart test/core/database/maintainly_database_test.dart test/data/maintainly_database_mapper_test.dart test/data/repositories/maintainly_repository_numeric_validation_test.dart test/application/maintainly_controller_service_reminder_test.dart
flutter analyze
flutter test test/core/database/maintainly_database_test.dart
flutter test test/data/maintainly_database_mapper_test.dart
flutter test test/application/maintainly_controller_service_reminder_test.dart
flutter test test/data/repositories/maintainly_repository_numeric_validation_test.dart
flutter test
```

### Step 7 completion checklist

- [x] Substep 1 — service/reminder relationship implementation.
- [x] Substep 2 — numeric validation implementation.
- [x] Combined Substep 3 — service/expense double-counting relationship and reversible vehicle archiving implementation.
- [x] User reported the latest non-browser automated suite passed; the browser database test is explicitly deferred to Step 9.
- [ ] Run formatter and analyzer during Step 10 final regression.
- [ ] Complete manual regression checks during Step 10.

**Next:** Step 8 — backup/restore reliability and schema migration/recovery hardening, after the user runs the automated checks for this combined substep.


## Step 8 — Reliability, backup, and recovery

### Substep 8.1 — Existing migration and backup safety review

- **Status:** Review completed; no application code or database schema changed in this substep.
- **Baseline:** The user's uploaded `maintainly_app(1).rar` archive, received on 16 November 2026, is the source baseline for Step 8.
- **Review scope:** `MaintainlyDatabase`, `MaintainlySchema`, `LegacyStorageKeys`, `LocalStore`, `LegacyDataInspector`, `LegacyBackupSnapshot`, `LegacyJsonToSqliteMigrator`, `MaintainlyRepository`, relevant schema/migration tests, and migration documentation.

#### Confirmed existing protections

1. SQLite schema is currently version 5. New databases create the latest schema directly; upgrades have explicit sequential paths for v1→v2→v3→v4→v5.
2. Existing upgrade tests cover starting schema versions 1, 2, 3, and 4 reaching schema v5. The current v4→v5 test checks the added archive and expense/service-link columns.
3. Legacy migration captures all five known SharedPreferences source keys (four record collections plus the seed marker), including key-presence and stored-type information, before attempting SQLite import.
4. The raw legacy backup is versioned (`maintainly.legacy-shared-preferences-backup`, format version 1), stored under `maintainly.legacy.backup.v1`, and verified by reading the exact value back after writing.
5. The migrator persists the backup before import, checks source integrity, performs the SQLite import and migration-ledger insert in one transaction, verifies row counts, and retains the original SharedPreferences source keys.
6. The repository's SQLite whole-snapshot save uses a database transaction, validates the snapshot first, and replaces dependent/parent rows in a controlled order. A failed SQLite transaction should roll back its row changes.

#### Gaps to address in Step 8

1. The existing legacy backup is an internal migration-recovery snapshot, not a user-selectable/exportable backup file.
2. It captures legacy SharedPreferences raw values; it does not represent the complete current SQLite-backed application snapshot in a user-facing portable backup format.
3. There is no user-facing JSON export or restore flow.
4. Existing schema upgrade tests verify version progression and selected columns, but a populated old-version database should also be tested to prove existing rows and values survive upgrades and receive safe defaults for newly added columns.
5. Restore must not directly overwrite current data until the complete backup has been parsed, version-checked, model-validated, and relationship-validated. It must preserve the current data if the restore transaction fails.
6. Restore/export must preserve Step 7 fields: `Vehicle.isArchived`, `VehicleExpense.sourceServiceId`, and `MaintenanceReminder.sourceServiceId`.

#### Agreed implementation sequence

- **Substep 8.2:** Define and test a versioned full-app JSON backup format covering vehicles, services, expenses, and reminders, including Step 7 relationship/archive fields.
- **Substep 8.3:** Add user-accessible JSON export and file selection/import plumbing suitable for the supported Android and Web targets; package/platform behaviour has been checked against the package documentation.
- **Substep 8.4:** Add strict backup parsing and validation, explicit restore confirmation, pre-restore recovery protection, and atomic SQLite restore with rollback on failure. Refuse destructive restore while SQLite migration is incomplete or SQLite is unavailable; the non-transactional legacy fallback remains available for ordinary saves only.
- **Substep 8.5:** Add focused automated tests for format compatibility, malformed/unsupported backups, duplicate IDs, missing vehicle/service references, archive/link-field preservation, successful restore, and rollback/recovery. Update user documentation.

#### Verification boundary

- Static source review completed for the files listed above.
- No Dart/Flutter code was changed in Substep 8.1; no formatter, analyzer, or test pass is claimed for this review-only substep.
- The user's deferred Chrome database test remains unverified and is scheduled for Step 9 platform verification.
- Full manual testing remains deferred until Step 10, as requested.

### Substep 8.2 — Versioned full-app JSON backup format

- **Status:** Implementation and focused tests added; user verified the focused suite (7/7) and full suite (81 passed, 1 skipped).
- Added `lib/data/backup/maintainly_backup.dart` with the portable `maintainly.full-backup` format, version 1.
- The format includes creation timestamp metadata and all four current collections: vehicles, services, expenses, and reminders.
- Serialization preserves Step 7 fields, including vehicle archive state, expense-to-service links, and reminder-to-service links.
- Decoder rejects malformed JSON, wrong format identifiers, unsupported versions, missing or incorrectly typed required fields, invalid dates/numbers, duplicate IDs, missing vehicle references, invalid service links, and linked expense totals that exceed the source service cost.
- Validation reuses `MaintainlyDataValidator` for numeric and expense/service consistency rules, and adds backup-level vehicle/service/reminder relationship checks.
- Added `test/data/backup/maintainly_backup_test.dart` for round-trip fidelity, empty snapshots, malformed/unsupported backups, required-field validation, duplicate IDs, missing vehicle references, invalid links, and linked-expense limits.
- No database schema, repository write path, UI, or file-picker dependency changed in this substep. Export/import file handling and actual restore remain for Substeps 8.3–8.4.
- `dart format` and `flutter analyze` have not been run in this environment. The user reported `flutter test test/data/backup/maintainly_backup_test.dart` passed 7/7 and the full suite completed with 81 passed and 1 skipped. The skipped test is the deferred Chrome database test.

### Substep 8.3 — Cross-platform JSON file export and selection

- **Status:** Implementation prepared; user-side dependency resolution and test verification pending.
- Added `file_picker: ^13.3.3` to `pubspec.yaml`. The package documentation lists Android and Web support for both `pickFile()` and `saveFile()`.
- Added `lib/data/backup/maintainly_backup_file_service.dart` to export a versioned backup as UTF-8 JSON and let the user select a `.json` file. The service is dependency-injectable for tests.
- Added an app-bar Backup menu with **Export JSON backup** and **Select backup file** actions. Selecting a file decodes and validates it using `MaintainlyBackup.decode`, then displays record counts. It explicitly tells the user that current app data has not been changed; actual restore is reserved for Substep 8.4.
- Added `test/data/backup/maintainly_backup_file_service_test.dart` covering export bytes/name/MIME type, export cancellation, file selection, import cancellation, non-JSON extension rejection, and invalid UTF-8.
- Modified: `pubspec.yaml`, `lib/app.dart`. Added: `lib/data/backup/maintainly_backup_file_service.dart`, `test/data/backup/maintainly_backup_file_service_test.dart`.
- `pubspec.lock` has not been regenerated in this environment. Run `flutter pub get` before testing this substep.
- No database schema, repository persistence path, or live app data is changed by file selection. File parsing is validated before the restore feature is introduced.
- `dart format`, `flutter analyze`, and Flutter tests have not been run in this environment.

**Next:** Step 8 Substep 8.4 — add explicit restore confirmation, preserve a pre-restore recovery snapshot, and replace the complete SQLite snapshot atomically with rollback on failure.

### Substep 8.4 — Confirmed JSON restore and recovery protection

- **Status:** Implementation and focused repository tests added; user-side verification pending.
- Added `MaintainlyRepository.restore()` as a dedicated destructive-restore path. It validates the complete four-collection snapshot and only proceeds when the repository has confirmed the SQLite migration ledger and SQLite is available.
- Restore is deliberately blocked when migration is incomplete or SQLite is unavailable. The legacy SharedPreferences implementation writes four collection keys separately and cannot guarantee an atomic replacement; the app therefore refuses restore rather than risk a partial overwrite in that mode. Existing non-destructive legacy save behaviour is unchanged.
- Reuses the existing SQLite transaction to replace vehicles, services, expenses, and reminders together, verifies collection counts, and updates the migration ledger in the same transaction. A failed insert/constraint should roll back the entire restore.
- Handles the SQLite-read fallback marker around the transaction so a failed restore returns to the previously active source; successful restore makes SQLite authoritative.
- Added `MaintainlyController.restoreData()`. It updates the in-memory collections and notifies the UI only after the repository confirms the database commit.
- Updated the **Select backup file** action: after strict JSON/model/relationship validation, the app displays record counts and asks for explicit confirmation that all current records will be replaced. Before applying the selected backup, it requires the user to save a separate JSON recovery copy of the current data. Cancelling that save cancels restore without changing app data.
- Added focused repository tests for successful complete restore, transaction rollback with fallback-marker preservation, and refusal when SQLite migration is not complete.
- Modified: `lib/data/repositories/maintainly_repository.dart`, `lib/application/maintainly_controller.dart`, `lib/application/providers.dart`, `lib/app.dart`, `test/data/repositories/maintainly_repository_sqlite_read_test.dart`.
- Modified this progress log. No schema change or new dependency was introduced.
- `dart format`, `flutter analyze`, and Flutter tests have not been run in this environment. Do not treat this implementation as verified until the user runs the commands below.

#### Suggested verification for Substep 8.4

Run from the project root in PowerShell:

```powershell
dart format lib/data/repositories/maintainly_repository.dart lib/application/maintainly_controller.dart lib/application/providers.dart lib/app.dart test/data/repositories/maintainly_repository_sqlite_read_test.dart
flutter analyze
flutter test test/data/repositories/maintainly_repository_sqlite_read_test.dart
flutter test test/data/backup/maintainly_backup_test.dart
flutter test test/data/backup/maintainly_backup_file_service_test.dart
flutter test
```

**Next:** Step 8 Substep 8.5 — user verification, any narrowly scoped fixes, and documentation/backup-restore regression coverage before closing Step 8.
