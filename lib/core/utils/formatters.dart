import 'package:intl/intl.dart';

class Formatters {
  static final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String dateTime(DateTime value) => _dateTime.format(value);
}
