import 'package:flutter/material.dart';

import '../../application/maintainly_controller.dart';
import '../../core/utils/formatters.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onNavigate,
  });
  final MaintainlyController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final due =
        controller.reminders
            .where(
              (r) =>
                  controller.vehicleById(r.vehicleId)?.isArchived != true &&
                  !r.completed &&
                  (controller.isOverdue(r) || controller.isDueSoon(r)),
            )
            .toList()
          ..sort(
            (a, b) => controller.isOverdue(a) == controller.isOverdue(b)
                ? (a.dueDate ?? DateTime(2100)).compareTo(
                    b.dueDate ?? DateTime(2100),
                  )
                : (controller.isOverdue(a) ? -1 : 1),
          );
    final recent = [...controller.services]
      ..sort((a, b) => b.date.compareTo(a.date));
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1100
            ? 4
            : constraints.maxWidth > 650
            ? 2
            : 2;
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(.78),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your fleet, under control.',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Maintenance records, running costs and service schedules in one place.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.white.withOpacity(.88)),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 9,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary,
                              ),
                              onPressed: () => onNavigate(1),
                              icon: const Icon(Icons.add),
                              label: const Text('Add vehicle'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withOpacity(.55),
                                ),
                              ),
                              onPressed: () => onNavigate(2),
                              icon: const Icon(Icons.build_outlined),
                              label: const Text('Log service'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (constraints.maxWidth > 700) const SizedBox(width: 18),
                  if (constraints.maxWidth > 700)
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.13),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions_car_filled_outlined,
                        size: 54,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: constraints.maxWidth < 420 ? 1.28 : 1.55,
              children: [
                MetricCard(
                  label: 'Vehicles in garage',
                  value: controller.activeVehicles.length.toString(),
                  icon: Icons.directions_car_outlined,
                  tint: const Color(0xFF159D83),
                  caption: 'Active records',
                ),
                MetricCard(
                  label: 'Overdue reminders',
                  value: controller.overdueCount.toString(),
                  icon: Icons.warning_amber_rounded,
                  tint: const Color(0xFFE06C55),
                  caption: 'Needs attention',
                ),
                MetricCard(
                  label: 'Due soon',
                  value: controller.upcomingCount.toString(),
                  icon: Icons.event_available_outlined,
                  tint: const Color(0xFFD69A35),
                  caption: 'Next 30 days / 1,000 km',
                ),
                MetricCard(
                  label: 'Recorded spending',
                  value: formatMoney(controller.totalSpend),
                  icon: Icons.account_balance_wallet_outlined,
                  tint: const Color(0xFF637DE0),
                  caption: 'Service + expenses',
                ),
              ],
            ),
            const SizedBox(height: 25),
            SectionHeading(
              title: 'Maintenance attention',
              subtitle: 'Overdue and upcoming reminders',
              trailing: TextButton(
                onPressed: () => onNavigate(2),
                child: const Text('View all'),
              ),
            ),
            if (due.isEmpty)
              const EmptyState(
                icon: Icons.verified_outlined,
                title: 'All clear',
                message: 'No overdue or upcoming maintenance reminders are recorded.',
              )
            else
              ...due.take(4).map((r) {
                final overdue = controller.isOverdue(r);
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          (overdue
                                  ? const Color(0xFFE06C55)
                                  : const Color(0xFFD69A35))
                              .withOpacity(.12),
                      child: Icon(
                        overdue ? Icons.priority_high : Icons.schedule,
                        color: overdue
                            ? const Color(0xFFE06C55)
                            : const Color(0xFFD69A35),
                      ),
                    ),
                    title: Text(
                      r.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${controller.vehicleName(r.vehicleId)} · ${r.dueDate == null ? '' : formatDate(r.dueDate)}${r.dueOdometer == null ? '' : ' · ${formatKm(r.dueOdometer!)}'}',
                    ),
                    trailing: StatusPill(
                      label: overdue ? 'OVERDUE' : 'DUE SOON',
                      color: overdue
                          ? const Color(0xFFE06C55)
                          : const Color(0xFFD69A35),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 23),
            SectionHeading(
              title: 'Recent service activity',
              subtitle: 'Latest logged workshop visits',
              trailing: TextButton(
                onPressed: () => onNavigate(2),
                child: const Text('View history'),
              ),
            ),
            if (recent.isEmpty)
              const EmptyState(
                icon: Icons.handyman_outlined,
                title: 'No service records',
                message: 'Service activity will appear here once recorded.',
              )
            else
              ...recent
                  .take(4)
                  .map(
                    (s) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.build_outlined),
                        ),
                        title: Text(
                          s.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${controller.vehicleName(s.vehicleId)} · ${formatDate(s.date)}',
                        ),
                        trailing: Text(
                          formatMoney(s.cost),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}
