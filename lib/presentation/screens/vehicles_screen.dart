import 'package:flutter/material.dart';

import '../../application/maintainly_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/vehicle.dart';
import '../dialogs/forms.dart';
import '../widgets/common_widgets.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key, required this.controller});
  final MaintainlyController controller;
  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final _search = TextEditingController();
  String _filter = 'All';
  bool _showArchived = false;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(Vehicle? vehicle) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          VehicleFormDialog(controller: widget.controller, vehicle: vehicle),
    );
  }

  Future<void> _details(Vehicle vehicle) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(vehicle.name),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${vehicle.year} ${vehicle.make} ${vehicle.model}${vehicle.isArchived ? ' · ARCHIVED' : ''}',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text('${vehicle.type} · ${vehicle.registration}'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _detailChip(
                      context,
                      'Odometer',
                      formatKm(vehicle.odometer),
                    ),
                    _detailChip(
                      context,
                      'Purchase price',
                      formatMoney(vehicle.purchasePrice),
                    ),
                    _detailChip(
                      context,
                      'Purchased',
                      formatDate(vehicle.purchaseDate),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Service history',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ...widget.controller.services
                    .where((s) => s.vehicleId == vehicle.id)
                    .take(8)
                    .map(
                      (s) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.build_circle_outlined),
                        title: Text(s.title),
                        subtitle: Text(
                          '${formatDate(s.date)} · ${formatKm(s.odometer)}',
                        ),
                        trailing: Text(formatMoney(s.cost)),
                      ),
                    ),
                if (widget.controller.services
                    .where((s) => s.vehicleId == vehicle.id)
                    .isEmpty)
                  const Text('No service records yet.'),
                const SizedBox(height: 14),
                Text(
                  'Expense history',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ...widget.controller.expenses
                    .where((e) => e.vehicleId == vehicle.id)
                    .take(8)
                    .map(
                      (e) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(e.description),
                        subtitle: Text(
                          '${formatDate(e.date)} · ${e.category}${e.sourceServiceId == null ? '' : ' · Included in service cost'}',
                        ),
                        trailing: Text(formatMoney(e.amount)),
                      ),
                    ),
                if (widget.controller.expenses
                    .where((e) => e.vehicleId == vehicle.id)
                    .isEmpty)
                  const Text('No expense records yet.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (vehicle.isArchived)
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await widget.controller.restoreVehicle(vehicle.id);
              },
              icon: const Icon(Icons.unarchive_outlined),
              label: const Text('Restore vehicle'),
            )
          else ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _confirmArchive(vehicle);
              },
              child: const Text('Archive', style: TextStyle(color: Colors.red)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _edit(vehicle);
              },
              child: const Text('Edit vehicle'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailChip(BuildContext context, String label, String value) =>
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Future<void> _confirmArchive(Vehicle vehicle) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive vehicle?'),
        content: Text(
          'Archive ${vehicle.name}? It will be removed from active vehicle lists, but all service records, expenses and reminders will be preserved. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (yes == true) await widget.controller.archiveVehicle(vehicle.id);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase();
    final sourceVehicles = _showArchived
        ? widget.controller.archivedVehicles
        : widget.controller.activeVehicles;
    final items = sourceVehicles
        .where(
          (v) =>
              (_filter == 'All' || v.type == _filter) &&
              ('${v.name} ${v.make} ${v.model} ${v.registration}'
                  .toLowerCase()
                  .contains(query)),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SectionHeading(
          title: 'Vehicle garage',
          subtitle: _showArchived
              ? '${widget.controller.archivedVehicles.length} archived vehicles'
              : '${widget.controller.activeVehicles.length} active vehicles',
          trailing: _showArchived
              ? null
              : FilledButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add vehicle'),
                ),
        ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(
                'Active (${widget.controller.activeVehicles.length})',
              ),
              selected: !_showArchived,
              onSelected: (_) => setState(() {
                _showArchived = false;
                _filter = 'All';
              }),
            ),
            ChoiceChip(
              label: Text(
                'Archived (${widget.controller.archivedVehicles.length})',
              ),
              selected: _showArchived,
              onSelected: (_) => setState(() {
                _showArchived = true;
                _filter = 'All';
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name, model or registration',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            //     children: [
            //   'All',
            //   ...['Car', 'Motorcycle', 'Commercial', 'Other']
            // ].map((f) => Padding(
            //         padding: const EdgeInsets.only(right: 8),
            //         child: ChoiceChip(
            //             label: Text(f),
            //             selected: _filter == f,
            //             onSelected: (_) => setState(() => _filter = f))))

            /* neechay wala AI corrected code tha, lekin ic me b if wala error hai */
            // if (!wide)
            //   return Column(
            //       children: items
            //           .map<Widget>((v) => Padding(
            //               // Error: Dart type inference on .map().toList() infers List<Object> instead of List<Widget>
            //               padding: const EdgeInsets.only(bottom: 12),
            //               child: _VehicleCard(
            //                   vehicle: v,
            //                   controller: widget.controller,
            //                   onTap: () => _details(v),
            //                   onEdit: () => _edit(v))))
            //           .toList());
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          EmptyState(
            icon: Icons.directions_car_outlined,
            title: 'No vehicles found',
            message: _search.text.isEmpty
                ? (_showArchived
                      ? 'No archived vehicles.'
                      : 'Add a vehicle to start building its maintenance history.')
                : 'No vehicles match this search.',
            action: _showArchived
                ? null
                : FilledButton.icon(
                    onPressed: () => _edit(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add vehicle'),
                  ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 850;
              final crossAxisCount = constraints.maxWidth > 1200 ? 3 : 2;
              if (!wide)
                return Column(
                  children: items
                      .map(
                        (v) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _VehicleCard(
                            vehicle: v,
                            controller: widget.controller,
                            onTap: () => _details(v),
                            onEdit: () => _edit(v),
                          ),
                        ),
                      )
                      .toList(),
                );
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 220,
                ),
                itemBuilder: (_, i) {
                  final v = items[i];
                  return _VehicleCard(
                    vehicle: v,
                    controller: widget.controller,
                    onTap: () => _details(v),
                    onEdit: () => _edit(v),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.controller,
    required this.onTap,
    required this.onEdit,
  });
  final Vehicle vehicle;
  final MaintainlyController controller;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final serviceCount = controller.services
        .where((s) => s.vehicleId == vehicle.id)
        .length;
    final spend =
        controller.expenseTotal(
          controller.expenses.where((e) => e.vehicleId == vehicle.id),
        ) +
        controller.services
            .where((s) => s.vehicleId == vehicle.id)
            .fold<double>(0, (sum, s) => sum + s.cost);
    final icon = vehicle.type == 'Motorcycle'
        ? Icons.two_wheeler
        : vehicle.type == 'Commercial'
        ? Icons.local_shipping_outlined
        : Icons.directions_car_outlined;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit')
                        onEdit();
                      else if (v == 'restore')
                        controller.restoreVehicle(vehicle.id);
                      else
                        onTap();
                    },
                    itemBuilder: (_) => [
                      if (!vehicle.isArchived)
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'details',
                        child: const Text('Details'),
                      ),
                      if (vehicle.isArchived)
                        const PopupMenuItem(
                          value: 'restore',
                          child: Text('Restore'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                '${vehicle.name}${vehicle.isArchived ? ' · Archived' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${vehicle.year} ${vehicle.make} ${vehicle.model}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(Icons.confirmation_number_outlined, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    vehicle.registration,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    vehicle.type,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(
                      context,
                      'Odometer',
                      formatKm(vehicle.odometer),
                    ),
                  ),
                  Expanded(
                    child: _miniStat(
                      context,
                      'Service logs',
                      serviceCount.toString(),
                    ),
                  ),
                  Expanded(
                    child: _miniStat(
                      context,
                      'Recorded spend',
                      formatMoney(spend),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}
