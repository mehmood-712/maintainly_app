import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'maintainly_backup.dart';

typedef SaveBackupFile = Future<Uri?> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
});

typedef PickBackupFile = Future<PickedBackupFile?> Function();

/// A selected backup file whose bytes are read only after the user picks it.
class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.readBytes});

  final String name;
  final Future<Uint8List> Function() readBytes;
}

/// Cross-platform JSON file handling for Android and Web.
///
/// Parsing and restoring are intentionally separate: callers must validate the
/// returned JSON with [MaintainlyBackup.decode] before changing app data.
class MaintainlyBackupFileService {
  MaintainlyBackupFileService({
    SaveBackupFile? saveFile,
    PickBackupFile? pickFile,
  }) : _saveFile = saveFile ?? _saveWithFilePicker,
       _pickFile = pickFile ?? _pickWithFilePicker;

  static const String jsonMimeType = 'application/json';

  final SaveBackupFile _saveFile;
  final PickBackupFile _pickFile;

  /// Opens the platform save flow and returns false if the user cancels.
  Future<bool> exportBackup(MaintainlyBackup backup) async {
    final bytes = Uint8List.fromList(utf8.encode(backup.encode()));
    final result = await _saveFile(
      fileName: _fileName(backup.createdAtUtc),
      bytes: bytes,
      mimeType: jsonMimeType,
    );
    return result != null;
  }

  /// Lets the user select a .json file and returns its UTF-8 contents.
  /// Returns null when the user cancels. This method does not restore data.
  Future<String?> selectBackupJson() async {
    final selected = await _pickFile();
    if (selected == null) return null;

    if (!selected.name.toLowerCase().endsWith('.json')) {
      throw const FormatException(
        'Please select a Maintainly .json backup file.',
      );
    }

    final bytes = await selected.readBytes();
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('Backup file must contain valid UTF-8 text.');
    }
  }

  static String _fileName(DateTime createdAt) {
    final timestamp = createdAt.toUtc().toIso8601String();
    final compact = timestamp
        .replaceAll('-', '')
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('T', '-')
        .replaceAll('Z', '');
    return 'maintainly-backup-$compact.json';
  }

  static Future<Uri?> _saveWithFilePicker({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    return FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  static Future<PickedBackupFile?> _pickWithFilePicker() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    return PickedBackupFile(name: file.name, readBytes: file.readAsBytes);
  }
}
