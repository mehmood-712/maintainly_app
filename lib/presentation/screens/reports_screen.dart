import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../application/maintainly_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/vehicle.dart';
import '../widgets/common_widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.controller});
  final MaintainlyController controller;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String? _vehicleId;
  bool _busy = false;

  Future<void> _printReport({Vehicle? vehicle}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final doc = _buildReport(widget.controller, vehicle: vehicle);
      await Printing.layoutPdf(
        name: vehicle == null
            ? 'maintainly-fleet-report.pdf'
            : 'maintainly-${vehicle.registration}-report.pdf',
        onLayout: (format) async => doc.save(),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate report: $error')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final vehicle = _vehicleId == null
        ? null
        : controller.vehicleById(_vehicleId!);
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SectionHeading(
          title: 'Reports & insights',
          subtitle: 'Printable fleet summaries and vehicle records',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.summarize_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fleet overview report',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'All vehicles, service records and recorded spending',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _summaryValue(
                      context,
                      'Vehicles (incl. archived)',
                      controller.vehicles.length.toString(),
                    ),
                    _summaryValue(
                      context,
                      'Service records',
                      controller.services.length.toString(),
                    ),
                    _summaryValue(
                      context,
                      'Expense entries',
                      controller.expenses.length.toString(),
                    ),
                    _summaryValue(
                      context,
                      'Total recorded cost',
                      formatMoney(controller.totalSpend),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _busy ||
                            (controller.vehicles.isEmpty &&
                                controller.services.isEmpty &&
                                controller.expenses.isEmpty)
                        ? null
                        : () => _printReport(),
                    icon: _busy
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      _busy ? 'Preparing report…' : 'Generate fleet PDF',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Individual vehicle report',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'A focused report containing the selected vehicle profile, maintenance log and expenses.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: _vehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Select vehicle',
                  ),
                  items: controller.vehicles
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.id,
                          child: Text('${v.name} · ${v.registration}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _vehicleId = value),
                ),
                const SizedBox(height: 13),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy || vehicle == null
                        ? null
                        : () => _printReport(vehicle: vehicle),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Generate vehicle PDF'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Reports include locally recorded data only. The PDF opens the platform print/share dialog; choose Save as PDF or the available share destination.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryValue(BuildContext context, String label, String value) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
}

pw.Widget _cell(String value, {bool header = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
  child: pw.Text(
    value,
    style: pw.TextStyle(
      fontSize: header ? 8 : 8.5,
      fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: header ? PdfColors.white : PdfColors.blueGrey900,
    ),
  ),
);

pw.Widget _table(List<String> headers, List<List<String>> rows) => pw.Table(
  border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
  columnWidths: {
    for (var i = 0; i < headers.length; i++) i: const pw.FlexColumnWidth(),
  },
  children: [
    pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF167F70)),
      children: headers.map((e) => _cell(e, header: true)).toList(),
    ),
    ...rows.map(
      (row) => pw.TableRow(children: row.map((e) => _cell(e)).toList()),
    ),
  ],
);

pw.Document _buildReport(MaintainlyController c, {Vehicle? vehicle}) {
  final vehicles = vehicle == null ? c.vehicles : [vehicle];
  final ids = vehicles.map((v) => v.id).toSet();
  final services = c.services.where((s) => ids.contains(s.vehicleId)).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  final expenses = c.expenses.where((e) => ids.contains(e.vehicleId)).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  final reminders = c.reminders
      .where((r) => ids.contains(r.vehicleId))
      .toList();
  final sum =
      services.fold<double>(0, (v, s) => v + s.cost) + c.expenseTotal(expenses);
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Maintainly · Local vehicle records',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 15),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: PdfColor.fromInt(0xFF167F70),
                width: 2,
              ),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'MAINTAINLY',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF167F70),
                    ),
                  ),
                  pw.Text(
                    vehicle == null
                        ? 'Fleet report'
                        : 'Vehicle report · ${vehicle.name}',
                    style: const pw.TextStyle(
                      fontSize: 11,
                      color: PdfColors.blueGrey700,
                    ),
                  ),
                ],
              ),
              pw.Text(
                'Generated ${formatDate(DateTime.now())}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 15),
        pw.Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _pdfMetric('Vehicles', vehicles.length.toString()),
            _pdfMetric('Service records', services.length.toString()),
            _pdfMetric('Expense entries', expenses.length.toString()),
            _pdfMetric('Total recorded cost', formatMoney(sum)),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'VEHICLE REGISTER',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF167F70),
          ),
        ),
        pw.SizedBox(height: 7),
        _table(
          [
            'Vehicle',
            'Type / status',
            'Registration',
            'Odometer',
            'Purchase price',
          ],
          vehicles
              .map(
                (v) => [
                  v.name,
                  v.type + (v.isArchived ? ' (Archived)' : ''),
                  v.registration,
                  formatKm(v.odometer),
                  formatMoney(v.purchasePrice),
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'SERVICE HISTORY',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF167F70),
          ),
        ),
        pw.SizedBox(height: 7),
        if (services.isEmpty)
          pw.Text('No service records.', style: const pw.TextStyle(fontSize: 9))
        else
          _table(
            ['Date', 'Vehicle', 'Service', 'Odometer', 'Cost'],
            services
                .map(
                  (s) => [
                    formatDate(s.date),
                    c.vehicleName(s.vehicleId),
                    s.title,
                    formatKm(s.odometer),
                    formatMoney(s.cost),
                  ],
                )
                .toList(),
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'EXPENSES',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF167F70),
          ),
        ),
        pw.SizedBox(height: 7),
        if (expenses.isEmpty)
          pw.Text('No expense records.', style: const pw.TextStyle(fontSize: 9))
        else
          _table(
            ['Date', 'Vehicle', 'Category', 'Description', 'Amount'],
            expenses
                .map(
                  (e) => [
                    formatDate(e.date),
                    c.vehicleName(e.vehicleId),
                    e.category,
                    e.description +
                        (e.sourceServiceId == null
                            ? ''
                            : ' (included in service cost)'),
                    formatMoney(e.amount),
                  ],
                )
                .toList(),
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'MAINTENANCE REMINDERS',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF167F70),
          ),
        ),
        pw.SizedBox(height: 7),
        if (reminders.isEmpty)
          pw.Text(
            'No reminder records.',
            style: const pw.TextStyle(fontSize: 9),
          )
        else
          _table(
            ['Vehicle', 'Reminder', 'Due date', 'Due odometer', 'Status'],
            reminders
                .map(
                  (r) => [
                    c.vehicleName(r.vehicleId),
                    r.title,
                    formatDate(r.dueDate),
                    r.dueOdometer == null ? '—' : formatKm(r.dueOdometer!),
                    r.completed
                        ? 'Completed'
                        : c.isOverdue(r)
                        ? 'Overdue'
                        : c.isDueSoon(r)
                        ? 'Due soon'
                        : 'Scheduled',
                  ],
                )
                .toList(),
          ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Figures reflect records entered in Maintainly and are not independently verified.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc;
}

pw.Widget _pdfMetric(String label, String value) => pw.Container(
  width: 118,
  padding: const pw.EdgeInsets.all(9),
  decoration: pw.BoxDecoration(
    color: PdfColors.grey100,
    borderRadius: pw.BorderRadius.circular(5),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ),
);
