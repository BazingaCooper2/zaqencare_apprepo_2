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

      // 1. Fetch All Relevant Shifts (Simple fetch for better compatibility)
      final response = await supabase
          .from('shift')
          .select('*')
          .eq('emp_id', empId)
          .not('date', 'is', null)
          .order('date')
          .order('shift_start_time');

      debugPrint('📥 Raw fetched rows = ${response.length}');

      final List<Map<String, dynamic>> rawShifts =
          List<Map<String, dynamic>>.from(response);

      // 2. Fetch Block Parents if any block_child shifts exist
      final Set<int> parentIds = rawShifts
          .where((s) => s['parent_block_id'] != null)
          .map((s) => s['parent_block_id'] as int)
          .toSet();

      if (parentIds.isNotEmpty) {
        try {
          final parentResponse = await supabase
              .from('shift')
              .select('*')
              .inFilter('shift_id', parentIds.toList());

          for (final p in parentResponse) {
            final parentId = p['shift_id'];
            if (!rawShifts.any((s) => s['shift_id'] == parentId)) {
              rawShifts.add(Map<String, dynamic>.from(p));
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching block parents: $e');
        }
      }

      // 3. Collect unique client IDs safely
      final Set<int> clientIds = {};
      for (final shift in rawShifts) {
        final cidRaw = shift['client_id']?.toString();
        if (cidRaw != null) {
          final pc = int.tryParse(cidRaw) ?? double.tryParse(cidRaw)?.toInt();
          if (pc != null) clientIds.add(pc);
        }
      }

      // 4. Fetch and map clients with nested care plans & tasks
      Map<int, Map<String, dynamic>> clientsMap = {};
      if (clientIds.isNotEmpty) {
        try {
          final clientResponse = await supabase
              .from('client_final')
              .select('*, care_plans!care_plans_client_id_fkey(*, care_plan_tasks!care_plan_tasks_care_plan_id_fkey(*))')
              .inFilter('id', clientIds.toList());

          for (final c in clientResponse) {
            final idRaw = c['id']?.toString();
            final id = idRaw != null ? (int.tryParse(idRaw) ?? double.tryParse(idRaw)?.toInt()) : null;
            if (id != null) {
              clientsMap[id] = Map<String, dynamic>.from(c);
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching client details: $e');
        }
      }

      // 5. Attach clients and Parse shifts
      final shifts = rawShifts.map((rawJson) {
        final json = Map<String, dynamic>.from(rawJson);
        final cidRaw = json['client_id']?.toString();
        final parsedCid = cidRaw != null ? (int.tryParse(cidRaw) ?? double.tryParse(cidRaw)?.toInt()) : null;

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
    final s = raw.toLowerCase().trim().replaceAll(' ', '_');
    if (s == 'clocked_out' || s == 'completed' || s == 'ended_early')
      return 'clocked_out';
    if (s == 'clocked_in' || s == 'active' || s == 'in_progress')
      return 'clocked_in';
    if (s == 'scheduled') return 'scheduled';
    if (s == 'offered') return 'offered';
    if (s == 'accepted') return 'accepted';
    if (s == 'assigned') return 'assigned';
    if (s.contains('cancel')) return 'cancelled';
    return s;
  }

  void _applyFilters() {
    final now = DateTime.now();
    final todayLocal = DateTime(now.year, now.month, now.day);

    // ── DEBUG tracing ─────────────────────────────────────────────────────────
    debugPrint(
        '════════════════════════════════════════════════════════════════');
    debugPrint(
        '🔍 APPLY FILTERS: date=$_selectedDateFilter | statuses=$_selectedStatuses');
    debugPrint('📅 Today Local: $todayLocal | allShifts=${_allShifts.length}');

    List<Shift> filtered;

    // NEXT SCHEDULED is a special case (pins active shift at top)
    if (_selectedDateFilter == 'Next Scheduled') {
      Shift? activeShift;
      if (_activeShiftId != null) {
        try {
          activeShift =
              _allShifts.firstWhere((s) => s.shiftId == _activeShiftId);
        } catch (_) {}
      }

      final remaining = _allShifts.where((shift) {
        if (shift.shiftId == _activeShiftId) return false;

        // ✅ Logic: Dashboard shows all shift types
        // if (!shift.isStandalone && !shift.isBlock) return false;

        final shiftDate = _parseDateLocal(shift.date);
        if (shiftDate == null) return false;

        final status = _normalizeStatus(shift.shiftStatus);

        // Date check: Today or Future
        final matchesDate = shiftDate.isAtSameMomentAs(todayLocal) ||
            shiftDate.isAfter(todayLocal);

        // Status check: Next Scheduled (scheduled, assigned)
        final matchesStatus = _selectedStatuses.isEmpty
            ? (status == 'scheduled' || status == 'assigned')
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

      filtered = [
        if (activeShift != null &&
            (activeShift.isStandalone || activeShift.isBlock))
          activeShift,
        ...remaining
      ];
    } else {
      // ALL OTHER TABS
      filtered = _allShifts.where((shift) {
        // ✅ Core Logic: Show all shift types on Dashboard
        // if (!shift.isStandalone && !shift.isBlockChild && !shift.isBlock) return false;

        final shiftDate = _parseDateLocal(shift.date);
        if (shiftDate == null) return false;

        final status = _normalizeStatus(shift.shiftStatus);

        // 1. DATE FILTER
        bool matchesDate = false;
        if (_selectedDateFilter == 'Today') {
          matchesDate = shiftDate.isAtSameMomentAs(todayLocal);
        } else if (_selectedDateFilter == 'Next Scheduled') {
          // Next Scheduled includes today and future
          matchesDate = (shiftDate.isAtSameMomentAs(todayLocal) ||
                  shiftDate.isAfter(todayLocal)) &&
              (status == 'scheduled' || status == 'assigned');
        } else if (_selectedDateFilter == 'This Week') {
          final startOfWeek =
              todayLocal.subtract(Duration(days: todayLocal.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          matchesDate =
              !shiftDate.isBefore(startOfWeek) && !shiftDate.isAfter(endOfWeek);
        } else if (_selectedDateFilter == 'Completed') {
          // Completed tab filters strictly by status
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
      debugPrint(
          "   → Showing shift #${s.shiftId} | ${s.date} | ${s.shiftStatus} | normalized=${_normalizeStatus(s.shiftStatus)}");
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
      backgroundColor: const Color(0xFFE8F0EE),
      appBar: AppBar(
        title: const Text('My Schedule',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Colors.white,
                letterSpacing: -0.3)),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadShifts,
        color: const Color(0xFF1A1A2E),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A1A2E)))
            : Column(
                children: [
                  // DATE FILTERS
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDateFilterChip('Next Scheduled'),
                          const SizedBox(width: 10),
                          _buildDateFilterChip('Today'),
                          const SizedBox(width: 10),
                          _buildDateFilterChip('This Week'),
                          const SizedBox(width: 10),
                          _buildDateFilterChip('Completed'),
                          const SizedBox(width: 10),
                          _buildDateFilterChip('All'),
                        ],
                      ),
                    ),
                  ),

                  // STATUS FILTERS (Restored)
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusChip('scheduled', 'Scheduled', Colors.orange),
                          const SizedBox(width: 8),
                          _buildStatusChip('offered', 'Offered', Colors.blueGrey),
                          const SizedBox(width: 8),
                          _buildStatusChip('accepted', 'Accepted', Colors.teal),
                          const SizedBox(width: 8),
                          _buildStatusChip('assigned', 'Assigned', Colors.indigo),
                          const SizedBox(width: 8),
                          _buildStatusChip('clocked_in', 'Clocked in', Colors.blue),
                          const SizedBox(width: 8),
                          _buildStatusChip('clocked_out', 'Clocked out', Colors.green),
                          const SizedBox(width: 8),
                          _buildStatusChip('cancelled', 'Cancelled', Colors.red),
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
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.calendar_today_rounded,
                                      size: 48,
                                      color: Colors.grey.shade300),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No shifts found',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              ..._filteredShifts.map((s) => _buildShiftCard(s)),
                              const SizedBox(height: 40),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDateFilterChip(String label) {
    final isSelected = _selectedDateFilter == label;
    return GestureDetector(
      onTap: () => _onDateFilterChanged(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF003D33) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, String label, Color color) {
    final normalized = status.toLowerCase().replaceAll(' ', '_');
    final isSelected = _selectedStatuses.contains(normalized);
    
    return GestureDetector(
      onTap: () => _onStatusFilterToggled(status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.2),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildShiftCard(Shift shift) {
    if (shift.isBlock) {
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
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Container(height: 6, color: Colors.purple.shade400),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'BLOCK',
                          style: TextStyle(
                            color: Colors.purple.shade700,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '#${shift.shiftId}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.grid_view_rounded,
                          color: Colors.purple.shade400, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shift.department ?? 'Block Assignment',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              'Assigned Schedule',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Flexible(child: _buildMiniInfo(Icons.calendar_today_rounded, shift.clockFormattedDate, 'Date')),
                      const SizedBox(width: 16),
                      Flexible(child: _buildMiniInfo(Icons.access_time_rounded, shift.formattedTimeRange, 'Time')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                      label: const Text(
                        'View Assigned Slots',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
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
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInfo(IconData icon, String text, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.purple.shade400),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
      ],
    );
  }

  void _showShiftDetails(Shift shift, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFE8F0EE),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Shift Details',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),

              // Status Badge
              _buildStatusTag(shift.statusDisplayText, shift.statusColor),
              const SizedBox(height: 40),

              // Scrollable Details
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildDetailItem('Client Name', shift.clientName ?? 'N/A'),
                    const SizedBox(height: 24),
                    _buildDetailItem('Phone Number', shift.client?.phoneMain ?? 'Not provided'),
                    const SizedBox(height: 24),
                    _buildDetailItem('Location', shift.clientLocation ?? 'N/A'),
                    const SizedBox(height: 24),
                    _buildDetailItem('Service Type', shift.clientServiceType ?? 'N/A'),
                    const SizedBox(height: 24),
                    _buildDetailItem('Skills Required', shift.skills ?? 'None specified'),
                    if (shift.shiftProgressNote?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 24),
                      _buildDetailItem('Progress Note', shift.shiftProgressNote!),
                    ],
                  ],
                ),
              ),

              // Close Button
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Divider(color: Colors.grey.shade300, thickness: 0.8),
      ],
    );
  }

  Widget _buildStatusTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 1.2),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildInfoChip(
      String label, String value, Color bgColor, Color textColor) {
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
