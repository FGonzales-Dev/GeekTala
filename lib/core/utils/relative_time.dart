String formatRelativeTime(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${time.month}/${time.day}';
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

int _daysBetween(DateTime earlier, DateTime later) => DateTime(
  later.year,
  later.month,
  later.day,
).difference(DateTime(earlier.year, earlier.month, earlier.day)).inDays;

/// A note's date in a list, like Apple Notes: the time today, "Yesterday",
/// the weekday this week, then `9/28` (or `9/28/24` in another year).
String formatNoteDate(DateTime time, DateTime now) {
  final days = _daysBetween(time, now);
  if (days <= 0) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[time.weekday - 1];
  if (time.year == now.year) return '${time.month}/${time.day}';
  return '${time.month}/${time.day}/${time.year % 100}';
}

/// Which heading a note goes under in a date-grouped list: "Today",
/// "Yesterday", "Previous 7 Days", "Previous 30 Days", then the month (this
/// year) or the year.
String noteDateGroup(DateTime time, DateTime now) {
  final days = _daysBetween(time, now);
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'Previous 7 Days';
  if (days < 30) return 'Previous 30 Days';
  if (time.year == now.year) return _months[time.month - 1];
  return '${time.year}';
}
