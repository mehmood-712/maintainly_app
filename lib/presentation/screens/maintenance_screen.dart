import 'package:flutter/material.dart';

import '../../application/maintainly_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/maintenance_reminder.dart';
import '../../data/models/service_record.dart';
import '../dialogs/forms.dart';
import '../widgets/common_widgets.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, required this.controller});
  final MaintainlyController controller;
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _search = TextEditingController();
  String _filter = 'All';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final reminders =
        controller.reminders.where((r) {
          if (controller.vehicleById(r.vehicleId)?.isArchived == true)
            return false;
          final statusMatches = switch (_filter) {
            'Overdue' => controller.isOverdue(r),
            'Due soon' => controller.isDueSoon(r),
            'Completed' => r.completed,
            'Open' => !r.completed,
            _ => true,
          };
          return statusMatches &&
              '${r.title} ${controller.vehicleName(r.vehicleId)}'
                  .toLowerCase()
                  .contains(_search.text.toLowerCase());
        }).toList()..sort(
          (a, b) => controller.isOverdue(a) == controller.isOverdue(b)
              ? (a.dueDate ?? DateTime(2100)).compareTo(
                  b.dueDate ?? DateTime(2100),
                )
              : (controller.isOverdue(a) ? -1 : 1),
        );
    final services = [...controller.services]
      ..sort((a, b) => b.date.compareTo(a.date));

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
            child: SectionHeading(
              title: 'Maintenance',
              subtitle: 'Reminders and complete service history',
              trailing: FilledButton.icon(
                onPressed: controller.activeVehicles.isEmpty
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            ReminderFormDialog(controller: controller),
                      ),
                icon: const Icon(Icons.add_alert),
                label: const Text('Reminder'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: TabBar(
              tabs: [
                Tab(text: 'Reminders (${controller.reminders.length})'),
                Tab(text: 'Service history (${controller.services.length})'),
              ],
              dividerHeight: 1,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search reminders or vehicles',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            ['All', 'Open', 'Overdue', 'Due soon', 'Completed']
                                .map(
                                  (f) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(f),
                                      selected: _filter == f,
                                      onSelected: (_) =>
                                          setState(() => _filter = f),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (reminders.isEmpty)
                      EmptyState(
                        icon: Icons.notifications_active_outlined,
                        title: 'No reminders found',
                        message: controller.activeVehicles.isEmpty
                            ? 'Add or restore a vehicle before creating reminders.'
                            : 'No reminders match the selected filter.',
                        action: FilledButton.icon(
                          onPressed: controller.activeVehicles.isEmpty
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => ReminderFormDialog(
                                    controller: controller,
                                  ),
                                ),
                          icon: const Icon(Icons.add),
                          label: const Text('Create reminder'),
                        ),
                      )
                    else
                      ...reminders.map(
                        (r) =>
                            _ReminderTile(reminder: r, controller: controller),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    SectionHeading(
                      title: 'Service records',
                      subtitle: 'Repairs, oil changes, parts and inspections',
                      trailing: FilledButton.icon(
                        onPressed: controller.activeVehicles.isEmpty
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    ServiceFormDialog(controller: controller),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Log service'),
                      ),
                    ),
                    if (services.isEmpty)
                      EmptyState(
                        icon: Icons.handyman_outlined,
                        title: 'No service history',
                        message: 'Log the first workshop visit to build a digital maintenance history.',
                      )
                    else
                      ...services.map(
                        (s) => _ServiceTile(record: s, controller: controller),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.controller});
  final MaintenanceReminder reminder;
  final MaintainlyController controller;

  @override
  Widget build(BuildContext context) {
    final overdue = controller.isOverdue(reminder);
    final soon = controller.isDueSoon(reminder);
    final color = reminder.completed
        ? const Color(0xFF159D83)
        : overdue
        ? const Color(0xFFE06C55)
        : soon
        ? const Color(0xFFD69A35)
        : Theme.of(context).colorScheme.primary;
    final state = reminder.completed
        ? 'COMPLETED'
        : overdue
        ? 'OVERDUE'
        : soon
        ? 'DUE SOON'
        : 'SCHEDULED';
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Checkbox(
              value: reminder.completed,
              onChanged: (_) => controller.toggleReminder(reminder.id),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: reminder.completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${controller.vehicleName(reminder.vehicleId)}${reminder.dueDate == null ? '' : ' · ${formatDate(reminder.dueDate)}'}${reminder.dueOdometer == null ? '' : ' · ${formatKm(reminder.dueOdometer!)}'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (reminder.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        reminder.notes,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 7),
                  StatusPill(label: state, color: color),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'toggle') controller.toggleReminder(reminder.id);
                if (v == 'delete') controller.deleteReminder(reminder.id);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    reminder.completed ? 'Mark open' : 'Mark completed',
                  ),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.record, required this.controller});
  final ServiceRecord record;
  final MaintainlyController controller;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.build_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        record.title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${controller.vehicleName(record.vehicleId)} · ${record.category}\n${formatDate(record.date)} · ${formatKm(record.odometer)}${record.mechanic.isEmpty ? '' : ' · ${record.mechanic}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: SizedBox(
        width: 90,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(record.cost),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'edit') {
                  showDialog<void>(
                    context: context,
                    builder: (_) => ServiceFormDialog(
                      controller: controller,
                      record: record,
                    ),
                  );
                } else {
                  controller.deleteService(record.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit record')),
                PopupMenuItem(value: 'delete', child: Text('Delete record')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
