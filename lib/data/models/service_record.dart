class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.vehicleId,
    required this.title,
    required this.category,
    required this.date,
    required this.odometer,
    required this.cost,
    required this.mechanic,
    required this.notes,
    this.nextDueDate,
    this.nextDueOdometer,
  });

  final String id;
  final String vehicleId;
  final String title;
  final String category;
  final DateTime date;
  final int odometer;
  final double cost;
  final String mechanic;
  final String notes;
  final DateTime? nextDueDate;
  final int? nextDueOdometer;

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'title': title,
    'category': category,
    'date': date.toIso8601String(),
    'odometer': odometer,
    'cost': cost,
    'mechanic': mechanic,
    'notes': notes,
    'nextDueDate': nextDueDate?.toIso8601String(),
    'nextDueOdometer': nextDueOdometer,
  };

  factory ServiceRecord.fromJson(Map<String, dynamic> json) => ServiceRecord(
    id: json['id'] as String,
    vehicleId: json['vehicleId'] as String,
    title: json['title'] as String? ?? 'Service',
    category: json['category'] as String? ?? 'General',
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    odometer: (json['odometer'] as num?)?.toInt() ?? 0,
    cost: (json['cost'] as num?)?.toDouble() ?? 0,
    mechanic: json['mechanic'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    nextDueDate: DateTime.tryParse(json['nextDueDate'] as String? ?? ''),
    nextDueOdometer: (json['nextDueOdometer'] as num?)?.toInt(),
  );
}
