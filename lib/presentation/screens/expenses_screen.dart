import 'package:flutter/material.dart';

import '../../application/maintainly_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/expense.dart';
import '../dialogs/forms.dart';
import '../widgets/common_widgets.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.controller});
  final MaintainlyController controller;
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _search = TextEditingController();
  String _category = 'All';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expenses =
        widget.controller.expenses
            .where(
              (e) =>
                  (_category == 'All' || e.category == _category) &&
                  '${e.description} ${widget.controller.vehicleName(e.vehicleId)} ${e.category}'
                      .toLowerCase()
                      .contains(_search.text.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final visibleTotal = widget.controller.expenseTotal(expenses);
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SectionHeading(
          title: 'Expense tracker',
          subtitle: 'Fuel, labour, spare parts and operating costs',
          trailing: FilledButton.icon(
            onPressed: widget.controller.activeVehicles.isEmpty
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        ExpenseFormDialog(controller: widget.controller),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('Add expense'),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Standalone expenses',
                  value: formatMoney(widget.controller.totalExpenses),
                  icon: Icons.wallet_outlined,
                  tint: const Color(0xFF637DE0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Current filter total',
                  value: formatMoney(visibleTotal),
                  icon: Icons.filter_alt_outlined,
                  tint: const Color(0xFF159D83),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search description or vehicle',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                [
                      'All',
                      'Fuel',
                      'Labour',
                      'Parts',
                      'Insurance',
                      'Registration',
                      'Other',
                    ]
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: _category == f,
                          onSelected: (_) => setState(() => _category = f),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        const SizedBox(height: 15),
        if (expenses.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No expenses found',
            message: widget.controller.activeVehicles.isEmpty
                ? 'Add or restore a vehicle before logging costs.'
                : 'No expenses match the current search or filter.',
            action: FilledButton.icon(
              onPressed: widget.controller.activeVehicles.isEmpty
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          ExpenseFormDialog(controller: widget.controller),
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
          )
        else
          ...expenses.map(
            (e) => _ExpenseTile(expense: e, controller: widget.controller),
          ),
      ],
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.controller});
  final VehicleExpense expense;
  final MaintainlyController controller;

  @override
  Widget build(BuildContext context) {
    final icon = switch (expense.category) {
      'Fuel' => Icons.local_gas_station_outlined,
      'Labour' => Icons.handyman_outlined,
      'Parts' => Icons.settings_outlined,
      'Insurance' => Icons.shield_outlined,
      _ => Icons.receipt_long_outlined,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.secondary),
        ),
        title: Text(
          expense.description,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${controller.vehicleName(expense.vehicleId)} · ${expense.category} · ${formatDate(expense.date)}${expense.odometer == 0 ? '' : ' · ${formatKm(expense.odometer)}'}${expense.sourceServiceId == null ? '' : ' · Included in ${controller.serviceTitleById(expense.sourceServiceId) ?? 'service cost'}'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatMoney(expense.amount),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  showDialog<void>(
                    context: context,
                    builder: (_) => ExpenseFormDialog(
                      controller: controller,
                      expense: expense,
                    ),
                  );
                } else {
                  controller.deleteExpense(expense.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
