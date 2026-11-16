import 'dart:convert';

import '../../core/data/legacy_storage_keys.dart';
import '../../core/data/local_store.dart';

enum LegacyValueStatus {
  missing,
  empty,
  valid,
  partiallyValid,
  malformed,
  invalidType,
}

enum LegacyIssueSeverity { warning, error }

class LegacyDataIssue {
  const LegacyDataIssue({
    required this.key,
    required this.message,
    this.recordIndex,
    this.severity = LegacyIssueSeverity.error,
  });

  final String key;
  final String message;
  final int? recordIndex;
  final LegacyIssueSeverity severity;

  Map<String, Object?> toJson() => {
    'key': key,
    'recordIndex': recordIndex,
    'severity': severity.name,
    'message': message,
  };
}

class LegacyCollectionInspection {
  const LegacyCollectionInspection({
    required this.key,
    required this.status,
    required this.keyExists,
    required this.rawValue,
    required this.recordCount,
    required this.validRecordCount,
    required this.invalidRecordCount,
    required this.recordIds,
    required this.vehicleIds,
    required this.issues,
  });

  final String key;
  final LegacyValueStatus status;
  final bool keyExists;

  /// Exact original SharedPreferences value. It is retained for recovery and
  /// is never normalized or written back by the inspector.
  final Object? rawValue;

  final int recordCount;
  final int validRecordCount;
  final int invalidRecordCount;
  final List<String> recordIds;
  final List<String> vehicleIds;
  final List<LegacyDataIssue> issues;

  bool get hasData => recordCount > 0;
  bool get hasErrors =>
      issues.any((issue) => issue.severity == LegacyIssueSeverity.error);

  Map<String, Object?> toJson({bool includeRawValue = false}) => {
    'key': key,
    'status': status.name,
    'keyExists': keyExists,
    'recordCount': recordCount,
    'validRecordCount': validRecordCount,
    'invalidRecordCount': invalidRecordCount,
    'recordIds': recordIds,
    'vehicleIds': vehicleIds,
    'issues': issues.map((issue) => issue.toJson()).toList(),
    if (includeRawValue) 'rawValue': rawValue,
  };
}

class LegacySeedMarkerInspection {
  const LegacySeedMarkerInspection({
    required this.keyExists,
    required this.rawValue,
    required this.status,
    required this.isMarkedSeeded,
  });

  final bool keyExists;
  final Object? rawValue;
  final LegacyValueStatus status;
  final bool isMarkedSeeded;

  Map<String, Object?> toJson({bool includeRawValue = false}) => {
    'key': LegacyStorageKeys.seeded,
    'keyExists': keyExists,
    'status': status.name,
    'isMarkedSeeded': isMarkedSeeded,
    if (includeRawValue) 'rawValue': rawValue,
  };
}

class LegacyDataInspectionReport {
  const LegacyDataInspectionReport({
    required this.inspectedAtUtc,
    required this.collections,
    required this.seedMarker,
    required this.issues,
    required this.sampleDataOverwriteRisk,
  });

  final DateTime inspectedAtUtc;
  final Map<String, LegacyCollectionInspection> collections;
  final LegacySeedMarkerInspection seedMarker;
  final List<LegacyDataIssue> issues;

  /// True when the old seeding condition would have overwritten existing
  /// record keys because the marker was not exactly "yes". Step 3 adds a
  /// repository guard, but the condition still requires review for migration.
  final bool sampleDataOverwriteRisk;

  int get totalRecordCount =>
      collections.values.fold(0, (sum, item) => sum + item.recordCount);

  int get validRecordCount =>
      collections.values.fold(0, (sum, item) => sum + item.validRecordCount);

  int get invalidRecordCount =>
      collections.values.fold(0, (sum, item) => sum + item.invalidRecordCount);

  bool get hasErrors =>
      issues.any((issue) => issue.severity == LegacyIssueSeverity.error) ||
      collections.values.any((item) => item.hasErrors);

  bool get hasWarnings =>
      issues.any((issue) => issue.severity == LegacyIssueSeverity.warning) ||
      collections.values.any(
        (item) => item.issues.any(
          (issue) => issue.severity == LegacyIssueSeverity.warning,
        ),
      );

