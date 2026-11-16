import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/maintainly_controller.dart';
import 'application/providers.dart';
import 'core/theme/app_theme.dart';
import 'data/backup/maintainly_backup.dart';
import 'data/backup/maintainly_backup_file_service.dart';
import 'data/repositories/maintainly_repository.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/expenses_screen.dart';
import 'presentation/screens/maintenance_screen.dart';
import 'presentation/screens/reports_screen.dart';
import 'presentation/screens/vehicles_screen.dart';

class MaintainlyApp extends ConsumerWidget {
  const MaintainlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(maintainlyControllerProvider);
    if (!controller.isReady) {
      return MaterialApp(theme: AppTheme.light(), home: const _LoadingScreen());
    }
    return MaterialApp(
      title: 'Maintainly Step 8.4 Chatgpt GitHub.com',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: controller.isDark ? ThemeMode.dark : ThemeMode.light,
      home: const _HomeShell(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_car_filled_outlined, size: 48),
          const SizedBox(height: 14),
          Text(
            'Maintainly',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 15),
          const SizedBox(width: 120, child: LinearProgressIndicator()),
        ],
      ),
    ),
  );
}

class _HomeShell extends ConsumerStatefulWidget {
  const _HomeShell();
  @override
  ConsumerState<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<_HomeShell> {
  int _index = 0;
  final MaintainlyBackupFileService _backupFiles =
      MaintainlyBackupFileService();

  Future<void> _handleBackupAction(
    _BackupAction action,
    MaintainlyController controller,
  ) async {
    try {
      if (action == _BackupAction.export) {
        final backup = MaintainlyBackup(
          createdAtUtc: DateTime.now().toUtc(),
          vehicles: controller.vehicles,
          services: controller.services,
          expenses: controller.expenses,
          reminders: controller.reminders,
        );
        final exported = await _backupFiles.exportBackup(backup);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exported ? 'JSON backup exported.' : 'Backup export cancelled.',
            ),
          ),
        );
        return;
      }

      final json = await _backupFiles.selectBackupJson();
      if (json == null || !mounted) return;
      final backup = MaintainlyBackup.decode(json);
      if (!mounted) return;
      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'The selected backup has been validated. Restoring it will replace '
            'all current Maintainly records.\n\n'
            'Vehicles: ${backup.vehicles.length}\n'
            'Services: ${backup.services.length}\n'
            'Expenses: ${backup.expenses.length}\n'
            'Reminders: ${backup.reminders.length}\n\n'
            'Before restoring, Maintainly will ask you to save a separate '
            'recovery backup of your current data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (shouldRestore != true || !mounted) return;

      final recoveryBackup = MaintainlyBackup(
        createdAtUtc: DateTime.now().toUtc(),
        vehicles: controller.vehicles,
        services: controller.services,
        expenses: controller.expenses,
        reminders: controller.reminders,
      );
      final recoverySaved = await _backupFiles.exportBackup(recoveryBackup);
      if (!recoverySaved || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Restore cancelled. Your current data is unchanged.',
              ),
            ),
          );
        }
        return;
      }

      await controller.restoreData(
        MaintainlyData(
          vehicles: backup.vehicles,
          services: backup.services,
          expenses: backup.expenses,
          reminders: backup.reminders,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup restored. A recovery copy was saved first.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup operation failed: $error')),
      );
    }
  }

  static const _titles = [
    'Overview',
    'Vehicle garage',
    'Maintenance',
    'Expenses',
    'Reports',
  ];
  static const _icons = [
    Icons.grid_view_rounded,
    Icons.directions_car_outlined,
    Icons.build_circle_outlined,
    Icons.receipt_long_outlined,
    Icons.insert_chart_outlined_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(maintainlyControllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final screens = [
      DashboardScreen(
        controller: controller,
        onNavigate: (index) => setState(() => _index = index),
      ),
      VehiclesScreen(controller: controller),
      MaintenanceScreen(controller: controller),
      ExpensesScreen(controller: controller),
      ReportsScreen(controller: controller),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titles[_index],
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (wide)
              Text(
                'MAINTAINLY  /  FLEET MANAGEMENT',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.3,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<_BackupAction>(
            tooltip: 'Backup and restore',
            icon: const Icon(Icons.backup_outlined),
            onSelected: (action) => _handleBackupAction(action, controller),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _BackupAction.export,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.download_outlined),
                  title: Text('Export JSON backup'),
                ),
              ),
              PopupMenuItem(
                value: _BackupAction.selectImport,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('Select backup file'),
                ),
              ),
            ],
          ),
          if (controller.overdueCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                tooltip: '${controller.overdueCount} overdue reminders',
                onPressed: () => setState(() => _index = 2),
                icon: Badge(
                  label: Text(controller.overdueCount.toString()),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ),
          IconButton(
            tooltip: controller.isDark
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            onPressed: controller.toggleTheme,
            icon: Icon(
              controller.isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              backgroundColor: Theme.of(context).colorScheme.surface,
              leading: Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 25),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
              destinations: List.generate(
                _titles.length,
                (i) => NavigationRailDestination(
                  icon: Icon(_icons[i]),
                  label: Text(_titles[i]),
                ),
              ),
            ),
          if (wide)
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: IndexedStack(index: _index, children: screens),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: List.generate(
                _titles.length,
                (i) => NavigationDestination(
                  icon: Icon(_icons[i]),
                  label: _titles[i],
                ),
              ),
            ),
    );
  }
}

enum _BackupAction { export, selectImport }
