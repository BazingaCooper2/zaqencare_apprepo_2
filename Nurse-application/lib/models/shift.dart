import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nurse_tracking_app/models/client.dart';
import 'package:nurse_tracking_app/models/patient.dart';
import 'package:nurse_tracking_app/utils/shift_date_helpers.dart';

class Shift {
  final int shiftId;
  final int? empId;
  final int? clientId;
  final String? shiftStatus;
  final String? shiftStartTime;
  final String? shiftEndTime;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final String? date;
  final String? shiftType;
  final Client? client;
  final String? taskId;
  final String? skills;
  final String? serviceInstructions;
  final String? tags;
  final String? forms;
  final String? shiftProgressNote;
  final Patient? patient;
  final String? useServiceDuration;

  // ✅ NEW: Shift type / block fields
  final String? shiftMode;       // "individual" | "block"
  final int? parentBlockId;      // null = parent/standalone, int = child shift
  final String? department;      // program type for block shifts

  Shift({
    required this.shiftId,
    this.empId,
    this.clientId,
    this.shiftStatus,
    this.shiftStartTime,
    this.shiftEndTime,
    this.clockIn,
    this.clockOut,
    this.date,
    this.shiftType,
    this.client,
    this.taskId,
    this.skills,
    this.serviceInstructions,
    this.tags,
    this.forms,
    this.shiftProgressNote,
    this.patient,
    this.useServiceDuration,
    this.shiftMode,
    this.parentBlockId,
    this.department,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    int? parseBigInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return Shift(
      shiftId: parseBigInt(json['shift_id']) ?? 0,
      empId: parseBigInt(json['emp_id']),
      clientId: parseBigInt(json['client_id']),
      shiftStatus: json['shift_status']?.toString(),
      shiftStartTime: json['shift_start_time']?.toString(),
      shiftEndTime: json['shift_end_time']?.toString(),
      clockIn: json['clock_in'] != null
          ? DateTime.parse(json['clock_in'].toString())
          : null,
      clockOut: json['clock_out'] != null
          ? DateTime.parse(json['clock_out'].toString())
          : null,
      date: json['date']?.toString() ?? 
            (json['shift_start_time'] != null ? json['shift_start_time'].toString().split('T').first : null),
      shiftType: json['shift_type']?.toString(),
      client: () {
        final clientData = json['client'] ?? json['client_final'];
        if (clientData == null) return null;
        if (clientData is List && clientData.isNotEmpty) {
          final first = clientData.first;
          if (first is Map) {
            return Client.fromJson(Map<String, dynamic>.from(first));
          }
        } else if (clientData is Map) {
          return Client.fromJson(Map<String, dynamic>.from(clientData));
        }
        return null;
      }(),
      taskId: json['task_id']?.toString(),
      skills: json['skills'] is List
          ? (json['skills'] as List).join(', ')
          : json['skills']?.toString(),
      serviceInstructions: json['service_instructions']?.toString(),
      tags: json['tags'] is List
          ? (json['tags'] as List).join(', ')
          : json['tags']?.toString(),
      forms: json['forms'] is List
          ? (json['forms'] as List).join(', ')
          : json['forms']?.toString(),
      shiftProgressNote: json['shift_progress_note']?.toString(),
      patient: null,
      useServiceDuration: json['use_service_duration']?.toString(),
      shiftMode: json['shift_mode']?.toString(),
      parentBlockId: parseBigInt(json['parent_block_id']),
      department: json['department']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shift_id': shiftId,
      'client_id': clientId,
      'emp_id': empId,
      'date': date,
      'shift_start_time': shiftStartTime,
      'shift_end_time': shiftEndTime,
      'task_id': taskId,
      'skills': skills,
      'service_instructions': serviceInstructions,
      'tags': tags,
      'forms': forms,
      'shift_status': shiftStatus,
      'shift_progress_note': shiftProgressNote,
      'use_service_duration': useServiceDuration,
      'shift_mode': shiftMode,
      'parent_block_id': parentBlockId,
      'department': department,
    };
  }

  // Compatibility getters
  String? get clientName {
    if (client != null) {
      final fn = client!.fullName;
      if (fn.isNotEmpty) return fn;
    }
    if (department != null && department!.trim().isNotEmpty) return department;
    return clientId != null ? 'Client (ID: $clientId)' : 'Shift #$shiftId';
  }
  String? get clientLocation => client?.fullAddress;
  String? get clientServiceType => client?.serviceType ?? '';

  // ✅ Shift type classification helpers
  bool get isIndividualShift {
    final mode = (shiftMode ?? 'individual').toLowerCase().trim();
    return mode == 'individual' && parentBlockId == null;
  }

  bool get isBlockParent {
    final mode = (shiftMode ?? '').toLowerCase().trim();
    return mode == 'block' && parentBlockId == null;
  }

  bool get isBlockChild {
    final mode = (shiftMode ?? 'individual').toLowerCase().trim();
    return mode == 'individual' && parentBlockId != null;
  }

  /// Only individual and child block shifts can be clocked in/out
  bool get canClockInOut => isIndividualShift || isBlockChild;

  Shift copyWith({
    int? shiftId,
    int? clientId,
    int? empId,
    String? date,
    String? shiftStartTime,
    String? shiftEndTime,
    String? taskId,
    String? skills,
    String? serviceInstructions,
    String? tags,
    String? forms,
    String? shiftStatus,
    String? shiftProgressNote,
    Patient? patient,
    String? useServiceDuration,
    Client? client,
    DateTime? clockIn,
    DateTime? clockOut,
    String? shiftMode,
    int? parentBlockId,
    String? department,
  }) {
    return Shift(
      shiftId: shiftId ?? this.shiftId,
      clientId: clientId ?? this.clientId,
      empId: empId ?? this.empId,
      date: date ?? this.date,
      shiftStartTime: shiftStartTime ?? this.shiftStartTime,
      shiftEndTime: shiftEndTime ?? this.shiftEndTime,
      clockIn: clockIn ?? this.clockIn,
      clockOut: clockOut ?? this.clockOut,
      taskId: taskId ?? this.taskId,
      skills: skills ?? this.skills,
      serviceInstructions: serviceInstructions ?? this.serviceInstructions,
      tags: tags ?? this.tags,
      forms: forms ?? this.forms,
      shiftStatus: shiftStatus ?? this.shiftStatus,
      shiftProgressNote: shiftProgressNote ?? this.shiftProgressNote,
      patient: patient ?? this.patient,
      useServiceDuration: useServiceDuration ?? this.useServiceDuration,
      client: client ?? this.client,
      shiftMode: shiftMode ?? this.shiftMode,
      parentBlockId: parentBlockId ?? this.parentBlockId,
      department: department ?? this.department,
    );
  }

  String get statusDisplayText {
    final normalized = shiftStatus?.toLowerCase().replaceAll(' ', '_');
    switch (normalized) {
      case 'scheduled':
        return 'Scheduled';
      case 'offered':
        return 'Offered';
      case 'accepted':
        return 'Accepted';
      case 'assigned':
        return 'Assigned';
      case 'clocked_in':
        return 'Clocked in';
      case 'clocked_out':
        return 'Clocked out';
      case 'cancelled':
        return 'Cancelled';
      default:
        return shiftStatus ?? 'Unknown';
    }
  }

  Color get statusColor {
    final normalized = shiftStatus?.toLowerCase().replaceAll(' ', '_');
    switch (normalized) {
      case 'scheduled':
        return Colors.orange;
      case 'offered':
        return Colors.blueGrey;
      case 'accepted':
        return Colors.teal;
      case 'assigned':
        return Colors.indigo;
      case 'clocked_in':
        return Colors.blue;
      case 'clocked_out':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static DateTime? _parseTimeAny(String? input) {
    if (input == null || input.isEmpty) return null;

    // 1. Try ISO8601 (e.g., "2026-01-22T14:45:00")
    try {
      return DateTime.parse(input);
    } catch (_) {}

    // 2. Try DateFormat parsing for common formats
    final formats = [
      'h:mm a',
      'hh:mm a',
      'HH:mm:ss',
      'HH:mm',
    ];

    for (final format in formats) {
      try {
        final parsed = DateFormat(format).parse(input);
        final now = DateTime.now();
        // Shift time into "today" to make difference calculations work
        return DateTime(
          now.year,
          now.month,
          now.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
        );
      } catch (_) {}
    }

    debugPrint('⚠️ _parseTimeAny: Failed to parse "$input"');
    return null;
  }

  double? get durationHours {
    final start = _parseTimeAny(shiftStartTime);
    final end = _parseTimeAny(shiftEndTime);
    if (start == null || end == null) return null;

    // If end is before start in time-only mode, mostly doesn't happen with full dates.
    // If it does (night shift), logic needs to handle date crossing, but usually full ISO handles it.
    Duration diff = end.difference(start);

    // Handle overnight shifts (e.g., 10 PM → 6 AM)
    if (diff.isNegative) {
      diff = end.add(const Duration(days: 1)).difference(start);
    }

    return diff.inMinutes / 60.0;
  }

  double? get overtimeHours {
    final duration = durationHours;
    if (duration == null) return null;
    return duration > 8 ? duration - 8 : 0;
  }

  static String formatTime12Hour(String? timeInput) {
    if (timeInput == null || timeInput.isEmpty) return '';
    try {
      final dateTime = _parseTimeAny(timeInput);
      if (dateTime != null) {
        return DateFormat('h:mm a').format(dateTime);
      }
      return timeInput;
    } catch (_) {
      return timeInput;
    }
  }

  String get formattedStartTime => formatTime12Hour(shiftStartTime);
  String get formattedEndTime => formatTime12Hour(shiftEndTime);

  // Get formatted time range (e.g., "9:00 AM - 5:00 PM")
  // Uses old text fields shiftStartTime/shiftEndTime (scheduled time)
  String get formattedTimeRange {
    if (shiftStartTime == null || shiftEndTime == null) {
      return 'Time not set';
    }
    return '$formattedStartTime - $formattedEndTime';
  }

  // ─── Clock-in / Clock-out timestamp getters ────────────────────────────
  // These use the actual clock_in / clock_out timestamps from Supabase.
  // Falls back to the scheduled start/end times for shifts not yet clocked.

  String? get _displayStartTs {
    if (clockIn != null) return clockIn!.toIso8601String();
    if (shiftStartTime != null && shiftStartTime!.isNotEmpty) {
      return shiftStartTime;
    }
    return null;
  }

  String? get _displayEndTs {
    if (clockOut != null) return clockOut!.toIso8601String();
    if (shiftEndTime != null && shiftEndTime!.isNotEmpty) return shiftEndTime;
    return null;
  }

  /// Formatted date from clock_in timestamp.
  /// Example: "Friday, Mar 27, 2026" or "Today, Mar 27"
  String get clockFormattedDate {
    if (clockIn != null) {
      return ShiftDateHelpers.formatDate(clockIn!.toIso8601String());
    }
    if (date != null) {
      return ShiftDateHelpers.formatDateFromDateString(date);
    }
    if (shiftStartTime != null && shiftStartTime!.contains('T')) {
      return ShiftDateHelpers.formatDate(shiftStartTime);
    }
    return '';
  }

  /// Formatted time range from actual clock_in / clock_out.
  /// Example: "12:05 AM - 01:05 AM"
  String get clockFormattedTimeRange =>
      ShiftDateHelpers.formatTimeRange(_displayStartTs, _displayEndTs);

  /// Formatted duration from clock_in / clock_out.
  /// Example: "1h 0m"
  String get clockFormattedDuration =>
      ShiftDateHelpers.formatDuration(_displayStartTs, _displayEndTs);

  /// Combined time range + duration.
  /// Example: "12:05 AM - 01:05 AM (1h 0m)"
  String get clockFormattedTimeRangeWithDuration =>
      ShiftDateHelpers.formatTimeRangeWithDuration(
          _displayStartTs, _displayEndTs);

  /// Duration in decimal hours using actual clock_in/clock_out.
  /// Falls back to the old shiftStartTime/shiftEndTime calculation.
  double? get clockDurationHours {
    final h = ShiftDateHelpers.getDurationHours(_displayStartTs, _displayEndTs);
    return h ?? durationHours;
  }

  // Helper method to determine how active a shift is today
  // 3 = In progress
  // 2 = Starting soon (within 2 hours)
  // 1 = Just ended (within 4 hours)
  // 0 = Not currently active
  int get shiftTimeScore {
    final status = shiftStatus?.toLowerCase().replaceAll(' ', '_');
    if (status == 'clocked_in' ||
        status == 'active' ||
        status == 'in_progress') {
      return 100; // Found a physically live shift
    }

    if (shiftStartTime == null || shiftEndTime == null) return 0;
    try {
      final now = DateTime.now();

      // Parse current hour/min for comparison
      final currentTotalMinutes = now.hour * 60 + now.minute;

      // Use the robust _parseTimeAny which handles ISO8601 datetimes
      // (e.g. "2026-03-16T10:30:00") as well as plain time strings.
      int? timeToMinutes(String? timeStr) {
        final dt = _parseTimeAny(timeStr);
        if (dt == null) return null;
        return dt.hour * 60 + dt.minute;
      }

      final startTotalMinutes = timeToMinutes(shiftStartTime!);
      final endTotalMinutes = timeToMinutes(shiftEndTime!);

      if (startTotalMinutes == null || endTotalMinutes == null) return 0;

      // 1. Shift is currently in progress (active)
      if (currentTotalMinutes >= startTotalMinutes &&
          currentTotalMinutes <= endTotalMinutes) {
        return 3;
      }

      // 2. Shift is starting soon (within the next 2 hours)
      if (startTotalMinutes > currentTotalMinutes &&
          (startTotalMinutes - currentTotalMinutes) <= 120) {
        return 2;
      }

      // 3. Shift JUST ended (within the last 4 hours)
      if (currentTotalMinutes > endTotalMinutes &&
          (currentTotalMinutes - endTotalMinutes) <= 240) {
        return 1;
      }

      return 0;
    } catch (e) {
      debugPrint('Error calculating shiftTimeScore for $shiftStartTime: $e');
      return 0;
    }
  }

  bool get isActiveOrUpcoming => shiftTimeScore > 0;
}
