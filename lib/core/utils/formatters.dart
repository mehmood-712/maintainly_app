import 'package:intl/intl.dart';

final _dateFormat = DateFormat('dd MMM yyyy');
final _numberFormat = NumberFormat('#,##0');
final _decimalFormat = NumberFormat('#,##0.00');

String formatDate(DateTime? value) =>
    value == null ? 'Not set' : _dateFormat.format(value);
String formatMoney(num value) => 'Rs ${_numberFormat.format(value)}';
String formatNumber(num value) => _numberFormat.format(value);
String formatKm(num value) => '${_numberFormat.format(value)} km';
String formatCompactMoney(num value) => 'Rs ${_decimalFormat.format(value)}';
