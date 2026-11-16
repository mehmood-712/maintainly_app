import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../application/maintainly_controller.dart';
import '../../data/models/expense.dart';
import '../../data/models/maintenance_reminder.dart';
import '../../data/models/service_record.dart';
import '../../data/models/vehicle.dart';

final _uuid = Uuid();
const _vehicleTypes = ['Car', 'Motorcycle', 'Commercial', 'Other'];
const _serviceCategories = [
  'Oil change',
  'Repair',
  'Parts replacement',
  'Inspection',
  'Tyres',
  'General',
];
const _expenseCategories = [
  'Fuel',
  'Labour',
  'Parts',
  'Insurance',
  'Registration',
  'Other',
];

Future<DateTime?> _pickDate(BuildContext context, DateTime? current) =>
    showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );

String? _nonNegativeInteger(String? value) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null) return 'Enter a whole number';
  if (parsed < 0) return 'Must be zero or greater';
  return null;
}

String? _optionalNonNegativeInteger(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return _nonNegativeInteger(value);
}

String? _nonNegativeAmount(String? value) {
  final parsed = double.tryParse(value?.trim() ?? '');
  if (parsed == null || !parsed.isFinite) return 'Enter a valid amount';
  if (parsed < 0) return 'Must be zero or greater';
  return null;
}

class VehicleFormDialog extends StatefulWidget {
  const VehicleFormDialog({super.key, required this.controller, this.vehicle});
  final MaintainlyController controller;
  final Vehicle? vehicle;

  @override
  State<VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends State<VehicleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _registration;
  late final TextEditingController _odometer;
  late final TextEditingController _price;
  late String _type;
  DateTime? _purchaseDate;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _name = TextEditingController(text: v?.name ?? '');
    _make = TextEditingController(text: v?.make ?? '');
    _model = TextEditingController(text: v?.model ?? '');
    _year = TextEditingController(
      text: v?.year.toString() ?? DateTime.now().year.toString(),
    );
    _registration = TextEditingController(text: v?.registration ?? '');
    _odometer = TextEditingController(text: v?.odometer.toString() ?? '0');
    _price = TextEditingController(
      text: v?.purchasePrice.toStringAsFixed(0) ?? '0',
    );
    _type = v?.type ?? 'Car';
    _purchaseDate = v?.purchaseDate;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _make,
      _model,
      _year,
      _registration,
      _odometer,
      _price,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.vehicle == null ? 'Add vehicle' : 'Edit vehicle'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Vehicle nickname',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Vehicle type'),
                items: _vehicleTypes
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? 'Car'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _make,
                      decoration: const InputDecoration(labelText: 'Make'),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(labelText: 'Model'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Year'),
                      validator: (v) => int.tryParse(v ?? '') == null
                          ? 'Enter a valid year'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _registration,
                      decoration: const InputDecoration(
                        labelText: 'Registration',
                      ),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _odometer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Current odometer (km)',
                      ),
                      validator: _nonNegativeInteger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Purchase price (Rs)',
                      ),
                      validator: _nonNegativeAmount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Purchase date'),
                subtitle: Text(
                  _purchaseDate == null
                      ? 'Not set'
                      : '${_purchaseDate!.day}/${_purchaseDate!.month}/${_purchaseDate!.year}',
                ),
                trailing: IconButton(
                  onPressed: () async {
                    final date = await _pickDate(context, _purchaseDate);
                    if (date != null) setState(() => _purchaseDate = date);
                  },
                  icon: const Icon(Icons.calendar_month),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () async {
          if (!_formKey.currentState!.validate()) return;
          final old = widget.vehicle;
          await widget.controller.saveVehicle(
            Vehicle(
              id: old?.id ?? _uuid.v4(),
              name: _name.text.trim(),
              type: _type,
              make: _make.text.trim(),
              model: _model.text.trim(),
              year: int.parse(_year.text),
              registration: _registration.text.trim(),
              odometer: int.parse(_odometer.text),
              purchaseDate: _purchaseDate,
              purchasePrice: double.parse(_price.text),
            ),
          );
          if (context.mounted) Navigator.pop(context);
        },
        child: Text(widget.vehicle == null ? 'Add vehicle' : 'Save changes'),
      ),
    ],
  );
}

