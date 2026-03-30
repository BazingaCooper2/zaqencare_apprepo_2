import 'package:intl/intl.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// Shift Date/Time Helpers
/// ──────────────────────────────────────────────────────────────────────────────
/// Reusable utility functions that convert Supabase timestamp strings
/// (e.g. "2026-03-27T00:05:00+05:30") into human-friendly display strings.
///
/// Usage:
///   ShiftDateHelpers.formatDate(shift.clockIn.toString())
///   ShiftDateHelpers.formatTimeRange(clockIn, clockOut)
///   ShiftDateHelpers.formatDuration(clockIn, clockOut)
/// ──────────────────────────────────────────────────────────────────────────────

class ShiftDateHelpers {
  ShiftDateHelpers._(); // Prevent instantiation

  // ─── Core parser ──────────────────────────────────────────────────────────

  /// Parses a Supabase timestamp string into a local [DateTime].
  /// Returns `null` if parsing fails.
  static DateTime? parseTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return null;
    try {
      return DateTime.parse(timestamp).toLocal();
    } catch (_) {
      return null;
    }
  }

  // ─── Date formatting ─────────────────────────────────────────────────────

  /// Formats a timestamp into a friendly date string.
  ///
  /// Examples:
  ///   "Today, Mar 27"
  ///   "Tomorrow, Mar 28"
  ///   "Friday, Mar 27, 2026"
  static String formatDate(String? timestamp) {
    final dt = parseTimestamp(timestamp);
    if (dt == null) return 'No date';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final shiftDate = DateTime(dt.year, dt.month, dt.day);

    if (shiftDate == today) {
      return 'Today, ${DateFormat('MMM d').format(dt)}';
    } else if (shiftDate == tomorrow) {
      return 'Tomorrow, ${DateFormat('MMM d').format(dt)}';
    } else {
      return DateFormat('EEEE, MMM d, yyyy').format(dt);
    }
  }

  /// Formats a date-only string (e.g. "2026-03-27") the same way.
  static String formatDateFromDateString(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'No date';
    // Append time so DateTime.parse works on date-only strings
    return formatDate('${dateStr}T00:00:00');
  }

  // ─── Time formatting ─────────────────────────────────────────────────────

  /// Formats a single timestamp into 12-hour time.
  ///
  /// Example: "12:05 AM"
  static String formatTime(String? timestamp) {
    final dt = parseTimestamp(timestamp);
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  /// Formats two timestamps into a time range string.
  ///
  /// Example: "12:05 AM - 01:05 AM"
  static String formatTimeRange(String? clockIn, String? clockOut) {
    final start = formatTime(clockIn);
    final end = formatTime(clockOut);

    if (start.isEmpty && end.isEmpty) return 'Time not set';
    if (start.isEmpty) return end;
    if (end.isEmpty) return '$start - ongoing';

    return '$start - $end';
  }

  // ─── Duration formatting ──────────────────────────────────────────────────

  /// Calculates the duration between two timestamps and returns a
  /// human-readable string.
  ///
  /// Examples: "1h 0m", "8h 30m", "0h 45m"
  static String formatDuration(String? clockIn, String? clockOut) {
    final start = parseTimestamp(clockIn);
    final end = parseTimestamp(clockOut);

    if (start == null || end == null) return '';

    final diff = end.difference(start);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);

    return '${hours}h ${minutes}m';
  }

  /// Returns the duration as a [Duration] object (useful for calculations).
  static Duration? getDuration(String? clockIn, String? clockOut) {
    final start = parseTimestamp(clockIn);
    final end = parseTimestamp(clockOut);
    if (start == null || end == null) return null;
    return end.difference(start);
  }

  /// Returns duration in decimal hours (e.g. 1.5 for 1h 30m).
  static double? getDurationHours(String? clockIn, String? clockOut) {
    final duration = getDuration(clockIn, clockOut);
    if (duration == null) return null;
    return duration.inMinutes / 60.0;
  }

  // ─── Combined display strings ─────────────────────────────────────────────

  /// Combines time range + duration into a single display string.
  ///
  /// Example: "12:05 AM - 01:05 AM (1h 0m)"
  static String formatTimeRangeWithDuration(
      String? clockIn, String? clockOut) {
    final range = formatTimeRange(clockIn, clockOut);
    final duration = formatDuration(clockIn, clockOut);

    if (duration.isEmpty) return range;
    return '$range ($duration)';
  }
}
