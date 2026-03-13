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
import '../models/employee.dart';
import '../models/shift.dart';
import '../models/client.dart';
import '../models/task_model.dart';
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
  // Geocoded coordinates for the active client's address.
  // client_final has no lat/lng column — coords are fetched via backend.
  List<double>? _geocodedClientLatLng; // [lat, lng]

  // Task state
  List<Task> _tasks = [];
  bool _loadingTasks = false;
  bool _updatingTasks = false; // Track if update is in progress

  // Route state
  String? _routeDistance;
  String? _routeDuration;

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
    await _requestLocationPermission();

    // 1. Check for existing session and restore it (PRIORITY)
    await _checkActiveClockInStatus();

    // 2. If no active session restored, load the next schedule
    if (_activeShift == null) {
      await _loadActiveShift();
    }

    // 3. Setup map based on whatever client we found
    _setupMapMarkersAndCircles();
  }

  Future<void> _checkActiveClockInStatus() async {
    try {
      final empId = await SessionManager.getEmpId();
      if (empId == null) return;

      // Check DB for any row where clock_out_time is NULL
      final response = await supabase
          .from('time_logs')
          .select('*')
          .eq('emp_id', empId)
          .filter('clock_out_time', 'is', null)
          .maybeSingle();

      if (response != null && mounted) {
        final log = response;
        final lat = (log['clock_in_latitude'] as num).toDouble();
        final lng = (log['clock_in_longitude'] as num).toDouble();

        // Try to match which location we are at based on stored coordinates
        String? matchedPlace;
        for (final entry in _locations.entries) {
          final loc = entry.value;
          final dist =
              _calculateDistance(lat, lng, loc.latitude, loc.longitude);

          // If the stored clock-in location corresponds to one of our geofences
          // (allowing a relaxed buffer since we might have clocked in at the edge)
          if (dist <= _geofenceRadius + 50) {
            matchedPlace = entry.key;
            break;
          }
        }

        // Manual Shift Restore removed as RPC handles it now.

        setState(() {
          _isClockedIn = true;
          _currentPlaceName = matchedPlace;
          _currentLogId = log['id'].toString();
          _clockInTimeUtc = DateTime.parse(log['clock_in_time']);
        });

        if (matchedPlace != null) {
          print('🔄 Restored active session at $matchedPlace');
        } else {
          debugPrint('⚠️ Restored active session but location unknown.');
        }
      }
    } catch (e) {
      debugPrint('Error checking active session: $e');
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _positionSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<Shift?> fetchActiveShift(int empId) async {
    debugPrint('🚨 Fetching ACTIVE SHIFT via RPC for emp_id=$empId');
    try {
      // 1. Try RPC first (Primary logic)
      final response =
          await supabase.rpc('get_active_shift', params: {'p_emp_id': empId});

      debugPrint('📥 RPC Raw Response: $response');

      if (response != null && response is List && response.isNotEmpty) {
        debugPrint('✅ RPC returned ${response.length} shift(s)');
        return Shift.fromJson(response.first);
      } else if (response is Map) {
        debugPrint('✅ RPC returned a single shift map');
        return Shift.fromJson(response as Map<String, dynamic>);
      }

      // 2. Fallback: Manual check for scheduled shifts today
      debugPrint(
          '⚠️ RPC returned empty/null. Fallback: Checking for today\'s scheduled shifts...');
      final now = DateTime.now();
      final todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      debugPrint('📅 Querying shifts for emp_id=$empId, date=$todayStr');

      final fallbackResponse = await supabase
          .from('shift')
          .select('*')
          .eq('emp_id', empId)
          .eq('date', todayStr)
          .inFilter('shift_status', [
        'scheduled',
        'Scheduled',
        'in_progress',
        'In Progress'
      ]).order('shift_start_time', ascending: true);

      debugPrint(
          '📥 Fallback query returned ${(fallbackResponse as List).length} shift(s)');

      if ((fallbackResponse as List).isNotEmpty) {
        // Log all found shifts
        for (int i = 0; i < (fallbackResponse as List).length; i++) {
          final s = fallbackResponse[i];
          debugPrint(
              '  Shift[$i]: id=${s['shift_id']}, client_id=${s['client_id']}, '
              'status=${s['shift_status']}, date=${s['date']}, '
              'time=${s['shift_start_time']}-${s['shift_end_time']}, '
              'task_id=${s['task_id']}');
        }

        final shifts = (fallbackResponse as List)
            .map((s) => Shift.fromJson(s as Map<String, dynamic>))
            .toList();

        Shift? bestMatch;
        int maxScore = 0;

        // Find the most relevant shift (Currently active > Starting soon > Just ended)
        for (final shift in shifts) {
          final score = shift.shiftTimeScore;
          debugPrint('  Shift ${shift.shiftId} score=$score');
          if (score > maxScore) {
            maxScore = score;
            bestMatch = shift;
            if (maxScore == 3) break; // Found an active one, can't get better
          }
        }

        if (bestMatch != null) {
          debugPrint(
              '✅ Found best matching scheduled shift for today: ${bestMatch.shiftId} (Score: $maxScore)');
          return bestMatch;
        }

        // If none strictly match the time window, fallback to the first shift of the day
        debugPrint(
            '⚠️ No currently active shift found today. Defaulting to first scheduled shift: ${shifts.first.shiftId}');
        return shifts.first;
      }

      debugPrint('❌ No shifts found for emp_id=$empId on $todayStr');
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching active shift: $e');
      return null;
    }
  }

  Future<void> _loadActiveShift() async {
    setState(() {
      _loadingActiveShift = true;
    });

    try {
      final empId = await SessionManager.getEmpId();
      debugPrint('🔑 SessionManager emp_id = $empId');

      if (empId == null) {
        debugPrint('❌ emp_id is null! User may not be logged in.');
        setState(() {
          _loadingActiveShift = false;
        });
        return;
      }

      final shift = await fetchActiveShift(empId);

      if (shift != null) {
        debugPrint(
            '✅ Active shift found: id=${shift.shiftId}, client_id=${shift.clientId}, task_id=${shift.taskId}');

        // Priority 1: Use nested client if available
        Client? client = shift.client;

        // Priority 2: Manual fetch if nested data missing
        if (client == null && shift.clientId != null) {
          debugPrint(
              '🔍 Fetching client data for client_id=${shift.clientId}...');
          final clientResponse = await supabase
              .from(Tables.client)
              .select('*')
              .eq('id', shift.clientId!)
              .limit(1);

          if (clientResponse.isNotEmpty) {
            client = Client.fromJson(clientResponse.first);
            debugPrint('✅ Client loaded: ${client.fullName}');
          } else {
            debugPrint('⚠️ No client found for client_id=${shift.clientId}');
          }
        }

        // Geocode the client address
        if (client != null && client.fullAddress.isNotEmpty) {
          final coords = await _fetchCoordinatesFromBackend(client.fullAddress);
          if (coords != null) {
            final lat = (coords['latitude'] as num).toDouble();
            final lng = (coords['longitude'] as num).toDouble();
            setState(() {
              _geocodedClientLatLng = [lat, lng];
            });
            debugPrint('✅ Geocoded ${client.fullAddress} → $lat,$lng');
          }
        }

        setState(() {
          _activeShift = shift;
          _activeClient = client;
          _loadingActiveShift = false;
          _setupMapMarkersAndCircles(); // Refresh markers/geofences
        });

        debugPrint(
            '✅ Loaded shift ${shift.shiftId} for client_id ${shift.clientId}');
        debugPrint('✅ Client loaded: ${client?.fullName ?? "No client"}');
        debugPrint('✅ Client address: ${client?.fullAddress ?? "No address"}');

        // Update route if we have both current position and client location
        if (_currentPosition != null && client != null) {
          _updateRouteToClient();
        }

        // Load tasks for this shift
        _loadTasks();
      } else {
        debugPrint('⚠️ No active shifts found');
        setState(() {
          _activeShift = null;
          _activeClient = null;
          _loadingActiveShift = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading active shift: $e');
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

        // Update address if not already set
        _currentAddress ??=
            await _reverseGeocode(position.latitude, position.longitude);

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

    // Also do one immediate fetch so we don't wait for the stream's first event
    _updateLocation();
  }

  Future<void> _updateLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      debugPrint(
          '📍 Location updated: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');

      if (!mounted) return;

      setState(() {
        _currentPosition = position;
      });

      // Update address if not already set
      _currentAddress ??=
          await _reverseGeocode(position.latitude, position.longitude);

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
    } catch (e) {
      debugPrint('❌ Location error: $e');
      if (mounted) {
        _showSnackBar('Location error: $e', isError: true);
      }
    }
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
    if (_permissionDenied) return; // Stop trying if we know we are blocked

    // 1. Check if Supabase Auth is valid
    if (supabase.auth.currentUser == null) {
      _showSnackBar('⚠️ Logged out from server. Please Log Out & Log In again.',
          isError: true);
      return;
    }

    try {
      final nowUtc = DateTime.now().toUtc();
      final clockInAddress =
          await _reverseGeocode(position.latitude, position.longitude);

      final lat = double.parse(position.latitude.toStringAsFixed(8));
      final lng = double.parse(position.longitude.toStringAsFixed(8));

      final empId = await SessionManager.getEmpId();
      if (empId == null) {
        _showSnackBar('Session expired. Please login again.', isError: true);
        return;
      }

      debugPrint(
          '📝 Attempting Auto-Clock In: AuthID=${supabase.auth.currentUser?.id}, EmpID=$empId');

      final response = await supabase.from('time_logs').insert({
        'emp_id': empId,
        // 'schedule_id': _activeShift?.shiftId.toString(), // schema mismatch
        'clock_in_time': nowUtc.toIso8601String(),
        'clock_in_latitude': lat,
        'clock_in_longitude': lng,
        'clock_in_address': clockInAddress,
        'updated_at': nowUtc.toIso8601String(),
      }).select('id');

      if (response.isNotEmpty) {
        // Also update the shift table if we have an active shift
        if (_activeShift != null) {
          try {
            await supabase.from('shift').update({
              'clock_in': nowUtc.toIso8601String(),
              'shift_status': 'in_progress'
            }).eq('shift_id', _activeShift!.shiftId);
            debugPrint('✅ Updated shift table with clock_in time');
          } catch (e) {
            debugPrint('⚠️ Failed to update shift table clock_in: $e');
          }
        }

        setState(() {
          _isClockedIn = true;
          _currentPlaceName = placeName;
          _currentLogId = response.first['id'];
          _clockInTimeUtc = nowUtc;
        });

        final localTime = DateFormat('HH:mm:ss').format(DateTime.now());
        _showSnackBar('✅ Auto Clocked IN at $placeName ($localTime)');
      }
    } catch (e) {
      // Handle RLS Permission Error specifically
      if (e.toString().contains('42501') || e.toString().contains('policy')) {
        setState(() {
          _permissionDenied = true;
        });
        _showPermissionErrorDialog();
      }
      // Handle Network Error
      else if (e.toString().contains('SocketException') ||
          e.toString().contains('host lookup')) {
        _showSnackBar(
            '⚠️ Internet lost. Validating entry locally... (Sync pending)',
            isError: true);
      } else {
        _showSnackBar('Error clocking in: $e', isError: true);
        debugPrint('❌ Clock-in Error: $e');
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

  Future<void> _autoClockOut(Position position) async {
    if (_currentLogId == null || _permissionDenied) return;

    try {
      final nowUtc = DateTime.now().toUtc();
      final clockOutAddress =
          await _reverseGeocode(position.latitude, position.longitude);

      final totalHours = _clockInTimeUtc != null
          ? ((nowUtc.difference(_clockInTimeUtc!).inMinutes) / 60.0)
          : 0.0;

      final lat = double.parse(position.latitude.toStringAsFixed(8));
      final lng = double.parse(position.longitude.toStringAsFixed(8));

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
            'shift_status': 'completed'
          }).eq('shift_id', _activeShift!.shiftId);
          debugPrint(
              '✅ Updated shift table with clock_out time and completed status');
        } catch (e) {
          debugPrint('⚠️ Failed to update shift table clock_out: $e');
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
    if (_activeShift == null) {
      debugPrint('❌ _loadTasks: _activeShift is null');
      return;
    }

    debugPrint(
        '🔍 _loadTasks: Fetching tasks for shift_id: ${_activeShift!.shiftId}');

    setState(() {
      _loadingTasks = true;
    });

    try {
      // ──────────────────────────────────────────────────────
      // 1. PRIMARY: Parse shift.task_id comma-separated string
      //    e.g. "task1,task2,task3,task4,task5"
      // ──────────────────────────────────────────────────────
      if (_activeShift!.taskId != null && _activeShift!.taskId!.contains(',')) {
        final parsed = Task.fromCommaSeparated(
          _activeShift!.taskId,
          shiftId: _activeShift!.shiftId,
        );
        if (parsed.isNotEmpty) {
          debugPrint(
              '✅ _loadTasks: Loaded ${parsed.length} tasks from shift.task_id (comma-separated)');
          if (mounted) {
            setState(() {
              _tasks = parsed;
              _loadingTasks = false;
            });
          }
          return;
        }
      }

      // ──────────────────────────────────────────────────────
      // 2. Fetch tasks from client_final.tasks JSONB
      // ──────────────────────────────────────────────────────
      // a) Check if we already have client data with tasks
      if (_activeClient != null && _activeClient!.tasks != null) {
        final clientTasks = Task.fromClientTasksJson(
          _activeClient!.tasks,
          shiftId: _activeShift!.shiftId,
        );
        if (clientTasks.isNotEmpty) {
          debugPrint(
              '✅ _loadTasks: Loaded ${clientTasks.length} tasks from activeClient.tasks');
          if (mounted) {
            setState(() {
              _tasks = clientTasks;
              _loadingTasks = false;
            });
          }
          return;
        }
      }

      // b) Fetch tasks directly from client_final table via client_id
      if (_activeShift!.clientId != null) {
        try {
          final clientResponse = await supabase
              .from(Tables.client)
              .select('tasks')
              .eq('id', _activeShift!.clientId!)
              .maybeSingle();

          if (clientResponse != null && clientResponse['tasks'] != null) {
            final clientTasks = Task.fromClientTasksJson(
              clientResponse['tasks'],
              shiftId: _activeShift!.shiftId,
            );
            if (clientTasks.isNotEmpty) {
              debugPrint(
                  '✅ _loadTasks: Loaded ${clientTasks.length} tasks from client_final.tasks (DB)');
              if (mounted) {
                setState(() {
                  _tasks = clientTasks;
                  _loadingTasks = false;
                });
              }
              return;
            }
          }
        } catch (e) {
          debugPrint('⚠️ _loadTasks: Error fetching client_final.tasks: $e');
        }
      }

      // ──────────────────────────────────────────────────────
      // 3. Fallback: Legacy tasks table by shift_id
      // ──────────────────────────────────────────────────────
      var response = await supabase
          .from('tasks')
          .select('*')
          .eq('shift_id', _activeShift!.shiftId)
          .order('task_id');

      debugPrint(
          '📥 _loadTasks: Found ${response.length} tasks by shift_id=${_activeShift!.shiftId}');

      // 4. Fallback: try shift.task_id as a single task_code
      if (response.isEmpty && _activeShift!.taskId != null) {
        debugPrint(
            '⚠️ No tasks by shift_id. Attempting fallback via task_code: ${_activeShift!.taskId}');

        final shiftTaskCode = _activeShift!.taskId!;

        final fallbackResponse = await supabase
            .from('tasks')
            .select('*')
            .eq('task_code', shiftTaskCode);

        if (fallbackResponse.isNotEmpty) {
          debugPrint(
              '✅ Found ${fallbackResponse.length} tasks via task_code=$shiftTaskCode');
          response = fallbackResponse;
        }
      }

      final tasks = response.map<Task>((e) => Task.fromJson(e)).toList();

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _loadingTasks = false;
        });

        if (tasks.isEmpty) {
          debugPrint(
              '⚠️ _tasks is empty. No data in shift.task_id, client_final.tasks, or "tasks" table.');
        }
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

  Future<void> _toggleTask(Task task, bool value) async {
    // 1. Optimistic Update
    final index = _tasks.indexWhere((t) => t.taskId == task.taskId);
    if (index == -1) return;

    final updatedTask = Task(
        taskId: task.taskId,
        shiftId: task.shiftId,
        details: task.details,
        status: value,
        comment: task.comment,
        taskCode: task.taskCode,
        isFromClient: task.isFromClient,
        isFromShiftTaskId: task.isFromShiftTaskId);

    setState(() {
      _tasks[index] = updatedTask;
    });

    // 2. Only persist to legacy tasks table if NOT a local task
    if (!task.isLocal) {
      try {
        await supabase
            .from('tasks')
            .update({'status': value}).eq('task_id', task.taskId);
      } catch (e) {
        debugPrint('❌ Error auto-saving task: $e');
        _showSnackBar('Values did not save to server. Check connection.',
            isError: true);
      }
    }
    // Local tasks (from shift.task_id or client.tasks) toggle in-memory only
  }

  Future<void> _handleClockOut() async {
    setState(() {
      _updatingTasks = true;
    });

    try {
      // Validate again (redundant but safe)
      if (!_tasks.every((t) => t.status)) {
        _showSnackBar('Please complete all tasks first!', isError: true);
        setState(() => _updatingTasks = false);
        return;
      }

      if (_currentPosition == null) {
        _showSnackBar('Waiting for location...', isError: true);
        setState(() => _updatingTasks = false);
        return;
      }

      _showSnackBar('✅ Tasks verified. Clocking out...');
      // Delay to show the success message
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        await _autoClockOut(_currentPosition!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updatingTasks = false;
        });
        _showSnackBar('Error clocking out: $e', isError: true);
      }
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
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Handle bar for visual affordance
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 20),
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
                                    Text(
                                      _isClockedIn
                                          ? 'Currently Working'
                                          : 'Ready to Start',
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

                          const SizedBox(height: 24),

                          // Active Shift Info Card
                          if (_loadingActiveShift)
                            const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_activeShift != null &&
                              _activeClient != null)
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
                                              _activeClient!.fullName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (_activeClient!.serviceType !=
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
                                              '${_activeShift!.date} • ${_activeShift!.formattedTimeRange}',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (_activeClient!
                                                .fullAddress.isNotEmpty) ...[
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
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(12),
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
                                      return CheckboxListTile(
                                        // Enabled only when clocked in
                                        enabled: _isClockedIn,
                                        value: task.status,
                                        onChanged: (val) =>
                                            _toggleTask(task, val ?? false),
                                        title: Text(
                                          task.details ?? 'Task ${index + 1}',
                                          style: TextStyle(
                                            decoration: task.status
                                                ? TextDecoration.lineThrough
                                                : null,
                                            fontSize: 14,
                                            color: task.status
                                                ? Colors.grey
                                                : Colors.black87,
                                          ),
                                        ),
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        contentPadding: EdgeInsets.zero,
                                        activeColor: Colors.blue,
                                      );
                                    },
                                  ),
                              ],
                            ),

                          // Clock Out Button (only shows when clocked in)
                          if (_isClockedIn)
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: (_tasks.isNotEmpty &&
                                        _tasks.every((t) => t.status) &&
                                        _currentPosition != null &&
                                        // Allow clock-out if geocoded coords available OR no coords (relax check)
                                        (_geocodedClientLatLng == null ||
                                            _calculateDistance(
                                                    _currentPosition!.latitude,
                                                    _currentPosition!.longitude,
                                                    _geocodedClientLatLng![0],
                                                    _geocodedClientLatLng![1]) <
                                                (_geofenceRadius + 200)) &&
                                        !_updatingTasks)
                                    ? _handleClockOut
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.redAccent, // Distinct color
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  disabledBackgroundColor: Colors.grey.shade300,
                                  disabledForegroundColor: Colors.grey.shade500,
                                ),
                                child: _updatingTasks
                                    ? const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Processing...',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Text(
                                        'Clock Out',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          if (_isClockedIn)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _tasks.every((t) => t.status)
                                    ? 'All tasks complete. You are ready to clock out.'
                                    : 'Complete all tasks to enable Clock Out.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _tasks.every((t) => t.status)
                                      ? Colors.green
                                      : Colors.orange,
                                  fontWeight: _tasks.every((t) => t.status)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          if (!_isClockedIn)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Enter the client\'s location to automatically clock in.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
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
