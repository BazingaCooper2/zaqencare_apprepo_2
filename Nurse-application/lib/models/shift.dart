import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'client.dart';
import 'patient.dart';

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
      date: json['date']?.toString(),
      shiftType: json['shift_type']?.toString(),
      client: () {
        final clientData = json['client'];
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
    };
  }

  // Compatibility getters
  String? get clientName =>
      client?.name ??
      '${client?.firstName ?? ''} ${client?.lastName ?? ''}'.trim();
  String? get clientLocation => client?.fullAddress;
  String? get clientServiceType => client?.serviceType ?? client?.status;

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
  }) {
    return Shift(
      shiftId: shiftId ?? this.shiftId,
      clientId: clientId ?? this.clientId,
      empId: empId ?? this.empId,
      date: date ?? this.date,
      shiftStartTime: shiftStartTime ?? this.shiftStartTime,
      shiftEndTime: shiftEndTime ?? this.shiftEndTime,
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
    );
  }

  String get statusDisplayText {
    final normalized = shiftStatus?.toLowerCase().replaceAll(' ', '_');
    switch (normalized) {
      case 'scheduled':
        return 'Scheduled';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
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
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Helper method to parse various time formats
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

  // Helper method to calculate duration in hours
  double? get durationHours {
    final start = _parseTimeAny(shiftStartTime);
    final end = _parseTimeAny(shiftEndTime);

    if (start == null || end == null) return null;

    // If end is before start in time-only mode, mostly doesn't happen with full dates.
    // If it does (night shift), logic needs to handle date crossing, but usually full ISO handles it.
    final diff = end.difference(start);
    return diff.inMinutes / 60.0;
  }

  // Helper method to calculate overtime hours
  double? get overtimeHours {
    final duration = durationHours;
    if (duration == null) return null;
    return duration > 8 ? duration - 8 : 0;
  }

  // Helper method to convert 24hr time OR ISO time to 12hr AM/PM format
  static String formatTime12Hour(String? timeInput) {
    if (timeInput == null || timeInput.isEmpty) return '';

    try {
      final dateTime = _parseTimeAny(timeInput);
      if (dateTime != null) {
        return DateFormat('h:mm a').format(dateTime); // e.g. 2:45 PM
      }
      return timeInput;
    } catch (_) {
      return timeInput;
    }
  }

  // Get formatted start time (12-hour format)
  String get formattedStartTime => formatTime12Hour(shiftStartTime);

  // Get formatted end time (12-hour format)
  String get formattedEndTime => formatTime12Hour(shiftEndTime);

  // Get formatted time range (e.g., "9:00 AM - 5:00 PM")
  String get formattedTimeRange {
    if (shiftStartTime == null || shiftEndTime == null) {
      return 'Time not set';
    }
    return '$formattedStartTime - $formattedEndTime';
  }

  // Helper method to determine how active a shift is today
  // 3 = In progress
  // 2 = Starting soon (within 2 hours)
  // 1 = Just ended (within 4 hours)
  // 0 = Not currently active
  int get shiftTimeScore {
    if (shiftStartTime == null || shiftEndTime == null) return 0;
    try {
      final now = DateTime.now();

      // Parse current hour/min for comparison
      final currentTotalMinutes = now.hour * 60 + now.minute;

      int parseTimeString(String timeStr) {
        String cleanTime = timeStr.trim().toUpperCase();
        bool isPM = cleanTime.contains('PM');
        bool isAM = cleanTime.contains('AM');
        cleanTime = cleanTime.replaceAll(RegExp(r'[A-Z\s]'), '');

        final parts = cleanTime.split(':');
        int hours = int.parse(parts[0]);
        int minutes = int.parse(parts[1]);

        if (isPM && hours < 12) hours += 12;
        if (isAM && hours == 12) hours = 0;

        return hours * 60 + minutes;
      }

      final startTotalMinutes = parseTimeString(shiftStartTime!);
      final endTotalMinutes = parseTimeString(shiftEndTime!);

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
