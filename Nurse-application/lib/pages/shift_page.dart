import 'package:flutter/material.dart';
import '../main.dart';
import '../models/employee.dart';
import '../models/shift.dart';
import 'package:nurse_tracking_app/services/session.dart';
import '../widgets/tasks_dialog.dart';
import '../widgets/custom_loading_screen.dart';
import 'block_slots_screen.dart';
import '../widgets/shift_card_widgets.dart';

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
      final response = await supabase.from('shift').select('*').eq('emp_id', empId).order('date').order('shift_start_time');

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

        // ✅ Logic: Dashboard shows only Individual + Block Parent
        if (!shift.isIndividualShift && !shift.isBlockParent) return false;

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

      filtered = [if (activeShift != null && (activeShift.isIndividualShift || activeShift.isBlockParent)) activeShift, ...remaining];
    } else {
      // ALL OTHER TABS
      filtered = _allShifts.where((shift) {
        // ✅ Logic: Dashboard shows only Individual + Block Parent
        if (!shift.isIndividualShift && !shift.isBlockParent) return false;

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
        title: const Text('My Schedule'),
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
                              final shift = _filteredShifts[index];
                              return _buildShiftCard(shift);
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

  Widget _buildShiftCard(Shift shift) {
    if (shift.isBlockParent) {
      return _buildBlockParentCard(shift);
    }

    return IndividualShiftCard(
      shift: shift,
      employee: widget.employee,
      onViewTasks: () {
        showDialog(
          context: context,
          builder: (context) => TasksDialog(shift: shift),
        );
      },
      onViewDetails: () => _showShiftDetails(shift, Theme.of(context)),
    );
  }

  Widget _buildBlockParentCard(Shift shift) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    color: Color(0xFF1976D2),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift.department ?? 'Block Assignment',
                        style: const TextStyle(
                          color: Color(0xFF202124),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Multiple Slots Assigned',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: const Color(0xFFF3E5F5),
                    border: Border.all(color: const Color(0xFFCE93D8)),
                  ),
                  child: const Text(
                    'BLOCK',
                    style: TextStyle(
                      color: Color(0xFF7B1FA2),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: Color(0xFF5F6368), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    shift.date ?? 'No date',
                    style: const TextStyle(color: Color(0xFF3C4043), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 20),
                  const Icon(Icons.access_time_rounded, color: Color(0xFF5F6368), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    shift.formattedTimeRange,
                    style: const TextStyle(color: Color(0xFF3C4043), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BlockSlotsScreen(
                        blockShift: shift,
                        employee: widget.employee,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE3F2FD),
                  foregroundColor: const Color(0xFF1976D2),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFBBDEFB)),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.format_list_bulleted_rounded, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'View Assigned Slots',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
