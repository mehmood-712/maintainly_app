import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:maintainly/core/database/maintainly_database.dart';

void main() {
  late MaintainlyDatabase database;

  setUp(() {
    database = MaintainlyDatabase(
      databaseName: 'maintainly_step1_web_smoke_test',
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('opens Drift SQLite in the browser and enables foreign keys', () async {
    await database.open();

    expect(await database.sqliteVersion, isNotEmpty);
    expect(
      await database.currentSchemaVersion,
      MaintainlyDatabase.latestSchemaVersion,
    );
    expect(await database.foreignKeysEnabled, isTrue);
  }, skip: !kIsWeb);
}
