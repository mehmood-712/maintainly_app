import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> create() async =>
      LocalStore(await SharedPreferences.getInstance());

  String? read(String key) => _prefs.getString(key);

  /// Returns the stored value without assuming that it has the expected type.
  ///
  /// Legacy-data inspection uses this method to detect a key whose value was
  /// written with an unexpected SharedPreferences type, rather than throwing
  /// while calling [read]. The returned value is never modified.
  Object? readRaw(String key) => _prefs.get(key);

  /// Whether a key exists, including keys whose stored value is empty.
  bool containsKey(String key) => _prefs.containsKey(key);

  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  /// Writes a string and confirms that SharedPreferences accepted and can
  /// read it back. Used for migration backups that must exist before import.
  Future<void> writeVerified(String key, String value) async {
    final accepted = await _prefs.setString(key, value);
    if (!accepted || _prefs.getString(key) != value) {
      throw StateError('Could not verify SharedPreferences write for "$key".');
    }
  }

  bool readBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> writeBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }
}
