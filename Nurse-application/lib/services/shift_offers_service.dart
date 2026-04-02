import 'package:flutter/foundation.dart';
import '../main.dart';
import '../models/shift_offer_record.dart';

/// Service for fetching shift offers from Supabase
class ShiftOffersService {
  /// Helper to manually fetch related data (Shift, Client) for offers
  static Future<List<ShiftOfferRecord>> _enrichOffers(
      List<Map<String, dynamic>> rawOffers) async {
    if (rawOffers.isEmpty) return [];

    try {
      // 1. Collect Shift IDs
      final shiftIds = rawOffers
          .map((o) => (o['shift_id'] as num?)?.toInt())
          .where((id) => id != null)
          .toSet()
          .toList();

      if (shiftIds.isEmpty) {
        return rawOffers
            .map((json) => ShiftOfferRecord.fromJson(json))
            .toList();
      }

      // 2. Fetch Shifts
      final shiftsResponse = await supabase.from('shift').select('''
            shift_id,
            emp_id,
            client_id,
            shift_status,
            shift_start_time,
            shift_end_time,
            start_ts,
            clock_in,
            clock_out,
            date,
            shift_type,
            task_id
          ''').filter('shift_id', 'in', '(${shiftIds.join(',')})');

      final shifts = List<Map<String, dynamic>>.from(shiftsResponse);
      final shiftMap = {
        for (var s in shifts) (s['shift_id'] as num).toInt(): s
      };

      // 3. Collect distinct Client IDs safely
      final Set<int> clientIds = {};
      for (final s in shifts) {
        final cidRaw = s['client_id'];
        if (cidRaw != null) {
          int? parsedCid;
          if (cidRaw is num) {
            parsedCid = cidRaw.toInt();
          } else if (cidRaw is String) parsedCid = int.tryParse(cidRaw);
          if (parsedCid != null) clientIds.add(parsedCid);
        }
      }

      // 4. Fetch Client Data
      Map<int, Map<String, dynamic>> clientsMap = {};
      if (clientIds.isNotEmpty) {
        try {
          final clientsResponse = await supabase
              .from('client_final')
              .select()
              .inFilter('id', clientIds.toList());
          for (final c in clientsResponse) {
            final cid = (c['id'] as num).toInt();
            clientsMap[cid] = Map<String, dynamic>.from(c);
          }
        } catch (e) {
          debugPrint('⚠️ Error enriching clients in offers: $e');
        }
      }

      // 5. Construct ShiftOfferRecords
      return rawOffers.map((offerJson) {
        final json =
            Map<String, dynamic>.from(offerJson); // Be safe with offer maps
        final shiftId = (json['shift_id'] as num?)?.toInt();
        final shiftData = shiftMap[shiftId];

        Map<String, dynamic>? clientData;
        if (shiftData != null) {
          final cidRaw = shiftData['client_id'];
          int? parsedCid;
          if (cidRaw is num) {
            parsedCid = cidRaw.toInt();
          } else if (cidRaw is String) parsedCid = int.tryParse(cidRaw);
          if (parsedCid != null) {
            clientData = clientsMap[parsedCid];
          }
        }

        // Parse base offer
        final baseOffer = ShiftOfferRecord.fromJson(json);

        // Return new instance with enriched data
        return ShiftOfferRecord(
          offersId: baseOffer.offersId,
          empId: baseOffer.empId,
          clientId: baseOffer
              .clientId, // This might differ from shift client, but usually same
          shiftId: baseOffer.shiftId,
          status: baseOffer.status,
          sentAt: baseOffer.sentAt,
          responseTime: baseOffer.responseTime,
          offerOrder: baseOffer.offerOrder,

          // Enriched fields
          shiftDate: shiftData?['date'] as String?,
          shiftStart: shiftData?['shift_start_time'] as String?,
          shiftEnd: shiftData?['shift_end_time'] as String?,
          clientFirstName: clientData?['first_name'] as String?,
          clientLastName: clientData?['last_name'] as String?,
          clientAddress: clientData?['address'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ Error enriching offers: $e');
      // Fallback to basic data
      return rawOffers.map((json) => ShiftOfferRecord.fromJson(json)).toList();
    }
  }

  /// Fetch all offers for an employee
  static Future<List<ShiftOfferRecord>> fetchAllOffers(int empId) async {
    try {
      debugPrint('📥 Fetching all offers for employee $empId');

      final response = await supabase
          .from('shift_offers')
          .select()
          .eq('emp_id', empId)
          .order('created_at', ascending: false);

      debugPrint('🔍 Raw response length for emp $empId: ${response.length}');
      if (response.isNotEmpty) {
        debugPrint('🔍 First offer status: ${response[0]['status']}');
        debugPrint('🔍 First offer ID: ${response[0]['offer_id']}');
      }

      final offers =
          await _enrichOffers(List<Map<String, dynamic>>.from(response));

      debugPrint('✅ Fetched ${offers.length} enriched offers');
      return offers;
    } catch (e) {
      debugPrint('❌ Error fetching all offers: $e');
      return [];
    }
  }

  /// Fetch pending offers only
  static Future<List<ShiftOfferRecord>> fetchPendingOffers(int empId) async {
    try {
      debugPrint('📥 Fetching pending offers for employee $empId with filter');

      final response = await supabase
          .from('shift_offers')
          .select()
          .eq('emp_id', empId)
          .filter('status', 'in', '("pending","sent")')
          .order('created_at', ascending: false);

      debugPrint('🔍 Raw PENDING response length: ${response.length}');

      final offers =
          await _enrichOffers(List<Map<String, dynamic>>.from(response));

      debugPrint('✅ Fetched ${offers.length} pending enriched offers');
      return offers;
    } catch (e) {
      debugPrint('❌ Error fetching pending offers: $e');
      return [];
    }
  }

  /// Fetch accepted offers
  static Future<List<ShiftOfferRecord>> fetchAcceptedOffers(int empId) async {
    try {
      debugPrint('📥 Fetching accepted offers for employee $empId');

      final response = await supabase
          .from('shift_offers')
          .select()
          .eq('emp_id', empId)
          .eq('status', 'accepted')
          .order('created_at', ascending: false);

      final offers =
          await _enrichOffers(List<Map<String, dynamic>>.from(response));

      debugPrint('✅ Fetched ${offers.length} accepted offers');
      return offers;
    } catch (e) {
      debugPrint('❌ Error fetching accepted offers: $e');
      return [];
    }
  }

  /// Fetch rejected offers
  static Future<List<ShiftOfferRecord>> fetchRejectedOffers(int empId) async {
    try {
      debugPrint('📥 Fetching rejected offers for employee $empId');

      final response = await supabase
          .from('shift_offers')
          .select()
          .eq('emp_id', empId)
          .eq('status', 'rejected')
          .order('created_at', ascending: false);

      final offers =
          await _enrichOffers(List<Map<String, dynamic>>.from(response));

      debugPrint('✅ Fetched ${offers.length} rejected offers');
      return offers;
    } catch (e) {
      debugPrint('❌ Error fetching rejected offers: $e');
      return [];
    }
  }

  /// Update offer status
  static Future<bool> updateOfferStatus({
    required int offersId,
    required String status,
    int? shiftId,
    int? empId,
  }) async {
    try {
      debugPrint('📤 Updating offer $offersId to status: $status');

      // 1. Update the offer status
      final updateData = {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (status == 'accepted') {
        updateData['accepted_at'] = DateTime.now().toIso8601String();
      }

      await supabase
          .from('shift_offers')
          .update(updateData)
          .eq('offer_id', offersId);

      // 2. If accepted, update the actual shift to assign the employee
      if (status == 'accepted' && shiftId != null && empId != null) {
        debugPrint('🔗 Assigning shift $shiftId to employee $empId');
        await supabase.from('shift').update({
          'emp_id': empId,
          'shift_status':
              'Scheduled', // Assuming 'Scheduled' is the active status
        }).eq('shift_id', shiftId);
      }

      debugPrint('✅ Offer status updated');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating offer status: $e');
      return false;
    }
  }

  /// Get offer count by status
  static Future<Map<String, int>> getOfferCounts(int empId) async {
    try {
      final allOffers = await fetchAllOffers(empId);

      return {
        'total': allOffers.length,
        'pending': allOffers
            .where((o) =>
                o.status?.toLowerCase() == 'pending' ||
                o.status?.toLowerCase() == 'sent')
            .length,
        'accepted': allOffers.where((o) => o.isAccepted).length,
        'rejected': allOffers.where((o) => o.isRejected).length,
        'expired': allOffers.where((o) => o.isExpired).length,
      };
    } catch (e) {
      debugPrint('❌ Error getting offer counts: $e');
      return {
        'total': 0,
        'pending': 0,
        'accepted': 0,
        'rejected': 0,
        'expired': 0,
      };
    }
  }

  /// Get acceptance rate (percentage)
  static Future<double> getAcceptanceRate(int empId) async {
    try {
      final counts = await getOfferCounts(empId);
      final total = counts['total']! - counts['pending']!; // Exclude pending

      if (total == 0) return 0.0;

      return (counts['accepted']! / total) * 100;
    } catch (e) {
      debugPrint('❌ Error calculating acceptance rate: $e');
      return 0.0;
    }
  }

  /// Fetch a single offer by ID (enriched)
  static Future<ShiftOfferRecord?> fetchOffer(int offersId) async {
    try {
      final response = await supabase
          .from('shift_offers')
          .select()
          .eq('offer_id', offersId)
          .maybeSingle();

      if (response == null) return null;

      final enriched =
          await _enrichOffers([Map<String, dynamic>.from(response)]);
      if (enriched.isNotEmpty) {
        return enriched.first;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching single offer: $e');
      return null;
    }
  }
}
