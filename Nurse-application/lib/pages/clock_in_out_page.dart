import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/shift.dart';
import '../main.dart';
import 'time_tracking_page.dart';
import '../widgets/custom_loading_screen.dart';
import '../services/care_plan_service.dart';

class ClockInOutPage extends StatefulWidget {
  final Employee employee;

  const ClockInOutPage({super.key, required this.employee});

  @override
  State<ClockInOutPage> createState() => _ClockInOutPageState();
}

class _ClockInOutPageState extends State<ClockInOutPage> {
  final _service = CarePlanService();
  bool _isLoading = true;

  List<Shift> _payrollBlocks = [];
  Map<int, List<Shift>> _blockChildren = {};
  List<Shift> _standaloneVisits = [];

  Shift? _clockedInShift;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Check for active shift
      final activeResponse = await supabase
          .from('shift')
          .select('''
*,
client:client_final!fk_shift_client(
  *,
  care_plans(
    *,
    care_plan_tasks(*)
  )
)
''')
          .eq('emp_id', widget.employee.empId)
          .not('clock_in', 'is', null)
          .filter('clock_out', 'is', null)
          .order('clock_in', ascending: false)
          .limit(1)
          .maybeSingle();

      print('Active Response: ${jsonEncode(activeResponse)}');

      _clockedInShift =
          activeResponse != null ? Shift.fromJson(activeResponse) : null;

      // 2. Fetch all shifts for today (One Query)
      final allShifts = await _service.getAllShiftsToday(widget.employee.empId);

      List<Shift> blocks = [];
      Map<int, List<Shift>> children = {};
      List<Shift> standalone = [];

      for (var s in allShifts) {
        if (s.isBlock) {
          blocks.add(s);
        } else if (s.isBlockChild) {
          children.putIfAbsent(s.parentBlockId!, () => []).add(s);
        } else if (s.isStandalone) {
          standalone.add(s);
        }
      }

      setState(() {
        _payrollBlocks = blocks;
        _blockChildren = children;
        _standaloneVisits = standalone;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading clock in data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _navigateToTracking(Shift shift) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (context) => TimeTrackingPage(
                employee: widget.employee,
                scheduleId: shift.shiftId.toString())))
        .then((_) => _loadData());
  }

  void _showChildShifts(Shift blockShift) {
    final children = _blockChildren[blockShift.shiftId] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _BlockChildsSheet(
          blockShift: blockShift,
          employee: widget.employee,
          initialChildren: children, // Pass existing children
          onChildSelected: (childShift) {
            Navigator.pop(context);
            _navigateToTracking(childShift);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const CustomLoadingScreen(message: 'Loading your shifts...');
    }

    // IF ALREADY CLOCKED IN, show active session to go to map
    if (_clockedInShift != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('Active Session',
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
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Pulsing active indicator
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.timer,
                            size: 40, color: Color(0xFF2E7D32)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'You are clocked in to shift #${_clockedInShift!.shiftId}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.3),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your session is currently active',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w400),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 16),
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined, size: 20),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text('Go to Live Tracking Map',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    onPressed: () => _navigateToTracking(_clockedInShift!),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Clock In / Out',
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
      ),
      body: RefreshIndicator(
        color: const Color(0xFF1A73E8),
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            // SECTION 1: PAYROLL BLOCKS
            Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A73E8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text('Payroll Blocks',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade800,
                        letterSpacing: -0.3)),
              ],
            ),
            const SizedBox(height: 12),
            if (_payrollBlocks.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No blocks scheduled from today onwards.',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                            fontWeight: FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._payrollBlocks.map((b) => _buildBlockCard(b)),

            const SizedBox(height: 28),

            // SECTION 2: STANDALONE VISITS
            Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF43A047),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text('Standalone Visits',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade800,
                        letterSpacing: -0.3)),
              ],
            ),
            const SizedBox(height: 12),
            if (_standaloneVisits.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No standalone visits scheduled from today onwards.',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                            fontWeight: FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._standaloneVisits.map((s) => _buildStandaloneCard(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockCard(Shift block) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showChildShifts(block),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1A73E8).withValues(alpha: 0.15),
                        const Color(0xFF1A73E8).withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.grid_view_rounded,
                      color: Color(0xFF1A73E8), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(block.department ?? 'Block Assignment',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: -0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('${block.date} • ${block.formattedTimeRange}',
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 13,
                              fontWeight: FontWeight.w400),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_forward_ios,
                      size: 14, color: Color(0xFF1A73E8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandaloneCard(Shift shift) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF43A047).withValues(alpha: 0.15),
                    const Color(0xFF43A047).withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.person_rounded,
                  color: Color(0xFF43A047), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shift.clientName ?? 'Visit #${shift.shiftId}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF1A1A2E),
                          letterSpacing: -0.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${shift.date} • ${shift.formattedTimeRange}',
                      style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                          fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Select',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              onPressed: () => _navigateToTracking(shift),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockChildsSheet extends StatefulWidget {
  final Shift blockShift;
  final Employee employee;
  final List<Shift> initialChildren;
  final Function(Shift) onChildSelected;

  const _BlockChildsSheet({
    required this.blockShift,
    required this.employee,
    required this.initialChildren,
    required this.onChildSelected,
  });

  @override
  State<_BlockChildsSheet> createState() => _BlockChildsSheetState();
}

class _BlockChildsSheetState extends State<_BlockChildsSheet> {
  late List<Shift> _childShifts;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _childShifts = widget.initialChildren;
    if (_childShifts.isEmpty) {
      _loadChildren();
    }
  }

  Future<void> _loadChildren() async {
    setState(() => _isLoading = true);
    try {
      final service = CarePlanService();
      final children = await service.getChildShifts(widget.blockShift.shiftId);
      if (mounted) {
        setState(() {
          _childShifts = children;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
              margin: const EdgeInsets.only(bottom: 20),
            ),
          ),
          Text('Visits in Block #${widget.blockShift.shiftId}',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text(
            'Select a visit to begin tracking',
            style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Expanded(
                child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1A73E8))))
          else if (_childShifts.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_busy_rounded,
                        size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No assigned visits in this block yet.',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15,
                            fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: PrimaryScrollController.of(context),
                itemCount: _childShifts.length,
                itemBuilder: (context, index) {
                  final child = _childShifts[index];
                  final status = child.shiftStatus?.toLowerCase().trim();
                  final isCompleted =
                      status == 'clocked_out' || status == 'completed';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFFF5F7FA)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCompleted
                            ? Colors.grey.shade200
                            : Colors.grey.shade100,
                      ),
                      boxShadow: isCompleted
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                              : const Color(0xFF1A73E8).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isCompleted
                              ? Icons.check_circle_rounded
                              : Icons.person_rounded,
                          color: isCompleted
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF1A73E8),
                          size: 20,
                        ),
                      ),
                      title: Text(child.clientName ?? 'Client Visit',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: isCompleted
                                  ? Colors.grey.shade400
                                  : const Color(0xFF1A1A2E),
                              decoration: isCompleted
                                  ? TextDecoration.lineThrough
                                  : null)),
                      subtitle: Text(
                        '${child.formattedStartTime} - ${child.formattedEndTime}\nStatus: ${child.statusDisplayText}',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                            height: 1.5),
                      ),
                      trailing: isCompleted
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFF4CAF50), size: 24)
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A73E8),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Select',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              onPressed: () =>
                                  widget.onChildSelected(child),
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