  /// A conservative readiness check for a future migration. A report with
  /// malformed records, defaulted/missing fields, duplicate IDs, orphaned
  /// vehicle references, or a first-launch overwrite risk needs review first.
  bool get isReadyForMigration =>
      !hasErrors && !hasWarnings && !sampleDataOverwriteRisk;

  /// True for data problems that make rewriting the four legacy collections
  /// unsafe. Seed-marker issues are excluded because a successful complete
  /// save can repair the marker after all four collections have been written.
  bool get hasDataIntegrityErrors =>
      collections.values.any((item) => item.hasErrors) ||
      issues.any(
        (issue) =>
            issue.severity == LegacyIssueSeverity.error &&
            issue.key != LegacyStorageKeys.seeded,
      );

  /// True when one or more record collections contain errors or warnings.
  /// A warning means the existing JSON parser would synthesize a default, so
  /// a normal save could normalize and replace the original raw representation.
  bool get hasUnsafeLegacyCollections =>
      hasDataIntegrityErrors ||
      collections.values.any((item) => item.issues.isNotEmpty);

  Map<String, Object?> toJson({bool includeRawValues = false}) => {
    'reportFormatVersion': 1,
    'inspectedAtUtc': inspectedAtUtc.toIso8601String(),
    'summary': {
      'totalRecords': totalRecordCount,
      'validRecords': validRecordCount,
      'invalidRecords': invalidRecordCount,
      'hasErrors': hasErrors,
      'hasWarnings': hasWarnings,
      'sampleDataOverwriteRisk': sampleDataOverwriteRisk,
      'readyForMigration': isReadyForMigration,
    },
    'seedMarker': seedMarker.toJson(includeRawValue: includeRawValues),
    'collections': {
      for (final entry in collections.entries)
        entry.key: entry.value.toJson(includeRawValue: includeRawValues),
    },
    'issues': issues.map((issue) => issue.toJson()).toList(),
  };
}

/// Read-only inspection of the legacy SharedPreferences JSON snapshot.
///
/// This class does not modify any preferences, seed flags, or SQLite tables.
class LegacyDataInspector {
  const LegacyDataInspector(this._store);

  final LocalStore _store;

  LegacyDataInspectionReport inspect({DateTime? inspectedAt}) {
    final collections = <String, LegacyCollectionInspection>{
      LegacyStorageKeys.vehicles: _inspectCollection(
        LegacyStorageKeys.vehicles,
        _validateVehicle,
      ),
      LegacyStorageKeys.services: _inspectCollection(
        LegacyStorageKeys.services,
        _validateService,
      ),
      LegacyStorageKeys.expenses: _inspectCollection(
        LegacyStorageKeys.expenses,
        _validateExpense,
      ),
      LegacyStorageKeys.reminders: _inspectCollection(
        LegacyStorageKeys.reminders,
        _validateReminder,
      ),
    };

    final globalIssues = <LegacyDataIssue>[];
    _checkDuplicateIds(collections, globalIssues);
    _checkVehicleReferences(collections, globalIssues);

    final seedMarker = _inspectSeedMarker();
    final anyCollectionKeyExists = collections.values.any(
      (collection) => collection.keyExists,
    );
    final overwriteRisk = !seedMarker.isMarkedSeeded && anyCollectionKeyExists;

    if (overwriteRisk) {
      globalIssues.add(
        const LegacyDataIssue(
          key: LegacyStorageKeys.seeded,
          message:
              'The seed marker is not "yes" while one or more legacy record keys exist. '
              'The pre-Step-3 seeding logic would have saved sample data over these keys. The current repository guard now prevents that overwrite.',
        ),
      );
    }

    if (seedMarker.status == LegacyValueStatus.invalidType) {
      globalIssues.add(
        const LegacyDataIssue(
          key: LegacyStorageKeys.seeded,
          message:
              'The seed marker is stored with a non-string SharedPreferences type. '
              'The current repository reads this marker as a string and may fail during initialization.',
        ),
      );
    } else if (seedMarker.keyExists && !seedMarker.isMarkedSeeded) {
      globalIssues.add(
        const LegacyDataIssue(
          key: LegacyStorageKeys.seeded,
          message:
              'The seed marker exists but is not the expected string "yes". '
              'Its original value has been preserved for review.',
          severity: LegacyIssueSeverity.warning,
        ),
      );
    }

    return LegacyDataInspectionReport(
      inspectedAtUtc: (inspectedAt ?? DateTime.now()).toUtc(),
      collections: collections,
      seedMarker: seedMarker,
      issues: globalIssues,
      sampleDataOverwriteRisk: overwriteRisk,
    );
  }

