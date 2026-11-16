class VehicleExpense {
  const VehicleExpense({
    required this.id,
    required this.vehicleId,
    required this.category,
    required this.description,
    required this.date,
    required this.amount,
    required this.odometer,
    this.sourceServiceId,
  });

  final String id;
  final String vehicleId;
  final String category;
  final String description;
  final DateTime date;
  final double amount;
  final int odometer;
  final String? sourceServiceId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'category': category,
    'description': description,
    'date': date.toIso8601String(),
    'amount': amount,
    'odometer': odometer,
    'sourceServiceId': sourceServiceId,
  };

  factory VehicleExpense.fromJson(Map<String, dynamic> json) => VehicleExpense(
    id: json['id'] as String,
    vehicleId: json['vehicleId'] as String,
    category: json['category'] as String? ?? 'Other',
    description: json['description'] as String? ?? '',
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    odometer: (json['odometer'] as num?)?.toInt() ?? 0,
    sourceServiceId: json['sourceServiceId'] as String?,
  );
}
