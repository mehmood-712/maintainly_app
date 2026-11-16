class MaintenanceReminder {
  const MaintenanceReminder({
    required this.id,
    required this.vehicleId,
    required this.title,
    required this.dueDate,
    required this.dueOdometer,
    required this.notes,
    required this.completed,
    this.sourceServiceId,
  });

  final String id;
  final String vehicleId;
  final String title;
  final DateTime? dueDate;
  final int? dueOdometer;
  final String notes;
  final bool completed;
  final String? sourceServiceId;

  MaintenanceReminder copyWith({
    String? vehicleId,
    String? title,
    DateTime? dueDate,
    int? dueOdometer,
    String? notes,
    bool? completed,
    String? sourceServiceId,
  }) => MaintenanceReminder(
    id: id,
    vehicleId: vehicleId ?? this.vehicleId,
    title: title ?? this.title,
    dueDate: dueDate ?? this.dueDate,
    dueOdometer: dueOdometer ?? this.dueOdometer,
    notes: notes ?? this.notes,
    completed: completed ?? this.completed,
    sourceServiceId: sourceServiceId ?? this.sourceServiceId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'title': title,
    'dueDate': dueDate?.toIso8601String(),
    'dueOdometer': dueOdometer,
    'notes': notes,
    'completed': completed,
    'sourceServiceId': sourceServiceId,
  };

  factory MaintenanceReminder.fromJson(Map<String, dynamic> json) =>
      MaintenanceReminder(
        id: json['id'] as String,
        vehicleId: json['vehicleId'] as String,
        title: json['title'] as String? ?? 'Maintenance',
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
        dueOdometer: (json['dueOdometer'] as num?)?.toInt(),
        notes: json['notes'] as String? ?? '',
        completed: json['completed'] as bool? ?? false,
        sourceServiceId: json['sourceServiceId'] as String?,
      );
}
