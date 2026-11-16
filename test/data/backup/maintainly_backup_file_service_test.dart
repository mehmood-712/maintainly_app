import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintainly/data/backup/maintainly_backup.dart';
import 'package:maintainly/data/backup/maintainly_backup_file_service.dart';
import 'package:maintainly/data/models/expense.dart';
import 'package:maintainly/data/models/maintenance_reminder.dart';
import 'package:maintainly/data/models/service_record.dart';
import 'package:maintainly/data/models/vehicle.dart';

void main() {
  final backup = MaintainlyBackup(
    createdAtUtc: DateTime.utc(2026, 11, 16, 12, 30),
    vehicles: [
      Vehicle(
        id: 'vehicle-1',
        name: 'Test car',
        type: 'Car',
        make: 'Toyota',
        model: 'Corolla',
        year: 2022,
        registration: 'ABC-123',
        odometer: 12000,
        purchaseDate: DateTime(2022, 1, 1),
        purchasePrice: 2500000,
        isArchived: false,
      ),
    ],
    services: [
      ServiceRecord(
        id: 'service-1',
        vehicleId: 'vehicle-1',
        title: 'Oil change',
        category: 'Maintenance',
        date: DateTime(2026, 10, 1),
        odometer: 11000,
        cost: 1000,
        mechanic: '',
        notes: '',
      ),
    ],
    expenses: [
      VehicleExpense(
        id: 'expense-1',
        vehicleId: 'vehicle-1',
        category: 'Parts',
        description: 'Filter',
        date: DateTime(2026, 10, 1),
        amount: 100,
        odometer: 11000,
        sourceServiceId: 'service-1',
      ),
    ],
    reminders: [
      MaintenanceReminder(
        id: 'reminder-1',
        vehicleId: 'vehicle-1',
        title: 'Next service',
        dueDate: null,
        dueOdometer: 16000,
        notes: '',
        completed: false,
        sourceServiceId: 'service-1',
      ),
    ],
  );

  test(
    'exports versioned JSON with the expected filename and MIME type',
    () async {
      String? savedName;
      String? savedMimeType;
      String? savedJson;

      final service = MaintainlyBackupFileService(
        saveFile: ({required fileName, required bytes, required mimeType}) async {
          savedName = fileName;
          savedMimeType = mimeType;
          savedJson = utf8.decode(bytes);
          return Uri(path: fileName);
        },
        pickFile: () async => null,
      );

      expect(await service.exportBackup(backup), isTrue);
      expect(savedName, 'maintainly-backup-20261116-123000000.json');
      expect(savedMimeType, 'application/json');
      expect(
        MaintainlyBackup.decode(savedJson!).vehicles.single.id,
        'vehicle-1',
      );
    },
  );

  test('reports export cancellation without claiming success', () async {
    final service = MaintainlyBackupFileService(
      saveFile: ({required fileName, required bytes, required mimeType}) async =>
          null,
      pickFile: () async => null,
    );

    expect(await service.exportBackup(backup), isFalse);
  });

  test('selects and reads a JSON backup without restoring it', () async {
    final json = backup.encode();
    final service = MaintainlyBackupFileService(
      saveFile: ({required fileName, required bytes, required mimeType}) async =>
          null,
      pickFile: () async => PickedBackupFile(
        name: 'my-maintainly-backup.json',
        readBytes: () async => Uint8List.fromList(utf8.encode(json)),
      ),
    );

    final selected = await service.selectBackupJson();
    expect(selected, json);
    expect(MaintainlyBackup.decode(selected!).services.single.id, 'service-1');
  });

  test('returns null when the user cancels backup selection', () async {
    final service = MaintainlyBackupFileService(
      saveFile: ({required fileName, required bytes, required mimeType}) async =>
          null,
      pickFile: () async => null,
    );

    expect(await service.selectBackupJson(), isNull);
  });

  test('rejects a selected file that does not have a JSON extension', () async {
    final service = MaintainlyBackupFileService(
      saveFile: ({required fileName, required bytes, required mimeType}) async =>
          null,
      pickFile: () async => PickedBackupFile(
        name: 'backup.txt',
        readBytes: () async => Uint8List.fromList(utf8.encode('{}')),
      ),
    );

    expect(service.selectBackupJson(), throwsA(isA<FormatException>()));
  });

  test('rejects invalid UTF-8 bytes', () async {
    final service = MaintainlyBackupFileService(
      saveFile: ({required fileName, required bytes, required mimeType}) async =>
          null,
      pickFile: () async => PickedBackupFile(
        name: 'backup.json',
        readBytes: () async => Uint8List.fromList([0xff, 0xfe]),
      ),
    );

    expect(service.selectBackupJson(), throwsA(isA<FormatException>()));
  });
}