class ServiceFormDialog extends StatefulWidget {
  const ServiceFormDialog({
    super.key,
    required this.controller,
    this.vehicleId,
    this.record,
  });
  final MaintainlyController controller;
  final String? vehicleId;
  final ServiceRecord? record;
  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _odometer = TextEditingController();
  final _cost = TextEditingController(text: '0');
  final _mechanic = TextEditingController();
  final _notes = TextEditingController();
  final _nextOdometer = TextEditingController();
  String? _vehicleId;
  String _category = 'Oil change';
  DateTime _date = DateTime.now();
  DateTime? _nextDate;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _vehicleId =
        record?.vehicleId ??
        widget.vehicleId ??
        (widget.controller.activeVehicles.isNotEmpty
            ? widget.controller.activeVehicles.first.id
            : null);
    final vehicle = widget.controller.vehicleById(_vehicleId ?? '');
    _title.text = record?.title ?? '';
    _odometer.text =
        record?.odometer.toString() ?? vehicle?.odometer.toString() ?? '';
    _cost.text = record?.cost.toStringAsFixed(0) ?? '0';
    _mechanic.text = record?.mechanic ?? '';
    _notes.text = record?.notes ?? '';
    _nextOdometer.text = record?.nextDueOdometer?.toString() ?? '';
    _category = record?.category ?? 'Oil change';
    _date = record?.date ?? DateTime.now();
    _nextDate = record?.nextDueDate;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _odometer,
      _cost,
      _mechanic,
      _notes,
      _nextOdometer,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.record == null ? 'Add service record' : 'Edit service record',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _vehicleId,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items:
                    [
                          ...widget.controller.activeVehicles,
                          if (_vehicleId != null &&
                              widget.controller
                                      .vehicleById(_vehicleId!)
                                      ?.isArchived ==
                                  true)
                            widget.controller.vehicleById(_vehicleId!)!,
                        ]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.id,
                            child: Text('${v.name} · ${v.registration}'),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  setState(() {
                    _vehicleId = v;
                    _odometer.text =
                        widget.controller
                            .vehicleById(v ?? '')
                            ?.odometer
                            .toString() ??
                        '';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Service title'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _serviceCategories
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? 'General'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _odometer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Odometer (km)',
                      ),
                      validator: _nonNegativeInteger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Cost (Rs)'),
                      validator: _nonNegativeAmount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mechanic,
                decoration: const InputDecoration(
                  labelText: 'Mechanic / workshop',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const Divider(height: 26),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Next service reminder (optional)',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nextOdometer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Due odometer (km)',
                      ),
                      validator: _optionalNonNegativeInteger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await _pickDate(context, _nextDate);
                        if (d != null) setState(() => _nextDate = d);
                      },
                      icon: const Icon(Icons.event, size: 17),
                      label: Text(
                        _nextDate == null
                            ? 'Due date'
                            : '${_nextDate!.day}/${_nextDate!.month}/${_nextDate!.year}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Service date: ${_date.day}/${_date.month}/${_date.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final d = await _pickDate(context, _date);
                    if (d != null) setState(() => _date = d);
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: const Text('Change service date'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            (widget.controller.activeVehicles.isEmpty && widget.record == null)
            ? null
            : () async {
                if (!_formKey.currentState!.validate() || _vehicleId == null)
                  return;
                try {
                  await widget.controller.saveService(
                    ServiceRecord(
                      id: widget.record?.id ?? _uuid.v4(),
                      vehicleId: _vehicleId!,
                      title: _title.text.trim(),
                      category: _category,
                      date: _date,
                      odometer: int.parse(_odometer.text),
                      cost: double.parse(_cost.text),
                      mechanic: _mechanic.text.trim(),
                      notes: _notes.text.trim(),
                      nextDueDate: _nextDate,
                      nextDueOdometer: _nextOdometer.text.trim().isEmpty
                          ? null
                          : int.parse(_nextOdometer.text.trim()),
                    ),
                  );
                  if (context.mounted) Navigator.pop(context);
                } on ArgumentError catch (error) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          error.message?.toString() ??
                              'The service record is not valid.',
                        ),
                      ),
                    );
                }
              },
        child: Text(widget.record == null ? 'Save service' : 'Update service'),
      ),
    ],
  );
}

