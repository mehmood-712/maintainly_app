🚗 Maintainly
Maintainly is a local-first Flutter application for managing vehicle information, maintenance records, reminders, and expenses. It is designed for individual vehicle owners and small fleets.

The app currently supports Android and Web. Vehicle records are stored locally on the device or in the browser profile.
✓ Features currently available
✓ 🚘 Vehicle management
- Add, view, edit, archive, and restore vehicles; archiving preserves all linked history.
- Keep vehicle details together in one garage.
✓ 🔧 Maintenance records
- Record a vehicle's service history.
- Save the service date, odometer reading, mechanic, cost, notes, and next-service information.
✓ ⏰ Maintenance reminders
- Create reminders based on a date, odometer reading, or both.
- View upcoming and overdue reminders inside the app.
✓ 💰 Expense tracking
- Record vehicle expenses under categories such as fuel, labour, parts, insurance, and other.
- Link itemized expenses to a service when their amount is already included in that service total; linked amounts remain visible but are not counted twice in dashboard/report totals.
✓ 📊 Dashboard and reports
- View fleet vehicle counts, expenses, and maintenance status.
- Generate and print or share a PDF fleet report.
✓ ⚙️ General app features
- Search and filter records on the main data screens.
- Switch between light and dark themes.
- Start with sample records on the first launch.
❗ Improvements needed
The items in this section are development goals. They are not included in the current build unless stated in the features section above.

Priority guide: ❗❗❗ Critical = essential for reliability; ❗❗ High = important for a complete user experience; ❗ Medium = valuable enhancement; no mark = optional or later-stage improvement.
❗❗❗ 💾 1. Data backup and restore
Users should be able to protect their maintenance history and move it to another device.
- Export all app records to a JSON backup file.
- Restore records from a backup after validating its format and contents.
- Explain whether a restore will replace or merge existing records, and ask for confirmation before making changes.
- Add CSV export for expenses and service history so users can analyse records in spreadsheet software.
❗❗❗ 🛠️ 2. More reliable maintenance scheduling
Maintenance can be due because of elapsed time, vehicle usage, or both. The reminder logic should handle these conditions consistently.
- Support service intervals based on months, kilometres, or a combination of both.
- When both date and mileage limits are set, mark the service as due as soon as either limit is reached.
- When a service is completed, close the related reminder and calculate the next due point when an interval is available.
- Prevent duplicate active reminders for the same maintenance task.
- Allow users to edit or snooze reminders without losing the original due information.
❗❗ 📏 3. Odometer validation
Odometer readings are used to calculate maintenance schedules, so incorrect readings can lead to incorrect reminders and reports.
- Reject negative readings and warn when a new reading is lower than the latest known reading.
- Allow users to correct an earlier mistake deliberately.
- Support historical service entries added out of order without corrupting the vehicle's latest odometer value.
- Keep the distance unit clear, such as kilometres or miles.
❗❗ 🧾 4. Further expense insights
- Add date-range and category filters to expense summaries.
- Show totals by vehicle and expense category.
❗ 🚙 5. Vehicle lifecycle extensions
- Current support includes reversible active/archived states.
- Consider separate inactive and sold states if user workflows require them.
- Add an explicit permanent-delete workflow only with clear confirmation and backup guidance.
❗❗ 🔔 6. Device notifications
Reminders are currently shown inside Maintainly. Android local notifications should make important due dates visible even when the app is closed.
- Notify users about upcoming, due, and overdue maintenance.
- Update or cancel scheduled notifications when a reminder is edited, completed, snoozed, or deleted.
- Avoid repeated notifications for the same reminder unless the user has chosen a repeat schedule.
❗ 📄 7. Vehicle documents and service evidence
Keep important vehicle information with its related records.
- Store details for insurance, registration, inspection, and other documents.
- Add expiry dates and reminders for documents that need renewal.
- Allow users to attach receipts or photos to service and expense records.
❗ ⛽ 8. Fuel tracking and cost insights
Add fuel records to help users understand vehicle usage and running costs.
- Record refuelling date, odometer reading, fuel quantity, and total price.
- Calculate fuel consumption and cost per kilometre when enough valid readings are available.
- Provide monthly, yearly, and custom date-range cost summaries.
- Make calculation assumptions clear, especially for partial fuel fills or missing readings.
❗❗ 🗄️ 9. Complete SQLite write-path and future sync
Maintainly now has a Drift/SQLite schema, a backup-first legacy JSON migration, and a SQLite-backed read path. The current transition still keeps writes on SharedPreferences until the SQLite CRUD write path is completed.
- Complete transactional SQLite create, update, and delete operations for vehicles, services, expenses, and reminders.
- Verify data consistency across app restarts before removing the legacy write fallback.
- Consider optional cloud backup and multi-device sync only after local database handling is reliable.
- If shared fleet access is introduced, add user roles and permissions rather than allowing unrestricted access to every record.
🚀 Getting started
🧰 Requirements
- Flutter 3.47.0 or later
- Dart 3.13.0 or later
- A working Flutter development environment
- Chrome for the Web version, or an Android device/emulator for Android
Check the Flutter installation:
flutter doctor
🌐 Run on Web
From the project root, run:
flutter pub get
flutter run -d chrome
📱 Run on Android
Generate the Android platform files once from the project root, then run the app on a connected device or emulator:
flutter create --platforms=android .
flutter pub get
flutter devices
flutter run -d <android-device-id>
Replace <android-device-id> with the identifier shown by flutter devices.
🗂️ Project structure
lib/
  application/       Riverpod controller and providers
  core/
    data/            SharedPreferences storage and legacy keys
    database/        Versioned Drift/SQLite schema and initialization
    theme/           Light and dark application themes
    utils/           Formatting helpers
  data/
    models/          Vehicle, service, expense, and reminder models
    mappers/         Domain-model and SQLite row mapping
    migration/       Legacy inspection and transactional import
    repositories/    Local data repository and SQLite read path
    remote/          Reserved for a future remote data layer
    datasources/     Data-source boundary placeholder
  presentation/
    dialogs/         Create and edit forms
    screens/         Dashboard, vehicles, maintenance, expenses, reports
    widgets/         Reusable UI components
⚙️ Technologies
- Flutter: shared Android and Web application UI.
- Riverpod: application state, controllers, and providers.
- shared_preferences: legacy JSON storage and recovery fallback during the SQLite transition.
- Drift and drift_flutter: local SQLite database, migration, and repository read path.
- pdf: PDF report generation.
- printing: platform print and share flow for generated reports.
💽 Data storage and limitations
Maintainly uses local storage and does not connect to a backend, API, Firebase, or Supabase. During the SQLite transition:
- SharedPreferences retains the original JSON records and serves as the recovery/compatibility fallback.
- On startup, Maintainly creates a verified backup and automatically migrates valid legacy records to Drift/SQLite when the database is available.
- After a successful migration, repository reads use SQLite and verify the imported row counts against the migration ledger.
- If migration is blocked or SQLite cannot initialize, the app continues using the preserved SharedPreferences records.
- Writes remain on the legacy SharedPreferences path until the next SQLite write-integration step; a fallback marker prevents newer JSON saves from being hidden by an older SQLite snapshot.
- Clearing browser site data or uninstalling the app may remove locally stored records.
- The current build displays reminders inside the app. It does not register operating-system notification services.
The PDF report is intended for viewing, printing, or sharing. It is not a restorable data backup. A complete backup and restore feature is listed under Planned improvements