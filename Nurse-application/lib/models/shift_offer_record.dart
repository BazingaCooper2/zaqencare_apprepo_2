import 'package:intl/intl.dart';

/// Model for shift_offers table in Supabase
class ShiftOfferRecord {
  final int offersId;
  final int? empId;
  final int? clientId;
  final int? shiftId;
  final String? status; // pending, accepted, rejected, expired
  final DateTime? sentAt;
  final DateTime? responseTime;
  final int? offerOrder;

  // Joined details
  final String? shiftDate;
  final String? shiftStart;
  final String? shiftEnd;
  final String? clientFirstName;
  final String? clientLastName;
  final String? clientAddress;

  ShiftOfferRecord({
    required this.offersId,
    this.empId,
    this.clientId,
    this.shiftId,
    this.status,
    this.sentAt,
    this.responseTime,
    this.offerOrder,
    this.shiftDate,
    this.shiftStart,
    this.shiftEnd,
    this.clientFirstName,
    this.clientLastName,
    this.clientAddress,
  });

  /// Parse from Supabase JSON
  factory ShiftOfferRecord.fromJson(Map<String, dynamic> json) {
    // Extract nested shift data if available
    final shiftData = json['shift'] as Map<String, dynamic>?;
    final clientData = shiftData?['client'] as Map<String, dynamic>?;

    return ShiftOfferRecord(
      offersId: (json['offer_id'] as num?)?.toInt() ??
          (json['offers_id'] as num?)?.toInt() ??
          0,
      empId: (json['emp_id'] as num?)?.toInt(),
      clientId: (json['client_id'] as num?)?.toInt(),
      shiftId: (json['shift_id'] as num?)?.toInt(),
      status: json['status']?.toString(),
      sentAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : (json['sent_at'] != null
              ? DateTime.parse(json['sent_at'].toString())
              : null),
      responseTime: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'].toString())
          : (json['updated_at'] != null
              ? DateTime.parse(json['updated_at'].toString())
              : (json['response_time'] != null
                  ? DateTime.parse(json['response_time'].toString())
                  : null)),
      offerOrder: (json['offer_order'] as num?)?.toInt(),

      // Map joined fields
      shiftDate: shiftData?['date']?.toString(),
      shiftStart: shiftData?['shift_start_time']?.toString(),
      shiftEnd: shiftData?['shift_end_time']?.toString(),
      clientFirstName: clientData?['first_name']?.toString(),
      clientLastName: clientData?['last_name']?.toString(),
      clientAddress: clientData?['address']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'offer_id': offersId,
      'emp_id': empId,
      'client_id': clientId,
      'shift_id': shiftId,
      'status': status,
      'created_at': sentAt?.toIso8601String(),
      'updated_at': responseTime?.toIso8601String(),
      'offer_order': offerOrder,
      'shift_date': shiftDate,
      'shift_start': shiftStart,
      'shift_end': shiftEnd,
      'client_first_name': clientFirstName,
      'client_last_name': clientLastName,
      'client_address': clientAddress,
    };
  }

  /// Check if offer is still pending
  bool get isPending =>
      status?.toLowerCase() == 'pending' || status?.toLowerCase() == 'sent';

  /// Check if offer was accepted
  bool get isAccepted => status?.toLowerCase() == 'accepted';

  /// Check if offer was rejected
  bool get isRejected => status?.toLowerCase() == 'rejected';

  /// Check if offer expired
  bool get isExpired => status?.toLowerCase() == 'expired';

  /// Get formatted sent date/time
  String get formattedSentAt {
    if (sentAt == null) return 'Unknown';
    return DateFormat('MMM dd, yyyy hh:mm a').format(sentAt!);
  }

  /// Get formatted response time
  String get formattedResponseTime {
    if (responseTime == null) return 'N/A';
    return DateFormat('MMM dd, yyyy hh:mm a').format(responseTime!);
  }

  /// Get response time duration
  String get responseDuration {
    if (sentAt == null || responseTime == null) return 'N/A';
    final duration = responseTime!.difference(sentAt!);

    if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes}m';
    } else if (duration.inDays < 1) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    }
  }

  /// Get time since sent
  String get timeSinceSent {
    if (sentAt == null) return 'Unknown';
    final now = DateTime.now();
    final duration = now.difference(sentAt!);

    if (duration.inMinutes < 1) {
      return 'Just now';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes}m ago';
    } else if (duration.inDays < 1) {
      return '${duration.inHours}h ago';
    } else if (duration.inDays < 7) {
      return '${duration.inDays}d ago';
    } else {
      return DateFormat('MMM dd').format(sentAt!);
    }
  }

  /// Get status badge color
  String get statusColor {
    switch (status?.toLowerCase()) {
      case 'accepted':
        return 'green';
      case 'rejected':
        return 'red';
      case 'pending':
      case 'sent': // Treat sent as pending
        return 'orange';
      case 'expired':
        return 'grey';
      default:
        return 'blue';
    }
  }

  /// Get status display text
  String get statusDisplay {
    final s = status?.toUpperCase() ?? 'UNKNOWN';
    return s == 'SENT' ? 'PENDING' : s;
  }

  /// Get full client name
  String get clientName {
    if (clientFirstName == null && clientLastName == null) {
      return 'Unknown Client';
    }
    return '${clientFirstName ?? ''} ${clientLastName ?? ''}'.trim();
  }

  /// Get shift time display
  String get shiftTimeDisplay {
    if (shiftStart == null || shiftEnd == null) return 'Time not specified';
    return '$shiftStart - $shiftEnd';
  }
}