  /// Captures the raw values of all five known keys in a portable JSON string.
  ///
  /// The snapshot is returned to the caller; this method does not write a
  /// file, alter preferences, or mark migration as complete. String values
  /// are stored verbatim in the JSON payload, including malformed JSON text.
  LegacyBackupSnapshot createBackupSnapshot({DateTime? createdAt}) {
    final entries = <String, LegacyBackupEntry>{};
    for (final key in LegacyStorageKeys.all) {
      final exists = _store.containsKey(key);
      final value = exists
          ? _cloneSupportedPreferenceValue(_store.readRaw(key))
          : null;
      entries[key] = LegacyBackupEntry(
        keyExists: exists,
        valueType: exists ? _valueTypeName(value) : 'missing',
        value: value,
      );
    }
    return LegacyBackupSnapshot(
      createdAtUtc: (createdAt ?? DateTime.now()).toUtc(),
      entries: entries,
    );
  }

  LegacyCollectionInspection _inspectCollection(
    String key,
    _RecordValidation Function(Map<String, dynamic>) validate,
  ) {
    final exists = _store.containsKey(key);
    final raw = exists ? _store.readRaw(key) : null;

    if (!exists) {
      return _collection(
        key: key,
        status: LegacyValueStatus.missing,
        keyExists: false,
        rawValue: null,
      );
    }

    if (raw is! String) {
      return _collection(
        key: key,
        status: LegacyValueStatus.invalidType,
        keyExists: true,
        rawValue: _cloneSupportedPreferenceValue(raw),
        issues: [
          LegacyDataIssue(
            key: key,
            message: 'Expected a JSON string but found ${_valueTypeName(raw)}.',
          ),
        ],
      );
    }

    if (raw.trim().isEmpty) {
      return _collection(
        key: key,
        status: LegacyValueStatus.empty,
        keyExists: true,
        rawValue: raw,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      return _collection(
        key: key,
        status: LegacyValueStatus.malformed,
        keyExists: true,
        rawValue: raw,
        issues: [
          LegacyDataIssue(key: key, message: 'Invalid JSON: ${error.message}'),
        ],
      );
    }

    if (decoded is! List) {
      return _collection(
        key: key,
        status: LegacyValueStatus.malformed,
        keyExists: true,
        rawValue: raw,
        issues: [
          LegacyDataIssue(
            key: key,
            message: 'Expected a JSON array but found ${decoded.runtimeType}.',
          ),
        ],
      );
    }

    if (decoded.isEmpty) {
      return _collection(
        key: key,
        status: LegacyValueStatus.empty,
        keyExists: true,
        rawValue: raw,
      );
    }

    final issues = <LegacyDataIssue>[];
    final ids = <String>[];
    final vehicleIds = <String>[];
    var validCount = 0;
    var invalidCount = 0;

    for (var index = 0; index < decoded.length; index++) {
      final item = decoded[index];
      if (item is! Map) {
        invalidCount++;
        issues.add(
          LegacyDataIssue(
            key: key,
            recordIndex: index,
            message: 'Record must be a JSON object.',
          ),
        );
        continue;
      }

      Map<String, dynamic> record;
      try {
        record = Map<String, dynamic>.from(item);
      } on TypeError {
        invalidCount++;
        issues.add(
          LegacyDataIssue(
            key: key,
            recordIndex: index,
            message: 'Record contains a non-string JSON field name.',
          ),
        );
        continue;
      }

      final validation = validate(record);
      for (final message in validation.errors) {
        issues.add(
          LegacyDataIssue(key: key, recordIndex: index, message: message),
        );
      }
      for (final message in validation.warnings) {
        issues.add(
          LegacyDataIssue(
            key: key,
            recordIndex: index,
            message: message,
            severity: LegacyIssueSeverity.warning,
          ),
        );
      }

      if (validation.errors.isEmpty) {
        validCount++;
        if (validation.id != null) ids.add(validation.id!);
        if (validation.vehicleId != null) {
          vehicleIds.add(validation.vehicleId!);
        }
      } else {
        invalidCount++;
        if (validation.id != null) ids.add(validation.id!);
        if (validation.vehicleId != null) {
          vehicleIds.add(validation.vehicleId!);
        }
      }
    }

    final status = invalidCount == 0
        ? LegacyValueStatus.valid
        : validCount > 0
        ? LegacyValueStatus.partiallyValid
        : LegacyValueStatus.malformed;

    return _collection(
      key: key,
      status: status,
      keyExists: true,
      rawValue: raw,
      recordCount: decoded.length,
      validRecordCount: validCount,
      invalidRecordCount: invalidCount,
      recordIds: ids,
      vehicleIds: vehicleIds,
      issues: issues,
    );
  }

  LegacyCollectionInspection _collection({
    required String key,
    required LegacyValueStatus status,
    required bool keyExists,
    required Object? rawValue,
    int recordCount = 0,
    int validRecordCount = 0,
    int invalidRecordCount = 0,
    List<String> recordIds = const [],
    List<String> vehicleIds = const [],
    List<LegacyDataIssue> issues = const [],
  }) => LegacyCollectionInspection(
    key: key,
    status: status,
    keyExists: keyExists,
    rawValue: rawValue,
    recordCount: recordCount,
    validRecordCount: validRecordCount,
    invalidRecordCount: invalidRecordCount,
    recordIds: List.unmodifiable(recordIds),
    vehicleIds: List.unmodifiable(vehicleIds),
    issues: List.unmodifiable(issues),
  );

  LegacySeedMarkerInspection _inspectSeedMarker() {
    final exists = _store.containsKey(LegacyStorageKeys.seeded);
    final raw = exists ? _store.readRaw(LegacyStorageKeys.seeded) : null;
    if (!exists) {
      return const LegacySeedMarkerInspection(
        keyExists: false,
        rawValue: null,
        status: LegacyValueStatus.missing,
        isMarkedSeeded: false,
      );
    }
    if (raw is! String) {
      return LegacySeedMarkerInspection(
        keyExists: true,
        rawValue: _cloneSupportedPreferenceValue(raw),
        status: LegacyValueStatus.invalidType,
        isMarkedSeeded: false,
      );
    }
    if (raw == 'yes') {
      return LegacySeedMarkerInspection(
        keyExists: true,
        rawValue: raw,
        status: LegacyValueStatus.valid,
        isMarkedSeeded: true,
      );
    }
    if (raw.isEmpty) {
      return LegacySeedMarkerInspection(
        keyExists: true,
        rawValue: raw,
        status: LegacyValueStatus.empty,
        isMarkedSeeded: false,
      );
    }
    return LegacySeedMarkerInspection(
      keyExists: true,
      rawValue: raw,
      status: LegacyValueStatus.malformed,
      isMarkedSeeded: false,
    );
  }

  void _checkDuplicateIds(
    Map<String, LegacyCollectionInspection> collections,
    List<LegacyDataIssue> globalIssues,
  ) {
    for (final collection in collections.values) {
      final seen = <String>{};
      for (final id in collection.recordIds) {
        if (!seen.add(id)) {
          globalIssues.add(
            LegacyDataIssue(
              key: collection.key,
              message:
                  'Duplicate record ID "$id" was found in this collection.',
            ),
          );
        }
      }
    }
  }

  void _checkVehicleReferences(
    Map<String, LegacyCollectionInspection> collections,
    List<LegacyDataIssue> globalIssues,
  ) {
    final vehicleIds = collections[LegacyStorageKeys.vehicles]!.recordIds
        .toSet();
    for (final key in [
      LegacyStorageKeys.services,
      LegacyStorageKeys.expenses,
      LegacyStorageKeys.reminders,
    ]) {
      final collection = collections[key]!;
      for (final vehicleId in collection.vehicleIds) {
        if (!vehicleIds.contains(vehicleId)) {
          globalIssues.add(
            LegacyDataIssue(
              key: key,
              message:
                  'Record references vehicle "$vehicleId", but that vehicle ID is not present in the legacy vehicles collection.',
            ),
          );
        }
      }
    }
  }

  _RecordValidation _validateVehicle(Map<String, dynamic> value) {
    final result = _RecordValidation();
    result.id = _requiredString(value, 'id', result.errors);
    _optionalString(value, 'name', result.warnings, result.errors);
    _optionalString(value, 'type', result.warnings, result.errors);
    _optionalString(value, 'make', result.warnings, result.errors);
    _optionalString(value, 'model', result.warnings, result.errors);
    _optionalString(value, 'registration', result.warnings, result.errors);
    _optionalNumber(
      value,
      'year',
      result.warnings,
      result.errors,
      integer: true,
    );
    _optionalNumber(
      value,
      'odometer',
      result.warnings,
      result.errors,
      integer: true,
      nonNegative: true,
    );
    _optionalNumber(
      value,
      'purchasePrice',
      result.warnings,
      result.errors,
      nonNegative: true,
    );
    _optionalDate(value, 'purchaseDate', result.warnings, result.errors);
    if (value.containsKey('isArchived') && value['isArchived'] is! bool) {
      result.errors.add('Field "isArchived" must be a boolean.');
    }
    return result;
  }

  _RecordValidation _validateService(Map<String, dynamic> value) {
    final result = _RecordValidation();
    result.id = _requiredString(value, 'id', result.errors);
    result.vehicleId = _requiredString(value, 'vehicleId', result.errors);
    _optionalString(value, 'title', result.warnings, result.errors);
    _optionalString(value, 'category', result.warnings, result.errors);
    _requiredDate(value, 'date', result.errors);
    _optionalNumber(
      value,
      'odometer',
      result.warnings,
      result.errors,
      integer: true,
      nonNegative: true,
    );
    _optionalNumber(
      value,
      'cost',
      result.warnings,
      result.errors,
      nonNegative: true,
    );
    _optionalString(value, 'mechanic', result.warnings, result.errors);
    _optionalString(value, 'notes', result.warnings, result.errors);
    _optionalDate(value, 'nextDueDate', result.warnings, result.errors);
    _optionalNumber(
      value,
      'nextDueOdometer',
      result.warnings,
      result.errors,
      integer: true,
      nullable: true,
      nonNegative: true,
    );
    return result;
  }

  _RecordValidation _validateExpense(Map<String, dynamic> value) {
    final result = _RecordValidation();
    result.id = _requiredString(value, 'id', result.errors);
    result.vehicleId = _requiredString(value, 'vehicleId', result.errors);
    _optionalString(value, 'category', result.warnings, result.errors);
    _optionalString(value, 'description', result.warnings, result.errors);
    _requiredDate(value, 'date', result.errors);
    _optionalNumber(
      value,
      'amount',
      result.warnings,
      result.errors,
      nonNegative: true,
    );
    _optionalNumber(
      value,
      'odometer',
      result.warnings,
      result.errors,
      integer: true,
      nonNegative: true,
    );
    if (value.containsKey('sourceServiceId') &&
        value['sourceServiceId'] != null &&
        value['sourceServiceId'] is! String) {
      result.errors.add('Field "sourceServiceId" must be a string or NULL.');
    }
    return result;
  }

  _RecordValidation _validateReminder(Map<String, dynamic> value) {
    final result = _RecordValidation();
    result.id = _requiredString(value, 'id', result.errors);
    result.vehicleId = _requiredString(value, 'vehicleId', result.errors);
    _optionalString(value, 'title', result.warnings, result.errors);
    _optionalDate(value, 'dueDate', result.warnings, result.errors);
    _optionalNumber(
      value,
      'dueOdometer',
      result.warnings,
      result.errors,
      integer: true,
      nullable: true,
      nonNegative: true,
    );
    _optionalString(value, 'notes', result.warnings, result.errors);
    if (value.containsKey('sourceServiceId') &&
        value['sourceServiceId'] != null &&
        value['sourceServiceId'] is! String) {
      result.errors.add('Field "sourceServiceId" must be a string or NULL.');
    }
    final completed = value['completed'];
    if (!value.containsKey('completed') || completed == null) {
      result.warnings.add(
        'Missing/NULL "completed"; the current model parser defaults it to false.',
      );
    } else if (completed is! bool) {
      result.errors.add('Field "completed" must be a boolean or NULL.');
    }
    return result;
  }

  String? _requiredString(
    Map<String, dynamic> value,
    String field,
    List<String> errors,
  ) {
    final raw = value[field];
    if (raw is String && raw.trim().isNotEmpty) return raw;
    errors.add('Required field "$field" must be a non-empty string.');
    return null;
  }

  void _optionalString(
    Map<String, dynamic> value,
    String field,
    List<String> warnings,
    List<String> errors,
  ) {
    if (!value.containsKey(field)) {
      warnings.add(
        'Missing "$field"; the current model parser supplies a default.',
      );
      return;
    }
    if (value[field] == null) {
      warnings.add(
        'Field "$field" is NULL; the current model parser supplies a default.',
      );
      return;
    }
    if (value[field] is! String) {
      errors.add('Field "$field" must be a string or NULL.');
    }
  }

  void _requiredDate(
    Map<String, dynamic> value,
    String field,
    List<String> errors,
  ) {
    final raw = value[field];
    if (raw is String && DateTime.tryParse(raw) != null) return;
    errors.add('Required date field "$field" must be a valid ISO-8601 string.');
  }

  void _optionalDate(
    Map<String, dynamic> value,
    String field,
    List<String> warnings,
    List<String> errors,
  ) {
    if (!value.containsKey(field)) {
      warnings.add(
        'Missing "$field"; the current model parser treats it as NULL.',
      );
      return;
    }
    final raw = value[field];
    if (raw == null) return;
    if (raw is String && DateTime.tryParse(raw) != null) return;
    errors.add('Field "$field" must be NULL or a valid ISO-8601 string.');
  }

  void _optionalNumber(
    Map<String, dynamic> value,
    String field,
    List<String> warnings,
    List<String> errors, {
    bool integer = false,
    bool nullable = false,
    bool nonNegative = false,
  }) {
    if (!value.containsKey(field)) {
      warnings.add(
        'Missing "$field"; the current model parser supplies a default.',
      );
      return;
    }
    final raw = value[field];
    if (raw == null && nullable) return;
    if (raw == null) {
      warnings.add(
        'Field "$field" is NULL; the current model parser supplies a default.',
      );
      return;
    }
    if (raw is! num || !raw.isFinite) {
      errors.add(
        'Field "$field" must be a finite number${nullable ? ' or NULL' : ''}.',
      );
      return;
    }
    if (integer && raw.toInt() != raw) {
      errors.add('Field "$field" must be an integer.');
      return;
    }
    if (nonNegative && raw < 0) {
      errors.add(
        'Field "$field" cannot be negative (the SQLite schema rejects it).',
      );
    }
  }

  static Object? _cloneSupportedPreferenceValue(Object? value) {
    if (value is List<String>) return List<String>.from(value);
    return value;
  }

  static String _valueTypeName(Object? value) {
    if (value == null) return 'null';
    if (value is String) return 'String';
    if (value is bool) return 'bool';
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is List<String>) return 'List<String>';
    return value.runtimeType.toString();
  }
}

class _RecordValidation {
  String? id;
  String? vehicleId;
  final List<String> warnings = [];
  final List<String> errors = [];
}

class LegacyBackupEntry {
  const LegacyBackupEntry({
    required this.keyExists,
    required this.valueType,
    required this.value,
  });

  final bool keyExists;
  final String valueType;
  final Object? value;

  Map<String, Object?> toJson() => {
    'keyExists': keyExists,
    'valueType': valueType,
    'value': value,
  };
}

/// Portable, versioned copy of the raw legacy SharedPreferences values.
///
/// This is a backup representation only. Restoring it is intentionally not
/// part of Step 3; restore validation and user confirmation are later work.
class LegacyBackupSnapshot {
  const LegacyBackupSnapshot({
    required this.createdAtUtc,
    required this.entries,
  });

  final DateTime createdAtUtc;
  final Map<String, LegacyBackupEntry> entries;

  Map<String, Object?> toJson() => {
    'format': 'maintainly.legacy-shared-preferences-backup',
    'formatVersion': 1,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'source': 'shared_preferences',
    'entries': {
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    },
  };

  String encode({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());
}
