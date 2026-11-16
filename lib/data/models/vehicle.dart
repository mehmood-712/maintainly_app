class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.type,
    required this.make,
    required this.model,
    required this.year,
    required this.registration,
    required this.odometer,
    required this.purchaseDate,
    required this.purchasePrice,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final String type;
  final String make;
  final String model;
  final int year;
  final String registration;
  final int odometer;
  final DateTime? purchaseDate;
  final double purchasePrice;
  final bool isArchived;

  Vehicle copyWith({
    String? name,
    String? type,
    String? make,
    String? model,
    int? year,
    String? registration,
    int? odometer,
    DateTime? purchaseDate,
    double? purchasePrice,
    bool? isArchived,
  }) => Vehicle(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    make: make ?? this.make,
    model: model ?? this.model,
    year: year ?? this.year,
    registration: registration ?? this.registration,
    odometer: odometer ?? this.odometer,
    purchaseDate: purchaseDate ?? this.purchaseDate,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    isArchived: isArchived ?? this.isArchived,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'make': make,
    'model': model,
    'year': year,
    'registration': registration,
    'odometer': odometer,
    'purchaseDate': purchaseDate?.toIso8601String(),
    'purchasePrice': purchasePrice,
    'isArchived': isArchived,
  };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled vehicle',
    type: json['type'] as String? ?? 'Car',
    make: json['make'] as String? ?? '',
    model: json['model'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
    registration: json['registration'] as String? ?? '',
    odometer: (json['odometer'] as num?)?.toInt() ?? 0,
    purchaseDate: DateTime.tryParse(json['purchaseDate'] as String? ?? ''),
    purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0,
    isArchived: json['isArchived'] as bool? ?? false,
  );
}
