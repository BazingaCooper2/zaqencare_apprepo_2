import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import 'package:nurse_tracking_app/models/employee.dart';
import 'package:nurse_tracking_app/models/shift.dart';
import 'package:nurse_tracking_app/models/client.dart';
import 'package:nurse_tracking_app/models/task_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nurse_tracking_app/services/session.dart';
import 'package:nurse_tracking_app/services/directions_service.dart';
import 'package:nurse_tracking_app/config/api_config.dart';
import '../constants/tables.dart';

class TimeTrackingPage extends StatefulWidget {
  final Employee employee;
  final String? scheduleId;

  const TimeTrackingPage({super.key, required this.employee, this.scheduleId});

  @override
  State<TimeTrackingPage> createState() => _TimeTrackingPageState();
}

class _TimeTrackingPageState extends State<TimeTrackingPage> {
  // Location and tracking state
  Position? _currentPosition;
  String? _currentAddress;
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionSubscription;

  // Clock-in/out state
  bool _isClockedIn = false;
  String? _currentPlaceName;
  String? _currentLogId;
  DateTime? _clockInTimeUtc;

  // Map state
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};
  bool _hasCenteredOnUser = false;

  // Active shift and client state (Authoritative Source of Truth)
  Shift? _activeShift;
  Client? _activeClient;
  bool _loadingActiveShift = false;
  List<Shift> _todayShifts = []; // New list for today's shifts

  // Geocoded coordinates for the active client's address.
  // client_final has no lat/lng column — coords are fetched via backend.
  List<double>? _geocodedClientLatLng; // [lat, lng]

  // Task state
  List<Task> _tasks = [];
  bool _loadingTasks = false;
  StreamSubscription? _tasksRealtimeSubscription;
  StreamSubscription?
      _shiftRealtimeSubscription; // Added to prevent memory leak

  // Manual clock in/out state
  bool _manualClockingIn = false;
  bool _manualClockingOut = false;

  // Route state
  String? _routeDistance;
  String? _routeDuration;
  int? _subscribedShiftId; // NEW: To prevent redundant streams loop

  // Assisted-Living locations with 50m geofence
  static const Map<String, LatLng> _locations = {
    'Willow Place': LatLng(43.538165, -80.311467),
    '85 Neeve': LatLng(43.536884, -80.307129),
    '87 Neeve': LatLng(43.536732, -80.307545),
  };

  static const double _geofenceRadius = 50.0; // meters

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. Check for existing session and restore it (PRIORITY)
    await _checkActiveClockInStatus();

    // 2. If no active session restored, load the next schedule
    if (_activeShift == null) {
      await _loadActiveShift();
    }

    // 3. Request location permission (might show dialog)
    await _requestLocationPermission();

    // 4. Setup map based on whatever client we found
    _setupMapMarkersAndCircles();
  }

  Future<void> _checkActiveClockInStatus() async {
    try {
      final empId = await SessionManager.getEmpId();
      if (empId == null) return;

      // 1. Direct Query on 'shift' table (User's specific request for session restoration)
      // This ensures we find the active shift even if it started on a different day.
      final activeShiftData = await supabase
          .from('shift')
          .select('*, client(*)')
          .eq('emp_id', empId)
          .not('clock_in', 'is', null)
          .filter('clock_out', 'is', null)
          .order('clock_in', ascending: false)
          .limit(1)
          .maybeSingle();

      if (activeShiftData != null && mounted) {
        final shift = Shift.fromJson(activeShiftData);

        // 2. Find corresponding time_log to restore _currentLogId for clock-out
        final logResponse = await supabase
            .from('time_logs')
            .select('id, clock_in_time')
            .eq('emp_id', empId)
            .eq('shift_id', shift.shiftId)
            .filter('clock_out_time', 'is', null)
            .maybeSingle();

        setState(() {
          _activeShift = shift;
          _isClockedIn = true;
          _clockInTimeUtc = shift.clockIn;
          if (logResponse != null) {
            _currentLogId = logResponse['id'].toString();
            _clockInTimeUtc = DateTime.parse(logResponse['clock_in_time']);
          }
        });

        await _loadClientAndTasksForActiveShift();
        _currentPlaceName = _activeClient?.fullName ?? 'Work Location';
        debugPrint('Restored active shift ${shift.shiftId} (Log: $_currentLogId)');
      } else {
        // Fallback: Check time_logs if shift table didn't have the explicit clock_in/out
        final response = await supabase
            .from('time_logs')
            .select('*, shift(*, client(*))')
            .eq('emp_id', empId)
            .filter('clock_out_time', 'is', null)
            .maybeSingle();

        if (response != null && mounted) {
          final log = response;
          setState(() {
            _isClockedIn = true;
            _currentLogId = log['id'].toString();
            _clockInTimeUtc = DateTime.parse(log['clock_in_time']);
            if (log['shift'] != null) {
              _activeShift = Shift.fromJson(log['shift']);
            }
          });
          await _loadClientAndTasksForActiveShift();
          _currentPlaceName = _activeClient?.fullName ?? 'Work Location';
          debugPrint('Restored session via time_logs: ${_activeShift?.shiftId}');
        }
      }
    } catch (e) {
      debugPrint('Restore session error: $e');
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _positionSubscription?.cancel();
    _tasksRealtimeSubscription?.cancel();
    _shiftRealtimeSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<List<Shift>> fetchTodayShifts(int empId) async {
    debugPrint('🚨 Fetching shifts for emp_id=$empId');
    try {
      final now = DateTime.now();
      final todayStr = now.toIso8601String().substring(0, 10);
      
      // BROAD FETCH: match all across time to ensure timezone safety
      // Using explicit alias 'client:client_final(*)' to match Shift model expectations
      final response = await supabase
          .from('shift')
          .select('*, client:client_final(*)')
          .eq('emp_id', empId)
          .or('shift_mode.eq.individual,parent_block_id.not.is.null');

      debugPrint('📅 Found ${response.length} shift(s) (with client details) for emp $empId');

      if (response.isEmpty) {
        debugPrint('⚠️ No assigned individual/child shifts found for emp $empId at all.');
        return [];
      }

      final allShifts = (response as List)
          .map((s) => Shift.fromJson(s))
          .toList();

      // Use LOCAL date string filtering to identify today's assignments
      final todayShifts = allShifts.where((s) {
        final rawDate = s.date ?? '';
        if (rawDate.isEmpty) return false;
        
        // Match string-wise (YYYY-MM-DD vs YYYY-MM-DD)
        final shiftDateStr = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
        final isMatch = shiftDateStr == todayStr;
        
        debugPrint('🔍 Shift ${s.shiftId} | DB Date: "$rawDate" (Short: $shiftDateStr) | Today: $todayStr | Match: $isMatch');
        
        return isMatch;
      }).toList();

      debugPrint('✅ Filtered to ${todayShifts.length} shift(s) for TODAY across ${allShifts.length} total shifts');
      return todayShifts;
    } catch (e) {
      debugPrint('❌ Error fetching shifts in TimeTrackingPage: $e');
      return [];
    }
  }

  Future<void> _loadActiveShift() async {
    if (_loadingActiveShift) return;

    setState(() {
      _loadingActiveShift = true;
    });

    try {
      final empId = await SessionManager.getEmpId();
      if (empId == null) {
        setState(() {
          _loadingActiveShift = false;
        });
        return;
      }

      // 1. Fetch active shift via RPC first (in case clocked in to an older shift).
      Shift? activeRpcShift;
      try {
        final rpcResponse =
            await supabase.rpc('get_active_shift', params: {'p_emp_id': empId});
        if (rpcResponse != null &&
            rpcResponse is List &&
            rpcResponse.isNotEmpty) {
          activeRpcShift = Shift.fromJson(rpcResponse.first);
        } else if (rpcResponse is Map) {
          activeRpcShift = Shift.fromJson(rpcResponse as Map<String, dynamic>);
        }
        debugPrint(
            '🔥 RPC get_active_shift returned: ${activeRpcShift?.shiftId}');
      } catch (rpcErr) {
        debugPrint('⚠️ get_active_shift RPC failed (non-fatal): $rpcErr');
      }

      // 2. If scheduleId is passed, use that as the target instead of all today's shifts
      Shift? targetShift;
      if (widget.scheduleId != null) {
          final sResp = await supabase.from('shift').select('*, client:client_final(*)').eq('shift_id', widget.scheduleId!).maybeSingle();
          if (sResp != null) {
              targetShift = Shift.fromJson(sResp);
          }
      }
      
      Shift? currentlyClockedInShift;
      if (activeRpcShift != null) {
        final st =
            activeRpcShift.shiftStatus?.toLowerCase().replaceAll(' ', '_');
        if (st == 'clocked_in' || st == 'active' || st == 'in_progress') {
          currentlyClockedInShift = activeRpcShift;
        }
      }

      if (currentlyClockedInShift != null) {
        _todayShifts = [currentlyClockedInShift];
        _activeShift = currentlyClockedInShift;
        _isClockedIn = true;
      } else {
        if (targetShift != null) {
           _todayShifts = [targetShift];
           _activeShift = targetShift;
        } else {
           _activeShift = null;
           _todayShifts = [];
        }
      }
      
      // Update UI immediately while secondary data (clients/tasks) loads
      if (mounted) {
        setState(() {});
      }

      await _loadClientAndTasksForActiveShift();
    } catch (e) {
      debugPrint('❌ Error loading shifts: $e');
      if (mounted) {
        setState(() {
          _loadingActiveShift = false;
        });
      }
    }
  }

  Future<void> _loadClientAndTasksForActiveShift() async {
    final shift = _activeShift;
    if (shift == null) {
      setState(() {
        _activeClient = null;
        _loadingActiveShift = false;
      });
      return;
    }

    try {
      Client? client = shift.client;
      if (client == null && shift.clientId != null) {
        final clientResponse = await supabase
            .from(Tables.client)
            .select('*')
            .eq('id', shift.clientId!) // Match client_final.id
            .limit(1);
        if (clientResponse.isNotEmpty) {
          client = Client.fromJson(clientResponse.first);
        }
      }

      if (client != null && client.fullAddress.isNotEmpty) {
        _fetchCoordinatesFromBackend(client.fullAddress).then((coords) {
          if (coords != null && mounted) {
            setState(() {
              _geocodedClientLatLng = [
                (coords['latitude'] as num).toDouble(),
                (coords['longitude'] as num).toDouble()
              ];
            });
            _setupMapMarkersAndCircles();
          }
        });
      }

      setState(() {
        _activeClient = client;
        _loadingActiveShift = false;
        final status = shift.shiftStatus?.toLowerCase().replaceAll(' ', '_');
        if (status == 'clocked_in' ||
            status == 'active' ||
            status == 'in_progress') {
          _isClockedIn = true;
          if (shift.clockIn != null && _clockInTimeUtc == null) {
            _clockInTimeUtc = shift.clockIn;
          }
        }
      });
      _setupMapMarkersAndCircles();

      if (_currentPosition != null && client != null) {
        _updateRouteToClient();
      }

      // OPTIMIZATION: Only (re)subscribe if the shift has actually changed
      if (_subscribedShiftId != shift.shiftId) {
        debugPrint('🔗 Initializing Realtime Subscriptions for shift ${shift.shiftId}');
        
        // Listen for task changes in real-time (Dynamic Task Updates)
        _tasksRealtimeSubscription?.cancel();
        _tasksRealtimeSubscription = supabase
            .from('shift_task_log')
            .stream(primaryKey: ['shift_id', 'order_index'])
            .eq('shift_id', shift.shiftId)
            .listen((_) => _loadTasks());

        // REALTIME SHIFT UPDATES
        _shiftRealtimeSubscription?.cancel();
        _shiftRealtimeSubscription = supabase
            .from('shift')
            .stream(primaryKey: ['shift_id'])
            .eq('shift_id', shift.shiftId)
            .listen((data) {
          // If we are already loading, ignore stream updates to prevent recursive loops
          if (_loadingActiveShift) return;
          
          debugPrint('🔄 Shift update received from Realtime Stream for ${shift.shiftId}');
          _loadActiveShift();
        });
        
        _subscribedShiftId = shift.shiftId;
      }
    } catch (e) {
      debugPrint('❌ Error loading active shift specifics: $e');
      setState(() {
        _loadingActiveShift = false;
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('🔐 Current location permission: $permission');

    // If permission is denied, request it
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('🔐 Requested permission result: $permission');
    }

    // Check if still denied or denied forever
    if (permission == LocationPermission.denied) {
      debugPrint('❌ Location permission denied');
      _showSnackBar('Location permission denied', isError: true);
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Location permission denied forever');
      _showSnackBar(
          'Location permission denied forever. Please enable in settings.',
          isError: true);
      return;
    }

    // Permission is granted (whileInUse or always)
    debugPrint('✅ Location permission granted: $permission');
    _startLocationPolling();
  }

  void _startLocationPolling() {
    // Use a continuous position stream for real-time, accurate location
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Only fire when moved ≥5 meters
      intervalDuration: const Duration(seconds: 5),
      forceLocationManager:
          true, // Use LocationManager for more reliable updates
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        debugPrint(
            '📍 Location stream: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');

        if (!mounted) return;

        setState(() {
          _currentPosition = position;
        });

        // Update address in background if not already set — never block the stream
        if (_currentAddress == null) {
          _reverseGeocode(position.latitude, position.longitude)
              .then((addr) => _currentAddress ??= addr);
        }

        // Center camera on user location first time
        if (!_hasCenteredOnUser && _mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(position.latitude, position.longitude),
              16,
            ),
          );
          _hasCenteredOnUser = true;
          debugPrint('🎯 Centered map on user location');
        }

        // Check for geofence entry at assisted living locations
        await _checkGeofenceEntry(position);

        // Update map markers
        _updateMapMarkers();
      },
      onError: (error) {
        debugPrint('❌ Location stream error: $error');
      },
    );
    // NOTE: No redundant _updateLocation() call here — the stream fires immediately.
  }

  Future<void> _checkGeofenceEntry(Position position) async {
    // 1. Check if we are inside ANY monitored location
    String? detectedPlace;
    double? distToPlace;

    // Check dynamic client location (Active Shift)
    if (_activeClient != null) {
      // Use geocoded coords from state (client_final has no lat/lng column)
      final coords = _geocodedClientLatLng;
      if (coords != null && coords.length >= 2) {
        final clientLat = coords[0];
        final clientLng = coords[1];
        final dist = _calculateDistance(
            position.latitude, position.longitude, clientLat, clientLng);

        if (dist <= _geofenceRadius) {
          // Use client name as the detected place
          detectedPlace = _activeClient!.fullName;
          distToPlace = dist;
          debugPrint(
              '🎯 Match found: ${_activeClient!.fullName} (Shift Client)');
        }
      }
    }

    // B. SECONDARY: Check static assisted living locations (ONLY if not already matched)
    if (detectedPlace == null) {
      for (final entry in _locations.entries) {
        final placeName = entry.key;
        final location = entry.value;

        final distance = _calculateDistance(
          position.latitude,
          position.longitude,
          location.latitude,
          location.longitude,
        );

        if (distance <= _geofenceRadius) {
          detectedPlace = placeName;
          distToPlace = distance;
          debugPrint('🎯 Match found: $placeName (Static Location)');
          break;
        }
      }
    }

    // 2. Logic Control
    if (detectedPlace != null) {
      // ✅ INSIDE A GEOFENCE
      if (!_isClockedIn) {
        // Not clocked in? -> Auto Clock IN
        debugPrint(
            '📍 Entered $detectedPlace ($distToPlace m). Auto Clocking In...');
        await _autoClockIn(detectedPlace, position);
      } else {
        // Already clocked in.
        // Optional: switch location if they moved from Place A to Place B instantly (rare)
        if (_currentPlaceName != detectedPlace) {
          debugPrint(
              '📍 Changed location from $_currentPlaceName to $detectedPlace. Updating...');
          // For now, assume they are just "working". We could update the log, but simpler to leave as is.
        }
      }
    } else {
      // ❌ OUTSIDE ALL GEOFENCES
      if (_isClockedIn) {
        // We are clocked in, but now outside.
        // Apply a small "exit buffer" to prevent jitter (e.g. GPS drift at the edge)
        // Check distance to the place we are supposedly clocked in at
        bool confirmedOutside = true;
        double? targetLat, targetLng;

        if (_currentPlaceName != null) {
          // Check static locations
          if (_locations.containsKey(_currentPlaceName)) {
            targetLat = _locations[_currentPlaceName]!.latitude;
            targetLng = _locations[_currentPlaceName]!.longitude;
          }
          // Check dynamic client location (match loosely by name or if we just assume current client)
          else if (_activeClient != null) {
            // If the current place name matches service type or client name
            final sType = _activeClient!.serviceType ?? '';
            final cName = _activeClient!.fullName;

            if (_currentPlaceName == sType || _currentPlaceName == cName) {
              // Use geocoded coords from state
              final coords = _geocodedClientLatLng;
              if (coords != null && coords.length >= 2) {
                targetLat = coords[0];
                targetLng = coords[1];
              }
            }
          }
        }

        if (targetLat != null && targetLng != null) {
          final dist = _calculateDistance(
              position.latitude, position.longitude, targetLat, targetLng);

          // Buffer: Geofence Radius + 20 meters.
          if (dist <= _geofenceRadius + 20) {
            confirmedOutside = false;
          }
        } else {
          // Should we clock out if we can't verify location?
          // Probably yes, but safer to assume we are "lost" rather than "left".
          // However, for strict geofencing, if we don't know where we are supposed to be, maybe we shouldn't have clocked in.
        }

        if (confirmedOutside && targetLat != null) {
          debugPrint('📍 Exited $_currentPlaceName. Auto Clocking Out...');
          _showSnackBar('📍 Exited geofence. Auto Clocking Out...');
          await _autoClockOut(position);
        }
      }
    }
  }

  Future<void> _updateRouteToClient() async {
    if (_activeClient == null) return;

    // Use geocoded coords stored in state
    final coordinates = _geocodedClientLatLng;

    if (coordinates == null || coordinates.length < 2) return;

    // Only try backend route if we have positions.
    // This function will NOT launch external maps automatically.
    if (_currentPosition == null) return;

    final destinationLat = coordinates[0];
    final destinationLng = coordinates[1];

    try {
      final directionsService = DirectionsService();
      final result = await directionsService.getDirections(
        origin: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        destination: LatLng(destinationLat, destinationLng),
      );

      if (result != null) {
        // Decode polyline points
        final points = _decodePolyline(result.polylineEncoded);

        setState(() {
          _routeDistance = result.distance;
          _routeDuration = result.duration;

          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route_to_client'),
              points: points,
              color: Colors.blue,
              width: 5,
              geodesic: true,
            ),
          );
        });

        // Update camera to show both locations if we have a valid route
        if (_mapController != null && points.isNotEmpty) {
          // Optional: Only move camera if user explicitly requested route or on first load
          // For now, we update the bounds to make sure the route is visible
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              _boundsFromLatLngList([
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                LatLng(destinationLat, destinationLng),
              ]),
              100.0,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating route: $e');
    }
  }

  Future<void> _launchExternalMaps() async {
    if (_activeClient == null) return;

    final coordinates = _geocodedClientLatLng; // Use geocoded state
    String url;

    if (coordinates != null && coordinates.length >= 2) {
      // Use geocoded coordinates
      url =
          'https://www.google.com/maps/dir/?api=1&destination=${coordinates[0]},${coordinates[1]}';
    } else if (_activeClient!.fullAddress.isNotEmpty) {
      // Use address
      final encodedAddress = Uri.encodeComponent(_activeClient!.fullAddress);
      url =
          'https://www.google.com/maps/dir/?api=1&destination=$encodedAddress';
    } else {
      _showSnackBar('No location data available for directions.',
          isError: true);
      return;
    }

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      _showSnackBar('Could not launch maps.', isError: true);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0;
    final int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return poly;
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double? x0, x1, y0, y1;
    for (final LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(
      southwest: LatLng(x0 ?? 0, y0 ?? 0),
      northeast: LatLng(x1 ?? 0, y1 ?? 0),
    );
  }

  bool _permissionDenied = false;

  Future<void> _autoClockIn(String placeName, Position position) async {
    if (_permissionDenied) return;

    if (_currentLogId != null) {
      debugPrint('⚠️ Already clocked in. Skipping duplicate clock-in.');
      return;
    }

    if (_activeShift == null) {
      debugPrint('❌ Cannot clock in: active shift is NULL');
      return;
    }

    if (supabase.auth.currentUser == null) {
      _showSnackBar('Please log in again.', isError: true);
      return;
    }

    try {
      final nowUtc = DateTime.now().toUtc();
      final lat = double.parse(position.latitude.toStringAsFixed(8));
      final lng = double.parse(position.longitude.toStringAsFixed(8));

      String clockInAddress =
          '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

      try {
        clockInAddress =
            await _reverseGeocode(position.latitude, position.longitude)
                .timeout(const Duration(seconds: 3));
      } catch (_) {}

      final empId = await SessionManager.getEmpId();
      if (empId == null) return;

      final response = await supabase.from('time_logs').insert({
        'emp_id': empId,
        'shift_id': _activeShift?.shiftId, // VERY IMPORTANT
        'clock_in_time': nowUtc.toIso8601String(),
        'clock_in_latitude': lat,
        'clock_in_longitude': lng,
        'clock_in_address': clockInAddress,
        'updated_at': nowUtc.toIso8601String(),
      }).select('id');

      if (response.isNotEmpty) {
        if (_activeShift != null) {
          await supabase.from('shift').update({
            'clock_in': nowUtc.toIso8601String(),
            'shift_status': 'clocked_in'
          }).eq('shift_id', _activeShift!.shiftId);
        }

        setState(() {
          _isClockedIn = true;
          _currentPlaceName = placeName;
          _currentLogId = response.first['id'].toString();
          _clockInTimeUtc = nowUtc;
        });

        _showSnackBar('Auto Clocked IN');
      }
    } catch (e) {
      debugPrint('Clock-in error: $e');
      _showSnackBar('Clock-in failed. Retrying...', isError: true);

      await Future.delayed(const Duration(seconds: 5));

      if (!_isClockedIn && _currentPosition != null) {
        await _autoClockIn(placeName, _currentPosition!);
      }
    }
  }

  void _showPermissionErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Permission Denied'),
        content: const Text(
            'The Supabase Database blocked this request (RLS Policy).\n\n'
            'FASTEST FIX:\n'
            '1. Go to Supabase Dashboard > Table Editor > "time_logs"\n'
            '2. Click "RLS" or "Active" in the toolbar\n'
            '3. Click "Disable RLS"\n\n'
            'Then restart the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Persists all current tasks into the `shift_tasks` table on clock-out.
  /// Uses upsert with conflict on (shift_id, task_id) for real tasks,
  /// and insert for temporary/local tasks (which have no task_id FK).
  Future<void> _finalizeShiftTasks(int shiftId, int empId) async {
    if (_tasks.isEmpty) return;

    try {
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      for (final task in _tasks) {
        final finalStatus = task.shiftTaskLogStatus ??
            (task.status ? 'completed' : 'pending');
        final isCompleted = finalStatus == 'completed';
        final isTemporary = task.isLocal;
        final taskName = task.details ?? 'Task';

        final row = <String, dynamic>{
          'shift_id': shiftId,
          'task_name': taskName,
          'is_temporary': isTemporary,
          'status': finalStatus,
          'skip_reason': task.skipReason,
          'completed_at': isCompleted ? nowUtc : null,
          'completed_by': isCompleted ? empId : null,
        };

        if (!isTemporary && !task.isFromClient && task.taskId > 0) {
          row['task_id'] = task.taskId;
        }

        try {
          if (row.containsKey('task_id')) {
            await supabase
                .from('shift_tasks')
                .upsert(row, onConflict: 'shift_id, task_id');
          } else {
             // Look for existing by name to prevent duplicates if task_id isn't provided
             final existing = await supabase.from('shift_tasks')
                .select('shift_task_id')
                .eq('shift_id', shiftId)
                .eq('task_name', taskName)
                .maybeSingle();
             if (existing != null) {
                await supabase.from('shift_tasks').update(row).eq('shift_task_id', existing['shift_task_id']);
             } else {
                await supabase.from('shift_tasks').insert(row);
             }
          }
        } catch (dbErr) {
          // If upsert fails because of care_plan_tasks foreign key violation or other constraint
          row.remove('task_id');
          final existing = await supabase.from('shift_tasks')
               .select('shift_task_id')
               .eq('shift_id', shiftId)
               .eq('task_name', taskName)
               .maybeSingle();           
          if (existing != null) {
             await supabase.from('shift_tasks').update(row).eq('shift_task_id', existing['shift_task_id']);
          } else {
             await supabase.from('shift_tasks').insert(row);
          }
        }
      }

      debugPrint(
          '✅ _finalizeShiftTasks: wrote ${_tasks.length} task(s) to shift_tasks for shift $shiftId');
    } catch (e) {
      // Non-fatal — log and continue so clock-out itself is never blocked
      debugPrint('⚠️ _finalizeShiftTasks error (non-fatal): $e');
    }
  }

  Future<void> _autoClockOut(Position position) async {
    if (_currentLogId == null || _permissionDenied) return;

    // ── TASK COMPLETION CHECK ────────────────────────────────────────────────
    // Requirement: Don't clock out until all tasks are done or skipped.
    if (!_allTasksCompleted) {
      debugPrint('📍 Auto-Clock Out blocked: Tasks still pending.');
      _showSnackBar(
          '📍 You left the geofence but tasks are still pending. Please complete them to clock out.',
          isError: true);
      return;
    }

    try {
      final nowUtc = DateTime.now().toUtc();
      final lat = double.parse(position.latitude.toStringAsFixed(8));
      final lng = double.parse(position.longitude.toStringAsFixed(8));

      // Reverse-geocode in parallel — don't block the clock-out DB write.
      String clockOutAddress =
          '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
      try {
        clockOutAddress =
            await _reverseGeocode(position.latitude, position.longitude)
                .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Timeout or error — address stays as lat/lng fallback
      }

      final totalHours = _clockInTimeUtc != null
          ? ((nowUtc.difference(_clockInTimeUtc!).inMinutes) / 60.0)
          : 0.0;

      final update = supabase.from('time_logs').update({
        'clock_out_time': nowUtc.toIso8601String(),
        'clock_out_latitude': lat,
        'clock_out_longitude': lng,
        'clock_out_address': clockOutAddress,
        'total_hours': double.parse(totalHours.toStringAsFixed(2)),
        'updated_at': nowUtc.toIso8601String(),
      }).eq('id', _currentLogId!);

      await update;

      // Also update the shift table if we have an active shift
      if (_activeShift != null) {
        try {
          await supabase.from('shift').update({
            'clock_out': nowUtc.toIso8601String(),
            'shift_status': 'clocked_out'
          }).eq('shift_id', _activeShift!.shiftId);
          debugPrint(
              '✅ Updated shift table with clock_out time and completed status');
        } catch (e) {
          debugPrint('⚠️ Failed to update shift table clock_out: $e');
        }

        // Persist final task outcomes to shift_tasks table
        final empId = await SessionManager.getEmpId();
        if (empId != null) {
          await _finalizeShiftTasks(_activeShift!.shiftId, empId);
        }
      }

      final placeName = _currentPlaceName ?? 'Location';
      _showSnackBar(
          '👋 Left $placeName. Auto Clocked OUT. (${totalHours.toStringAsFixed(2)} hrs)');

      setState(() {
        _isClockedIn = false;
        _currentLogId = null;
        _currentPlaceName = null;
        _clockInTimeUtc = null;
      });

      // Refresh to load next shift after completing current one
      _loadActiveShift();
    } catch (e) {
      if (e.toString().contains('42501') || e.toString().contains('policy')) {
        _showSnackBar('⚠️ Database Permission Error (Check RLS Policies)',
            isError: true);
      } else if (e.toString().contains('SocketException') ||
          e.toString().contains('host lookup')) {
        _showSnackBar(
            '⚠️ Internet lost during clock-out. Please check connection.',
            isError: true);
      } else {
        _showSnackBar('Error clocking out: $e', isError: true);
      }
    }
  }

  void _setupMapMarkersAndCircles() {
    _markers.clear();
    _circles.clear();

    // Add markers and circles for assisted living locations
    for (final entry in _locations.entries) {
      final placeName = entry.key;
      final location = entry.value;

      // Check if this location matches the client's service type
      // Using loose comparison (ignoring case/trim)
      final clientServiceType = _activeClient?.serviceType?.trim() ?? '';
      final isTargetLocation =
          clientServiceType.toLowerCase() == placeName.toLowerCase();

      // Add marker
      _markers.add(
        Marker(
          markerId: MarkerId(placeName),
          position: location,
          infoWindow: InfoWindow(
              title: placeName,
              snippet: isTargetLocation ? 'Shift Location' : null),
          // Green if it's the target, Red otherwise
          icon: BitmapDescriptor.defaultMarkerWithHue(isTargetLocation
              ? BitmapDescriptor.hueGreen
              : BitmapDescriptor.hueRed),
        ),
      );

      // Add 50m geofence circle
      _circles.add(
        Circle(
          circleId: CircleId(placeName),
          center: location,
          radius: _geofenceRadius,
          strokeWidth: isTargetLocation ? 3 : 2,
          strokeColor: isTargetLocation ? Colors.green : Colors.blue,
          fillColor: isTargetLocation
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.blue.withValues(alpha: 0.1),
        ),
      );
    }

    // Add patient destination marker if we have next client AND it's not already covered by known locations
    if (_activeClient != null) {
      final clientServiceType = _activeClient!.serviceType?.trim() ?? '';
      // Check if service type is one of our known keys (case-insensitive)
      final isKnownLocation = _locations.keys
          .any((k) => k.toLowerCase() == clientServiceType.toLowerCase());

      if (!isKnownLocation) {
        // Use geocoded state coords for dynamic client marker
        final coordinates = _geocodedClientLatLng;
        if (coordinates != null && coordinates.length >= 2) {
          _markers.add(
            Marker(
              markerId: const MarkerId('patient_destination'),
              position: LatLng(coordinates[0], coordinates[1]),
              infoWindow: InfoWindow(
                title: _activeClient!.fullName,
                snippet: _activeClient!.fullAddress,
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
            ),
          );

          // Add visual Geofence Circle for dynamic client location
          _circles.add(
            Circle(
              circleId: const CircleId('patient_geofence'),
              center: LatLng(coordinates[0], coordinates[1]),
              radius: _geofenceRadius,
              strokeWidth: 2,
              strokeColor: Colors.green,
              fillColor: Colors.green.withValues(alpha: 0.1),
            ),
          );
        }
      }
    }
  }

  void _updateMapMarkers() {
    if (_currentPosition == null) return;

    // Add user location marker
    final userMarker = Marker(
      markerId: const MarkerId('user_location'),
      position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      infoWindow: const InfoWindow(title: 'Your Location'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );

    setState(() {
      _markers
          .removeWhere((marker) => marker.markerId.value == 'user_location');
      _markers.add(userMarker);
    });
  }

  Future<void> _moveCameraToUser() async {
    if (_currentPosition != null && _mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          16,
        ),
      );
    }
  }

  Future<void> _loadTasks() async {
    if (_activeShift == null || _loadingTasks) {
      if (_activeShift == null) debugPrint('❌ _loadTasks: _activeShift is null');
      return;
    }

    debugPrint(
        '🔍 _loadTasks: Fetching tasks for shift_id: ${_activeShift!.shiftId}');

    setState(() {
      _loadingTasks = true;
    });

    try {
      List<Task> initialTasks = [];

      // 1. Fetch expected templated local tasks
      if (_activeShift!.taskId != null && _activeShift!.taskId!.contains(',')) {
        initialTasks = Task.fromCommaSeparated(_activeShift!.taskId,
            shiftId: _activeShift!.shiftId);
      } else if (_activeClient != null && _activeClient!.tasks != null) {
        initialTasks = Task.fromClientTasksJson(_activeClient!.tasks,
            shiftId: _activeShift!.shiftId);
      } else if (_activeShift!.clientId != null) {
        try {
          final clientResponse = await supabase
              .from(Tables.client)
              .select('tasks')
              .eq('id', _activeShift!.clientId!)
              .maybeSingle();
          if (clientResponse != null && clientResponse['tasks'] != null) {
            initialTasks = Task.fromClientTasksJson(clientResponse['tasks'],
                shiftId: _activeShift!.shiftId);
          }
        } catch (_) {}
      }

      // 2. Fetch fully committed tasks live from the database
      final liveTasksResponse = await supabase
          .from('tasks')
          .select('*')
          .eq('shift_id', _activeShift!.shiftId);

      final liveTasks =
          liveTasksResponse.map<Task>((e) => Task.fromJson(e)).toList();

      List<Task> finalTasks = [];

      // 3. Merge templates sequentially against database reality
      if (initialTasks.isNotEmpty) {
        for (int i = 0; i < initialTasks.length; i++) {
          final template = initialTasks[i];
          try {
            final match =
                liveTasks.firstWhere((lt) => lt.details == template.details);
            finalTasks.add(match);
          } catch (_) {
            finalTasks.add(template);
          }
        }
      } else if (liveTasks.isNotEmpty) {
        finalTasks = liveTasks;
      } else if (liveTasks.isEmpty && _activeShift!.taskId != null) {
        // Deep Fallback: try shift.task_id as a single standalone task_code from DB
        final fallbackResponse = await supabase
            .from('tasks')
            .select('*')
            .eq('task_code', _activeShift!.taskId!);
        if (fallbackResponse.isNotEmpty) {
          finalTasks =
              fallbackResponse.map<Task>((e) => Task.fromJson(e)).toList();
        }
      }

      // 4. Fetch shift_task_log to integrate 'skipped', 'completed', or 'pending' statuses
      final logsResponse = await supabase
          .from('shift_task_log')
          .select('*')
          .eq('shift_id', _activeShift!.shiftId);
      final logs = logsResponse as List;

      for (int i = 0; i < finalTasks.length; i++) {
        final task = finalTasks[i];
        // Match by task_id if it's already in DB, or by order_index if it's local
        final match = logs
            .where((l) =>
                (l['task_id'] == task.taskId && !task.isLocal) ||
                l['order_index'] == i)
            .firstOrNull;

        if (match != null) {
          finalTasks[i] = task.copyWith(
            shiftTaskLogStatus: match['status'],
            skipReason: match['skip_reason'],
          );
        }
      }

      if (mounted) {
        setState(() {
          _tasks = finalTasks;
          _loadingTasks = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading tasks: $e');
      if (mounted) {
        setState(() {
          _loadingTasks = false;
        });
        if (e.toString().contains('42501') || e.toString().contains('policy')) {
          _showSnackBar('Database Permission Error. Check RLS policies.',
              isError: true);
        }
      }
    }
  }

  Future<void> _upsertShiftTaskLog(int orderIndex, int? taskId, String status,
      {String? skipReason}) async {
    try {
      final empId = await SessionManager.getEmpId();
      if (empId == null) return;

      final clientId = _activeShift!.clientId ?? _activeClient?.id ?? 0;
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      // Since the db often has rows pre-created with order_index and null task_id,
      // we must conflict on order_index to correctly update the existing row
      // rather than accidentally trying to insert a new row that violates the unique order_index constraint.
      final response = await supabase.from('shift_task_log').upsert({
        'shift_id': _activeShift!.shiftId,
        'order_index': orderIndex,
        if (taskId != null) 'task_id': taskId,
        'emp_id': empId,
        'client_id': clientId,
        'status': status,
        'skip_reason':
            skipReason, // explicitly pass to ensure it clears when resuming
        'completed_at': status == 'completed'
            ? nowUtc
            : null,
      }, onConflict: 'shift_id, order_index').select();

      debugPrint('✅ Upserted shift_task_log successfully: $response');
      
      // -- ALSO sync to the new shift_tasks table (dynamically in real-time) --
      if (_tasks.length > orderIndex) {
        final taskDetails = _tasks[orderIndex].details ?? 'Task';
        final isCompleted = status == 'completed';
        final isTemporary = _tasks[orderIndex].isLocal;
        
        final row = <String, dynamic>{
          'shift_id': _activeShift!.shiftId,
          'task_name': taskDetails,
          'is_temporary': isTemporary,
          'status': status,
          'skip_reason': skipReason,
          'completed_at': isCompleted ? nowUtc : null,
          'completed_by': isCompleted ? empId : null,
        };

        if (taskId != null && taskId > 0 && !isTemporary) {
           row['task_id'] = taskId;
        }

        try {
           if (row.containsKey('task_id')) {
             await supabase.from('shift_tasks').upsert(row, onConflict: 'shift_id, task_id');
           } else {
             final existing = await supabase.from('shift_tasks')
                .select('shift_task_id')
                .eq('shift_id', _activeShift!.shiftId)
                .eq('task_name', taskDetails)
                .maybeSingle();
             if (existing != null) {
                await supabase.from('shift_tasks').update(row).eq('shift_task_id', existing['shift_task_id']);
             } else {
                await supabase.from('shift_tasks').insert(row);
             }
           }
        } catch (fkError) {
           // Fallback if care_plan_tasks FK constraint fails
           row.remove('task_id');
           final existing = await supabase.from('shift_tasks')
               .select('shift_task_id')
               .eq('shift_id', _activeShift!.shiftId)
               .eq('task_name', taskDetails)
               .maybeSingle();           
           if (existing != null) {
               await supabase.from('shift_tasks').update(row).eq('shift_task_id', existing['shift_task_id']);
           } else {
               await supabase.from('shift_tasks').insert(row);
           }
        }
        debugPrint('✅ Synced dynamically to shift_tasks table.');
      }
    } catch (e) {
      debugPrint('❌ Error upserting shift_task_log: $e');
      if (mounted) {
        _showSnackBar('Failed to update task log: $e', isError: true);
      }
    }
  }

  Future<void> _promptSkipTask(Task task) async {
    final index = _tasks.indexWhere(
        (t) => t.taskId == task.taskId && t.details == task.details);
    if (index == -1) return;

    final reasonController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
              title: const Text('Skip Task',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Please provide a reason for skipping this task:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      hintText: 'Reason for skipping',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Skip Task'),
                ),
              ]);
        });

    if (confirmed == true && reasonController.text.trim().isNotEmpty) {
      await _skipTaskAndSave(task, index, reasonController.text.trim());
    } else if (confirmed == true && reasonController.text.trim().isEmpty) {
      _showSnackBar('Skip reason is required.', isError: true);
    }
  }

  Future<void> _skipTaskAndSave(Task task, int index, String reason) async {
    // Optimistic update
    Task updatedTask = task.copyWith(
      status: false,
      shiftTaskLogStatus: 'skipped',
      skipReason: reason,
    );
    setState(() {
      _tasks[index] = updatedTask;
    });

    try {
      int? realTaskId;
      if (task.isLocal) {
        final nowUtc = DateTime.now().toUtc().toIso8601String();
        // Task hasn't been instantiated physically on the Supabase task database yet - Create it!
        final response = await supabase
            .from('tasks')
            .insert({
              'shift_id': task.shiftId,
              'details': task.details,
              'status': false,
              'task_created': nowUtc,
              'task_completed': null,
            })
            .select()
            .single();

        final updated = Task.fromJson(response).copyWith(
          shiftTaskLogStatus: 'skipped',
          skipReason: reason,
        );
        realTaskId = updated.taskId;

        setState(() {
          _tasks[index] = updated;
        });
      } else {
        // Shift task already exists natively natively! Overwriting.
        await supabase.from('tasks').update({
          'status': false,
          'task_completed': null,
        }).eq('task_id', task.taskId);
        realTaskId = task.taskId;
      }

      await _upsertShiftTaskLog(index, realTaskId, 'skipped',
          skipReason: reason);
    } catch (e) {
      debugPrint('❌ Error skipping task natively: $e');
      _showSnackBar('Failed to skip. Check connection.', isError: true);
      // Revert optimistic update
      setState(() {
        _tasks[index] = task;
      });
    }
  }

  Future<void> _toggleTask(Task task, bool value) async {
    final index = _tasks.indexWhere(
        (t) => t.taskId == task.taskId && t.details == task.details);
    if (index == -1) return;

    final newStatus = value ? 'completed' : 'pending';

    // Optimistically update memory so checks snap instantly
    Task updatedTask = task.copyWith(
      status: value,
      shiftTaskLogStatus: newStatus,
      skipReason: null, // Clear skip reason if re-toggled
    );

    setState(() {
      _tasks[index] = updatedTask;
    });

    try {
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      int? realTaskId;

      if (task.isLocal) {
        // Task hasn't been instantiated physically on the Supabase task database yet - Create it!
        final response = await supabase
            .from('tasks')
            .insert({
              'shift_id': task.shiftId,
              'details': task.details,
              'status': value,
              'task_created': nowUtc,
              'task_completed': value ? nowUtc : null,
            })
            .select()
            .single();

        final updated = Task.fromJson(response).copyWith(
          shiftTaskLogStatus: newStatus,
          skipReason: null,
        );
        realTaskId = updated.taskId;

        // Map native DB object back gracefully to terminate local tracking
        setState(() {
          _tasks[index] = updated;
        });
      } else {
        // Shift task already exists natively natively! Overwriting.
        await supabase.from('tasks').update({
          'status': value,
          'task_completed': value ? nowUtc : null,
        }).eq('task_id', task.taskId);
        realTaskId = task.taskId;
      }

      await _upsertShiftTaskLog(index, realTaskId, newStatus);
    } catch (e) {
      debugPrint('❌ Error syncing task natively: $e');
      _showSnackBar('Values did not sync. Check connection.', isError: true);
      // Revert optimistic update
      setState(() {
        _tasks[index] = task;
      });
    }
  }

  /// Whether all tasks are completed (or skipped)
  bool get _allTasksCompleted =>
      _tasks.every((t) => t.status || t.shiftTaskLogStatus == 'skipped');

  /// Whether a manual clock-in is allowed:
  /// - A shift must be loaded for today
  /// - Shift must not already be clocked in / active / completed
  bool get _canManualClockIn {
    if (_activeShift == null) return false;
    if (_isClockedIn) return false;
    final status =
        _activeShift!.shiftStatus?.toLowerCase().replaceAll(' ', '_');
    // Allow clock-in only for scheduled (not yet started) shifts
    return status == 'scheduled';
  }

  /// Whether a manual clock-out is allowed:
  /// - Must be clocked in (shift active)
  /// - All tasks must be completed
  bool get _canManualClockOut {
    if (!_isClockedIn) return false;
    return _allTasksCompleted;
  }

  Future<void> _manualClockIn() async {
    if (_activeShift == null || _manualClockingIn) return;

    setState(() => _manualClockingIn = true);

    try {
      final nowUtc = DateTime.now().toUtc();
      final empId = await SessionManager.getEmpId();
      if (empId == null) return;

      await supabase.from('shift').update({
        'clock_in': nowUtc.toIso8601String(),
        'shift_status': 'clocked_in',
      }).eq('shift_id', _activeShift!.shiftId);

      double? lat, lng;
      String clockInAddress = 'Manual Clock In';

      if (_currentPosition != null) {
        lat = _currentPosition!.latitude;
        lng = _currentPosition!.longitude;
      }

      final logResponse = await supabase.from('time_logs').insert({
        'emp_id': empId,
        'shift_id': _activeShift!.shiftId, // IMPORTANT
        'clock_in_time': nowUtc.toIso8601String(),
        if (lat != null) 'clock_in_latitude': lat,
        if (lng != null) 'clock_in_longitude': lng,
        'clock_in_address': clockInAddress,
        'updated_at': nowUtc.toIso8601String(),
      }).select('id');

      setState(() {
        _isClockedIn = true;
        _clockInTimeUtc = nowUtc;
        _currentLogId = logResponse.first['id'].toString();
        _manualClockingIn = false;
      });

      _showSnackBar('Clocked In');
    } catch (e) {
      _showSnackBar('Error clocking in', isError: true);
      setState(() => _manualClockingIn = false);
    }
  }

  /// Manual Clock Out — triggered by the Clock Out button.
  Future<void> _manualClockOut() async {
    if (_activeShift == null || _manualClockingOut) return;

    // Double-check all tasks are done
    if (!_allTasksCompleted) {
      _showSnackBar('Please complete all tasks before clocking out.',
          isError: true);
      return;
    }

    setState(() => _manualClockingOut = true);

    try {
      final nowUtc = DateTime.now().toUtc();

      // 1. Update shift table: clock_out + status = 'Clocked out'
      await supabase.from('shift').update({
        'clock_out': nowUtc.toIso8601String(),
        'shift_status': 'clocked_out',
      }).eq('shift_id', _activeShift!.shiftId);

      debugPrint('✅ Manual Clock Out: Updated shift ${_activeShift!.shiftId}');

      // 2. Update time_logs entry if we have one
      if (_currentLogId != null) {
        final totalHours = _clockInTimeUtc != null
            ? ((nowUtc.difference(_clockInTimeUtc!).inMinutes) / 60.0)
            : 0.0;

        double? lat, lng;
        String clockOutAddress = 'Manual Clock Out';
        if (_currentPosition != null) {
          lat = double.parse(_currentPosition!.latitude.toStringAsFixed(8));
          lng = double.parse(_currentPosition!.longitude.toStringAsFixed(8));
          try {
            clockOutAddress = await _reverseGeocode(
                    _currentPosition!.latitude, _currentPosition!.longitude)
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
        }

        await supabase.from('time_logs').update({
          'clock_out_time': nowUtc.toIso8601String(),
          if (lat != null) 'clock_out_latitude': lat,
          if (lng != null) 'clock_out_longitude': lng,
          'clock_out_address': clockOutAddress,
          'total_hours': double.parse(totalHours.toStringAsFixed(2)),
          'updated_at': nowUtc.toIso8601String(),
        }).eq('id', _currentLogId!);
      }

      // Persist final task outcomes to shift_tasks table
      final empId = await SessionManager.getEmpId();
      if (empId != null) {
        await _finalizeShiftTasks(_activeShift!.shiftId, empId);
      }

      setState(() {
        _isClockedIn = false;
        _clockInTimeUtc = null;
        _currentLogId = null;
        _currentPlaceName = null;
        _activeShift = _activeShift!
            .copyWith(shiftStatus: 'clocked_out', clockOut: nowUtc);
        _manualClockingOut = false;
      });

      _showSnackBar('✅ Clocked Out successfully');

      // Refresh to load next shift
      _loadActiveShift();
    } catch (e) {
      debugPrint('❌ Manual Clock Out Error: $e');
      _showSnackBar('Error clocking out: $e', isError: true);
      if (mounted) setState(() => _manualClockingOut = false);
    }
  }

  // Inline helper functions
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  Future<String> _reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final parts = <String>[];

        if (placemark.name?.isNotEmpty == true) parts.add(placemark.name!);
        if (placemark.street?.isNotEmpty == true) parts.add(placemark.street!);
        if (placemark.locality?.isNotEmpty == true) {
          parts.add(placemark.locality!);
        }
        if (placemark.administrativeArea?.isNotEmpty == true) {
          parts.add(placemark.administrativeArea!);
        }
        if (placemark.postalCode?.isNotEmpty == true) {
          parts.add(placemark.postalCode!);
        }
        if (placemark.country?.isNotEmpty == true) {
          parts.add(placemark.country!);
        }

        return parts.isNotEmpty ? parts.join(', ') : 'Unknown address';
      }
    } catch (e) {
      // Fall through to return 'Unknown address'
    }
    return 'Unknown address';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  LatLng _getInitialCameraPosition() {
    // If we have geocoded client location, center there
    if (_geocodedClientLatLng != null && _geocodedClientLatLng!.length >= 2) {
      return LatLng(_geocodedClientLatLng![0], _geocodedClientLatLng![1]);
    }

    // Average of the three assisted living locations
    double totalLat = 0;
    double totalLng = 0;

    for (final location in _locations.values) {
      totalLat += location.latitude;
      totalLng += location.longitude;
    }

    return LatLng(
      totalLat / _locations.length,
      totalLng / _locations.length,
    );
  }

  Future<void> _moveCameraToClient() async {
    if (_mapController != null &&
        _geocodedClientLatLng != null &&
        _geocodedClientLatLng!.length >= 2) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_geocodedClientLatLng![0], _geocodedClientLatLng![1]),
          18, // High zoom for precision
        ),
      );
    }
  }

  Future<Map<String, double>?> _fetchCoordinatesFromBackend(
      String address) async {
    try {
      final uri = Uri.parse(ApiConfig.geocodeUrl);

      debugPrint('🌍 Calling Geocode API: $uri for "$address"');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'address': address}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'latitude': (data['latitude'] as num).toDouble(),
          'longitude': (data['longitude'] as num).toDouble(),
        };
      } else {
        debugPrint(
            '⚠️ Geocode API Error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Network Error (Geocoding): $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 Redrawing TimeTrackingScreen (activeShift: ${_activeShift?.shiftId}, todayShifts: ${_todayShifts.length}, loading: $_loadingActiveShift)');
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Clock in/out',
            style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.black87, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            onPressed: _loadActiveShift,
            tooltip: 'Refresh Shift',
          ),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: Stack(
        children: [
          // 1. Full Screen Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _getInitialCameraPosition(),
              zoom: 15,
            ),
            markers: _markers,
            circles: _circles,
            polylines: _polylines,
            onMapCreated: (controller) async {
              _mapController = controller;
              // Center on user location if already available
              if (_currentPosition != null && !_hasCenteredOnUser) {
                await controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    16,
                  ),
                );
                _hasCenteredOnUser = true;
              }
            },
            myLocationEnabled: _currentPosition != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            // Add padding to map to avoid bottom sheet covering google logo/controls
            padding: const EdgeInsets.only(bottom: 280),
          ),

          // 2. Map Overlay Controls (Recenter FAB)
          Positioned(
            right: 16,
            top: 130, // Moved to top-right to avoid obstruction
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_geocodedClientLatLng != null) ...[
                  FloatingActionButton(
                    heroTag: 'client_loc_fab',
                    onPressed: _moveCameraToClient,
                    backgroundColor: Colors.white,
                    mini: true,
                    tooltip: 'Show Client Location',
                    child: const Icon(Icons.person_pin_circle,
                        color: Colors.green),
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton(
                  heroTag: 'recenter_fab',
                  onPressed: _moveCameraToUser,
                  backgroundColor: Colors.white,
                  tooltip: 'My Location',
                  child: const Icon(Icons.my_location, color: Colors.black87),
                ),
              ],
            ),
          ),

          // 3. Loading Overlay for GPS
          if (_currentPosition == null)
            Positioned(
              top: 120,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Acquiring precise location...',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Swipeable Bottom Sheet
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.2, // Collapsed state (shows only header)
            maxChildSize: 0.85, // Expanded state (covers most of map)
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Handle bar for visual affordance
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // Status Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _isClockedIn
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.orange.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isClockedIn
                                      ? Icons.check_circle_rounded
                                      : Icons.timer_outlined,
                                  color: _isClockedIn
                                      ? Colors.green
                                      : Colors.orange,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_isClockedIn && _clockInTimeUtc != null)
                                      Text(
                                        'Clocked In at ${DateFormat('h:mm a').format(_clockInTimeUtc!.toLocal())}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      )
                                    else
                                      Text(
                                        'Ready to Start',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _isClockedIn
                                          ? 'Clocked In'
                                          : 'Clocked Out',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isClockedIn && _clockInTimeUtc != null)
                                _LiveTimer(startTime: _clockInTimeUtc!),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Manual Clock In / Out Buttons
                          // Shift Selection Dropdown
                          if (!_isClockedIn && _todayShifts.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Select Shift',
                                  labelStyle: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<Shift>(
                                    isExpanded: true,
                                    value: _todayShifts.contains(_activeShift)
                                        ? _activeShift
                                        : (_todayShifts.isNotEmpty
                                            ? _todayShifts.first
                                            : null),
                                    items: _todayShifts.map((shift) {
                                      return DropdownMenuItem<Shift>(
                                        value: shift,
                                        child: Text(
                                          shift.formattedTimeRange,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (selectedShift) {
                                        if (selectedShift != null &&
                                            selectedShift.shiftId !=
                                                _activeShift?.shiftId) {
                                          setState(() {
                                            _activeShift = selectedShift;
                                            _loadingActiveShift = true;
                                          });
                                          // Reload the client and tasks for the newly selected shift
                                          _loadClientAndTasksForActiveShift();
                                        }
                                    },
                                  ),
                                ),
                              ),
                            ),

                          // Manual Clock In / Out Buttons
                          if (_activeShift == null &&
                              !_loadingActiveShift &&
                              _todayShifts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Text(
                                'No shift scheduled',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      _canManualClockIn ? _manualClockIn : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        Colors.grey.shade300,
                                    disabledForegroundColor:
                                        Colors.grey.shade500,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _manualClockingIn
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : const Text('Clock In',
                                          style: TextStyle(fontSize: 16)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _canManualClockOut
                                      ? _manualClockOut
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey.shade700,
                                    disabledForegroundColor:
                                        Colors.grey.shade400,
                                    side: BorderSide(
                                      color: _canManualClockOut
                                          ? Colors.grey.shade700
                                          : Colors.grey.shade300,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _manualClockingOut
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: Colors.grey,
                                              strokeWidth: 2),
                                        )
                                      : const Text('Clock Out',
                                          style: TextStyle(fontSize: 16)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Active Shift Info Card
                          if (_loadingActiveShift)
                            const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_activeShift != null)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color:
                                            Colors.blue.withValues(alpha: 0.1)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                            Icons.person_outline_rounded,
                                            color: Colors.blue),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _activeClient?.fullName ??
                                                  'Client details loading...',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (_activeClient?.serviceType !=
                                                    null &&
                                                _activeClient!
                                                    .serviceType!.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2),
                                                child: Text(
                                                  _activeClient!.serviceType!,
                                                  style: TextStyle(
                                                    color: Colors.blue.shade700,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            // Get Directions Button
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: InkWell(
                                                onTap: _launchExternalMaps,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.directions,
                                                      size: 16,
                                                      color:
                                                          Colors.blue.shade700,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Get Directions',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .blue.shade700,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${_activeShift!.clockFormattedDate}  •  ${_activeShift!.clockFormattedTimeRangeWithDuration}',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (_activeClient != null &&
                                                _activeClient!.fullAddress
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .location_on_outlined,
                                                      size: 14,
                                                      color:
                                                          Colors.grey.shade500),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      _activeClient!
                                                          .fullAddress,
                                                      style: TextStyle(
                                                        color: Colors
                                                            .grey.shade500,
                                                        fontSize: 11,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (_currentPosition != null &&
                                                _geocodedClientLatLng !=
                                                    null) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(Icons.directions_car,
                                                      size: 14,
                                                      color:
                                                          Colors.blue.shade400),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _routeDistance != null &&
                                                            _routeDuration !=
                                                                null
                                                        ? '$_routeDistance • $_routeDuration'
                                                        : '${(_calculateDistance(
                                                              _currentPosition!
                                                                  .latitude,
                                                              _currentPosition!
                                                                  .longitude,
                                                              _geocodedClientLatLng![
                                                                  0],
                                                              _geocodedClientLatLng![
                                                                  1],
                                                            ) / 1000).toStringAsFixed(2)} km away',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.blue.shade600,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (_routeDistance == null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              left: 8.0),
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          _updateRouteToClient();
                                                          _moveCameraToClient(); // Or bounds
                                                        },
                                                        child: const Text(
                                                          'Show Route',
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.blue,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 11,
                                                              decoration:
                                                                  TextDecoration
                                                                      .underline),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '#${_activeShift!.shiftId}',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Inline Tasks Section (Visible Always)
                                const Divider(height: 32),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Shift Tasks',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_loadingTasks)
                                  const Center(
                                      child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(),
                                  ))
                                else if (_tasks.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: _activeShift!.isBlockChild
                                          ? const Color(0xFFF1F6F5)
                                          : Colors.blue.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _activeShift!.isBlockChild
                                            ? const Color(0xFFE0EAE8)
                                            : Colors.blue.withValues(alpha: 0.1),
                                      ),
                                    ),
                                    child: Text(
                                      'No tasks assigned for this shift.',
                                      style: TextStyle(
                                          color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                else
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: _tasks.length,
                                    itemBuilder: (context, index) {
                                      final task = _tasks[index];
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          InkWell(
                                            onTap: _isClockedIn &&
                                                    task.shiftTaskLogStatus !=
                                                        'skipped'
                                                ? () => _toggleTask(
                                                    task, !task.status)
                                                : null,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4.0,
                                                      horizontal: 8.0),
                                              child: Row(
                                                children: [
                                                  Checkbox(
                                                    value: task.status,
                                                    onChanged: _isClockedIn &&
                                                            task.shiftTaskLogStatus !=
                                                                'skipped'
                                                        ? (val) => _toggleTask(
                                                            task, val ?? false)
                                                        : null,
                                                    activeColor: Colors.blue,
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      task.details ??
                                                          'Task ${index + 1}',
                                                      style: TextStyle(
                                                        decoration: task
                                                                    .status ||
                                                                task.shiftTaskLogStatus ==
                                                                    'skipped'
                                                            ? TextDecoration
                                                                .lineThrough
                                                            : null,
                                                        fontSize: 14,
                                                        color:
                                                            task.shiftTaskLogStatus ==
                                                                    'skipped'
                                                                ? Colors.orange
                                                                : (task.status
                                                                    ? Colors
                                                                        .grey
                                                                    : Colors
                                                                        .black87),
                                                      ),
                                                    ),
                                                  ),
                                                  if (_isClockedIn &&
                                                      task.shiftTaskLogStatus !=
                                                          'skipped')
                                                    TextButton(
                                                      onPressed: () =>
                                                          _promptSkipTask(task),
                                                      child: const Text('Skip',
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.orange,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                    )
                                                  else if (task
                                                          .shiftTaskLogStatus ==
                                                      'skipped')
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                          right: 16.0),
                                                      child: Text('Skipped',
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.orange,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13)),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (task.shiftTaskLogStatus ==
                                                  'skipped' &&
                                              task.skipReason != null &&
                                              task.skipReason!.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 48.0,
                                                  bottom: 8.0,
                                                  right: 16.0),
                                              child: Text(
                                                'Reason: ${task.skipReason}',
                                                style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 13,
                                                    fontStyle:
                                                        FontStyle.italic),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Simple widget to show live duration since start time
class _LiveTimer extends StatefulWidget {
  final DateTime startTime;
  const _LiveTimer({required this.startTime});

  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer> {
  late Timer _timer;
  String _formattedDuration = '00:00:00';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now().toUtc();
    final duration = now.difference(widget.startTime);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    if (mounted) {
      setState(() {
        _formattedDuration = '$hours:$minutes:$seconds';
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Text(
        _formattedDuration,
        style: TextStyle(
          color: Colors.green.shade700,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
