import 'package:flutter/material.dart';
import '../main.dart';
import '../models/employee.dart';
import '../models/shift.dart';
import 'package:nurse_tracking_app/services/session.dart';
import '../widgets/tasks_dialog.dart';
import '../widgets/custom_loading_screen.dart';

class ShiftPage extends StatefulWidget {
  final Employee employee;

  const ShiftPage({super.key, required this.employee});

  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> {
  List<Shift> _allShifts = [];
  List<Shift> _filteredShifts = [];
  bool _isLoading = true;
  int? _activeShiftId; // Stores the ID of the RPC-determined active shift

  // Date filter state
  String _selectedDateFilter =
      'Next Scheduled'; // 'Today', 'This Week', 'Next Scheduled', 'All'

  // Status filter state
  final Set<String> _selectedStatuses = {}; // Empty means show all

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    try {
      debugPrint('🔍 SHIFT PAGE: Loading shifts...');
      setState(() => _isLoading = true);

      final empId = await SessionManager.getEmpId();
      debugPrint('🧠 SessionManager returned EMP_ID = $empId');

      if (empId == null) {
        debugPrint('❌ ERROR: empId is NULL');
        setState(() => _isLoading = false);
        return;
      }

      final countResponse =
          await supabase.from('shift').select('count').single();

      debugPrint('📊 Total rows in SHIFT table = ${countResponse['count']}');

      // Fetch shifts for emp_id
      debugPrint(
          '📡 Running query: SELECT * FROM shift WHERE emp_id = $empId ORDER BY date, shift_start_time');

      // 1. Fetch Active Shift ID via RPC (Single Source of Truth)
      try {
        final activeShiftResponse =
            await supabase.rpc('get_active_shift', params: {'p_emp_id': empId});
        debugPrint('🔥 RPC Active Shift Response: $activeShiftResponse');

        if (activeShiftResponse != null) {
          if (activeShiftResponse is List && activeShiftResponse.isNotEmpty) {
            _activeShiftId = activeShiftResponse[0]['shift_id'];
          } else if (activeShiftResponse is Map) {
            _activeShiftId = activeShiftResponse['shift_id'];
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching active shift RPC in ShiftPage: $e');
      }

      // 2. Fetch All Shifts
      final response = await supabase.from('shift').select('''
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
          ''').eq('emp_id', empId).order('date').order('shift_start_time');

      debugPrint('📥 Raw fetched rows = ${response.length}');

      final rawShifts = List<Map<String, dynamic>>.from(response);

      // 3. Collect unique client IDs safely
      final Set<int> clientIds = {};
      for (final shift in rawShifts) {
        final cidRaw = shift['client_id'];
        if (cidRaw != null) {
          int? parsedCid;
          if (cidRaw is int)
            parsedCid = cidRaw;
          else if (cidRaw is num)
            parsedCid = cidRaw.toInt();
          else if (cidRaw is String) parsedCid = int.tryParse(cidRaw);

          if (parsedCid != null) {
            clientIds.add(parsedCid);
          }
        }
      }

      // 4. Fetch and map clients from client_final
      Map<int, Map<String, dynamic>> clientsMap = {};
      if (clientIds.isNotEmpty) {
        try {
          final clientResponse = await supabase
              .from('client_final')
              .select()
              .inFilter('id', clientIds.toList());

          for (final c in clientResponse) {
            final cid = (c['id'] as num).toInt();
            clientsMap[cid] = Map<String, dynamic>.from(c);
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching client details: $e');
        }
      }

      // 5. Attach clients and Parse shifts
      final shifts = rawShifts.map((rawJson) {
        final json =
            Map<String, dynamic>.from(rawJson); // Clone to ensure mutability
        final cidRaw = json['client_id'];
        int? parsedCid;
        if (cidRaw is int)
          parsedCid = cidRaw;
        else if (cidRaw is num)
          parsedCid = cidRaw.toInt();
        else if (cidRaw is String) parsedCid = int.tryParse(cidRaw);

        if (parsedCid != null && clientsMap.containsKey(parsedCid)) {
          json['client'] = clientsMap[parsedCid];
        }
        return Shift.fromJson(json);
      }).toList();

      setState(() {
        _allShifts = shifts;
        _applyFilters();
        _isLoading = false;
      });

      debugPrint('✅ Parsed shifts count = ${_allShifts.length}');
    } catch (error) {
      debugPrint('❌ ERROR loading shifts: $error');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading shifts: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      setState(() => _isLoading = false);
    }
  }

  // ─── Safe date parser ─────────────────────────────────────────────────────
  // Parses shift.date (TEXT "YYYY-MM-DD") into a LOCAL midnight DateTime.
  // Never calls .toLocal() on a UTC parse so timezone offsets can't shift
  // "2026-03-28" to "2026-03-27" on UTC+5:30 devices.
  static DateTime? _parseDateLocal(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    // Take only the first 10 chars ("YYYY-MM-DD") regardless of
    // whether the value is a full timestamp or a plain date.
    final datePart = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
    final parts = datePart.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d); // local, no timezone issues
  }

  // ─── Status normalizer ────────────────────────────────────────────────────
  // Uses .contains() so it handles any capitalisation from the DB:
  //   "scheduled" / "Scheduled" / "SCHEDULED" → 'scheduled'
  //   "Clocked in" / "clocked in" / "clocked_in" → 'clocked_in'
  //   "Clocked out" / "clocked out" / "clocked_out" → 'clocked_out'
  static String _normalizeStatus(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.toLowerCase().trim();
    if (s.contains('clocked out') || s == 'clocked_out' ||
        s == 'completed'         || s == 'ended_early') return 'clocked_out';
    if (s.contains('clocked in')  || s == 'clocked_in' ||
        s == 'active'             || s == 'in_progress') return 'clocked_in';
    if (s.contains('cancel'))  return 'cancelled';
    if (s.contains('scheduled')) return 'scheduled'; // catches 'scheduled', 'Scheduled'
    return s;
  }

  void _applyFilters() {
    final now = DateTime.now();
    final todayLocal = DateTime(now.year, now.month, now.day);

    // ── DEBUG tracing ─────────────────────────────────────────────────────────
    debugPrint('════════════════════════════════════════════════════════════════');
    debugPrint('🔍 APPLY FILTERS: date=$_selectedDateFilter | statuses=$_selectedStatuses');
    debugPrint('📅 Today Local: $todayLocal | allShifts=${_allShifts.length}');

    List<Shift> filtered;

    // NEXT SCHEDULED is a special case (pins active shift at top)
    if (_selectedDateFilter == 'Next Scheduled') {
      Shift? activeShift;
      if (_activeShiftId != null) {
        try {
          activeShift = _allShifts.firstWhere((s) => s.shiftId == _activeShiftId);
        } catch (_) {}
      }

      final remaining = _allShifts.where((shift) {
        if (shift.shiftId == _activeShiftId) return false;

        final shiftDate = _parseDateLocal(shift.date);
        if (shiftDate == null) return false;

        final status = _normalizeStatus(shift.shiftStatus);

        // Date check: Today or Future
        final matchesDate = shiftDate.isAtSameMomentAs(todayLocal) || shiftDate.isAfter(todayLocal);

        // Status check: If no status filter, only show actionable ones
        final matchesStatus = _selectedStatuses.isEmpty
            ? (status == 'scheduled' || status == 'clocked_in')
            : _selectedStatuses.contains(status);

        return matchesDate && matchesStatus;
      }).toList()
        ..sort((a, b) {
          final da = _parseDateLocal(a.date) ?? DateTime(9999);
          final db = _parseDateLocal(b.date) ?? DateTime(9999);
          final cmp = da.compareTo(db);
          if (cmp != 0) return cmp;
          return (a.shiftStartTime ?? '').compareTo(b.shiftStartTime ?? '');
        });

      filtered = [if (activeShift != null) activeShift, ...remaining];
    } else {
      // ALL OTHER TABS
      filtered = _allShifts.where((shift) {
        final shiftDate = _parseDateLocal(shift.date);
        if (shiftDate == null) return false;

        final status = _normalizeStatus(shift.shiftStatus);

        // 1. DATE FILTER
        bool matchesDate = false;
        if (_selectedDateFilter == 'Today') {
          matchesDate = shiftDate.isAtSameMomentAs(todayLocal);
        } else if (_selectedDateFilter == 'This Week') {
          final startOfWeek = todayLocal.subtract(Duration(days: todayLocal.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          matchesDate = !shiftDate.isBefore(startOfWeek) && !shiftDate.isAfter(endOfWeek);
        } else if (_selectedDateFilter == 'Completed') {
          // Completed tab filters by status, not date
          matchesDate = (status == 'clocked_out' || status == 'cancelled');
        } else {
          // 'All' or unknown
          matchesDate = true;
        }

        // 2. STATUS FILTER
        final matchesStatus = _selectedStatuses.isEmpty
            ? true
            : _selectedStatuses.contains(status);

        return matchesDate && matchesStatus;
      }).toList();

      // Sort Completed: newest first
      if (_selectedDateFilter == 'Completed') {
        filtered.sort((a, b) {
          final da = _parseDateLocal(a.date) ?? DateTime(0);
          final db = _parseDateLocal(b.date) ?? DateTime(0);
          return db.compareTo(da);
        });
      }
    }

    // DEBUG print results
    debugPrint("✅ After filtering: ${filtered.length} shift(s)");
    for (var s in filtered) {
      debugPrint("   → Showing shift #${s.shiftId} | ${s.date} | ${s.shiftStatus} | normalized=${_normalizeStatus(s.shiftStatus)}");
    }

    setState(() {
      _filteredShifts = filtered;
    });
  }

  void _onDateFilterChanged(String filter) {
    setState(() {
      _selectedDateFilter = filter;
    });
    _applyFilters();
  }

  void _onStatusFilterToggled(String status) {
    // Normalize to internal key e.g. "Scheduled" -> "scheduled"
    final normalized = _normalizeStatus(status);
    if (normalized.isEmpty) return;

    setState(() {
      if (_selectedStatuses.contains(normalized)) {
        _selectedStatuses.remove(normalized);
      } else {
        _selectedStatuses.add(normalized);
      }
    });
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Dashboard'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadShifts,
        child: _isLoading
            ? const CustomLoadingScreen(
                message: 'Loading shifts...',
                isOverlay: true,
              )
            : Column(
                children: [
                  // DATE FILTER
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDateFilterChip('Next Scheduled', theme),
                          const SizedBox(width: 8),
                          _buildDateFilterChip('Today', theme),
                          const SizedBox(width: 8),
                          _buildDateFilterChip('This Week', theme),
                          const SizedBox(width: 8),
                          _buildDateFilterChip(
                              'Completed', theme), // Added Completed Preset
                          const SizedBox(width: 8),
                          _buildDateFilterChip('All', theme),
                        ],
                      ),
                    ),
                  ),

                  // STATUS FILTER
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusChip(
                              'scheduled', 'Scheduled', Colors.orange),
                          const SizedBox(width: 8),
                          _buildStatusChip(
                              'clocked_in', 'Clocked in', Colors.blue),
                          const SizedBox(width: 8),
                          _buildStatusChip(
                              'clocked_out', 'Clocked out', Colors.green),
                          const SizedBox(width: 8),
                          _buildStatusChip(
                              'cancelled', 'Cancelled', Colors.red),
                        ],
                      ),
                    ),
                  ),

                  // SHIFT LIST
                  Expanded(
                    child: _filteredShifts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.calendar_today_outlined,
                                    size: 64,
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.3)),
                                const SizedBox(height: 16),
                                Text(
                                  'No live shift available',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredShifts.length,
                            itemBuilder: (context, index) {
                              return _buildShiftCard(
                                  _filteredShifts[index], theme);
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDateFilterChip(String label, ThemeData theme) {
    final isSelected = _selectedDateFilter == label;
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => _onDateFilterChanged(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, String label, Color color) {
    final normalized = status.toLowerCase().replaceAll(' ', '_');
    final isSelected = _selectedStatuses.contains(normalized);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _onStatusFilterToggled(status),
      selectedColor: color.withValues(alpha: 0.2),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? color : Colors.grey[300]!,
        width: isSelected ? 2 : 1,
      ),
    );
  }

  Widget _buildShiftCard(Shift shift, ThemeData theme) {
    // Use clock-based helpers — correctly reads clock_in/clock_out timestamps
    final formattedDate = shift.clockFormattedDate;
    final timeRangeWithDuration = shift.clockFormattedTimeRangeWithDuration;
    final statusColor = shift.statusColor;
    final statusText = shift.statusDisplayText;
    final normalized = shift.shiftStatus?.toLowerCase().replaceAll(' ', '_');
    final canComplete =
        normalized == 'scheduled' || normalized == 'in_progress' || normalized == 'active' || normalized == 'clocked_in';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => TasksDialog(shift: shift),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildStatusTag(statusText, statusColor),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                '#${shift.shiftId}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // CLIENT NAME (ADDED BACK TO CARD FOR BETTER DASHBOARD)
                        Row(
                          children: [
                            Icon(Icons.person_pin_rounded,
                                size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                shift.clientName ?? 'Unknown Client',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // IMPROVED DATE & TIME DISPLAY
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded,
                                      size: 16,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      formattedDate,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                                  Row(
                                children: [
                                  Icon(Icons.access_time_rounded,
                                      size: 16,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      timeRangeWithDuration,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // View Details Button
                    SizedBox(
                      height: 32,
                      child: OutlinedButton(
                        onPressed: () => _showShiftDetails(shift, theme),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(
                              color:
                                  theme.colorScheme.primary.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('View Details',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),

                    // View Tasks Button (if applicable)
                    if (canComplete) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => TasksDialog(shift: shift),
                            );
                          },
                          icon: const Icon(Icons.list_alt_rounded, size: 16),
                          label: const Text('View Tasks',
                              style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue.shade700,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.blue.shade200),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Duration & Overtime
              Row(
                children: [
                  Expanded(
                    child: _buildInfoChip(
                      'Duration',
                      () {
                        final h = shift.clockDurationHours;
                        if (h == null) return 'N/A';
                        final hrs = h.floor();
                        final mins = ((h - hrs) * 60).round();
                        return mins > 0 ? '${hrs}h ${mins}m' : '${hrs}h';
                      }(),
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      'Overtime',
                      () {
                        final h = shift.clockDurationHours;
                        if (h == null) return 'N/A';
                        final ot = h > 8 ? h - 8 : 0.0;
                        final hrs = ot.floor();
                        final mins = ((ot - hrs) * 60).round();
                        return mins > 0 ? '${hrs}h ${mins}m' : '${hrs}h';
                      }(),
                      Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShiftDetails(Shift shift, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              // Handle Bar
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

              Text(
                'Shift Details',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Center(
                  child: _buildStatusTag(
                      shift.statusDisplayText, shift.statusColor)),
              const SizedBox(height: 32),

              _buildDetailItem(theme, 'Client Name', shift.clientName ?? 'N/A'),
              _buildDetailItem(
                  theme, 'Location', shift.clientLocation ?? 'N/A'),
              _buildDetailItem(
                  theme, 'Service Type', shift.clientServiceType ?? 'N/A'),
              _buildDetailItem(
                  theme, 'Skills Required', shift.skills ?? 'None specified'),

              if (shift.shiftProgressNote != null &&
                  shift.shiftProgressNote!.isNotEmpty)
                _buildDetailItem(
                    theme, 'Progress Note', shift.shiftProgressNote!),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
            ),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
