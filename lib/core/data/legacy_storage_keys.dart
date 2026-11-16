/// SharedPreferences keys used by Maintainly's pre-SQLite JSON store.
///
/// Keep the legacy source names stable. The backup key is separate from the
/// legacy source keys and is deliberately excluded from [collections] and
/// [all], so backup snapshots never recursively include themselves.
abstract final class LegacyStorageKeys {
  static const vehicles = 'maintainly.vehicles';
  static const services = 'maintainly.services';
  static const expenses = 'maintainly.expenses';
  static const reminders = 'maintainly.reminders';
  static const seeded = 'maintainly.seeded';

  /// Durable copy of the exact legacy values, written before SQLite import.
  static const migrationBackup = 'maintainly.legacy.backup.v1';

  static const collections = <String>[vehicles, services, expenses, reminders];

  static const all = <String>[...collections, seeded];
}