class ExpenseFormDialog extends StatefulWidget {
  const ExpenseFormDialog({super.key, required this.controller, this.expense});
  final MaintainlyController controller;
  final VehicleExpense? expense;
  @override
  State<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _odometer = TextEditingController(text: '0');
  String? _vehicleId;
  String _category = 'Fuel';
  DateTime _date = DateTime.now();
  String? _sourceServiceId;
  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _vehicleId =
        expense?.vehicleId ??
        (widget.controller.activeVehicles.isEmpty
            ? null
            : widget.controller.activeVehicles.first.id);
    _odometer.text =
        expense?.odometer.toString() ??
        widget.controller.vehicleById(_vehicleId ?? '')?.odometer.toString() ??
        '0';
    _description.text = expense?.description ?? '';
    _amount.text = expense?.amount.toStringAsFixed(0) ?? '';
    _category = expense?.category ?? 'Fuel';
    _date = expense?.date ?? DateTime.now();
    _sourceServiceId = expense?.sourceServiceId;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _odometer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.expense == null ? 'Add expense' : 'Edit expense'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _vehicleId,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items:
                    [
                          ...widget.controller.activeVehicles,
                          if (_vehicleId != null &&
                              widget.controller
                                      .vehicleById(_vehicleId!)
                                      ?.isArchived ==
                                  true)
                            widget.controller.vehicleById(_vehicleId!)!,
                        ]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(v.name),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() {
                  _vehicleId = v;
                  _sourceServiceId = null;
                  _odometer.text =
                      widget.controller
                          .vehicleById(v ?? '')
                          ?.odometer
                          .toString() ??
                      '0';
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _expenseCategories
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? 'Other'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount (Rs)',
                      ),
                      validator: _nonNegativeAmount,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _odometer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Odometer (km)',
                      ),
                      validator: _nonNegativeInteger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: _sourceServiceId,
                decoration: const InputDecoration(
                  labelText: 'Included in service cost? (optional)',
                ),
                hint: const Text('No — standalone expense'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No — standalone expense'),
                  ),
                  ...widget.controller.services
                      .where((service) => service.vehicleId == _vehicleId)
                      .map(
                        (service) => DropdownMenuItem<String?>(
                          value: service.id,
                          child: Text(
                            '${service.title} · ${service.date.day}/${service.date.month}/${service.date.year}',
                          ),
                        ),
                      ),
                ],
                onChanged: (value) => setState(() => _sourceServiceId = value),
              ),
              if (_sourceServiceId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'This amount remains visible in expense history but is not added again to overall spending.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await _pickDate(context, _date);
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text('Date: ${_date.day}/${_date.month}/${_date.year}'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            (widget.controller.activeVehicles.isEmpty && widget.expense == null)
            ? null
            : () async {
                if (!_formKey.currentState!.validate() || _vehicleId == null)
                  return;
                try {
                  await widget.controller.saveExpense(
                    VehicleExpense(
                      id: widget.expense?.id ?? _uuid.v4(),
                      vehicleId: _vehicleId!,
                      category: _category,
                      description: _description.text.trim(),
                      date: _date,
                      amount: double.parse(_amount.text),
                      odometer: int.parse(_odometer.text),
                      sourceServiceId: _sourceServiceId,
                    ),
                  );
                  if (context.mounted) Navigator.pop(context);
                } on ArgumentError catch (error) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          error.message?.toString() ??
                              'The expense record is not valid.',
                        ),
                      ),
                    );
                }
              },
        child: Text(widget.expense == null ? 'Save expense' : 'Update expense'),
      ),
    ],
  );
}

class ReminderFormDialog extends StatefulWidget {
  const ReminderFormDialog({super.key, required this.controller});
  final MaintainlyController controller;
  @override
  State<ReminderFormDialog> createState() => _ReminderFormDialogState();
}

class _ReminderFormDialogState extends State<ReminderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _odometer = TextEditingController();
  final _notes = TextEditingController();
  String? _vehicleId;
  DateTime? _date;
  @override
  void initState() {
    super.initState();
    _vehicleId = widget.controller.activeVehicles.isEmpty
        ? null
        : widget.controller.activeVehicles.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _odometer.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create reminder'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _vehicleId,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items: widget.controller.activeVehicles
                    .map(
                      (v) => DropdownMenuItem(value: v.id, child: Text(v.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _vehicleId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Reminder title'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _odometer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Due odometer (km)',
                      ),
                      validator: _optionalNonNegativeInteger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await _pickDate(context, _date);
                        if (d != null) setState(() => _date = d);
                      },
                      icon: const Icon(Icons.event, size: 17),
                      label: Text(
                        _date == null
                            ? 'Due date'
                            : '${_date!.day}/${_date!.month}/${_date!.year}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.controller.activeVehicles.isEmpty
            ? null
            : () async {
                if (!_formKey.currentState!.validate() || _vehicleId == null)
                  return;
                final km = _odometer.text.trim().isEmpty
                    ? null
                    : int.parse(_odometer.text.trim());
                if (_date == null && km == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Set a due date or due odometer.'),
                    ),
                  );
                  return;
                }
                await widget.controller.addReminder(
                  MaintenanceReminder(
                    id: _uuid.v4(),
                    vehicleId: _vehicleId!,
                    title: _title.text.trim(),
                    dueDate: _date,
                    dueOdometer: km,
                    notes: _notes.text.trim(),
                    completed: false,
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              },
        child: const Text('Save reminder'),
      ),
    ],
  );
}
