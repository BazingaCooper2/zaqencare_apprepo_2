import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/shift.dart';
import '../models/employee.dart';
import '../services/care_plan_service.dart';
import '../widgets/shift_card_widgets.dart';
import 'block_slots_screen.dart';
import 'task_list_screen.dart';
import 'client_details_screen.dart';

/// ✅ ShiftDashboardScreen
/// Displays today's shifts for the logged-in employee.
/// Individual shifts → full card with Clock In/Out, Tasks, Details.
/// Block Parent shifts → only "View Slots".
class ShiftDashboardScreen extends StatefulWidget {
  final Employee employee;

  const ShiftDashboardScreen({super.key, required this.employee});

  @override
  State<ShiftDashboardScreen> createState() => _ShiftDashboardScreenState();
}

class _ShiftDashboardScreenState extends State<ShiftDashboardScreen> {
  final _service = CarePlanService();
  
  List<Shift> _blocks = [];
  Map<int, List<Shift>> _blockChildren = {};
  List<Shift> _standalone = [];
  
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shifts = await _service.getAllShiftsToday(widget.employee.empId);
      
      List<Shift> blocks = [];
      Map<int, List<Shift>> children = {};
      List<Shift> standalone = [];

      for (var s in shifts) {
        if (s.isBlock) {
          blocks.add(s);
        } else if (s.isBlockChild) {
          children.putIfAbsent(s.parentBlockId!, () => []).add(s);
        } else if (s.isStandalone) {
          standalone.add(s);
        }
      }

      if (mounted) {
        setState(() {
          _blocks = blocks;
          _blockChildren = children;
          _standalone = standalone;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFF0F1729),
      appBar: AppBar(
        backgroundColor: const Color(0xFF162040),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Schedule',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              today,
              style: const TextStyle(color: Color(0xFF8892B0), fontSize: 13),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadShifts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF64FFDA)));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadShifts, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_blocks.isEmpty && _standalone.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, color: Colors.white.withValues(alpha: 0.3), size: 64),
            const SizedBox(height: 16),
            Text(
              'No shifts today',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 18),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadShifts,
      color: const Color(0xFF64FFDA),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_blocks.any((b) => _blockChildren.containsKey(b.shiftId))) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Block Assignments',
                style: TextStyle(color: Color(0xFF64FFDA), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ..._blocks
                .where((b) => _blockChildren.containsKey(b.shiftId))
                .map((block) => _BlockParentCard(
                  shift: block,
                  onViewSlots: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlockSlotsScreen(
                          blockShift: block,
                          employee: widget.employee,
                        ),
                      ),
                    );
                    _loadShifts();
                  },
                )),
            const SizedBox(height: 24),
          ],
          if (_standalone.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Standalone Visits',
                style: TextStyle(color: Color(0xFF64FFDA), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ..._standalone.map((shift) => IndividualShiftCard(
                  shift: shift,
                  employee: widget.employee,
                  isClockedIn: shift.isActive,
                  isClockingIn: false,
                  isClockingOut: false,
                  // Dashboard is VIEW ONLY
                  onClockIn: null,
                  onClockOut: null,
                  onViewTasks: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskListScreen(
                          shift: shift,
                          employee: widget.employee,
                        ),
                      ),
                    );
                    _loadShifts();
                  },
                  onViewDetails: shift.clientId != null
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClientDetailsScreen(clientId: shift.clientId!),
                            ),
                          )
                      : null,
                )),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BLOCK PARENT CARD
// ─────────────────────────────────────────────

class _BlockParentCard extends StatelessWidget {
  final Shift shift;
  final VoidCallback onViewSlots;

  const _BlockParentCard({
    required this.shift,
    required this.onViewSlots,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D1B69), Color(0xFF1A1040)],
        ),
        border: Border.all(
            color: const Color(0xFFBB86FC).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.grid_view_rounded,
                    color: Color(0xFFBB86FC), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shift.department ?? 'Block Program',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const ShiftStatusBadge(
                    label: 'BLOCK', color: Color(0xFFBB86FC)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today,
                        color: Color(0xFF8892B0), size: 15),
                    const SizedBox(width: 6),
                    Text(
                      shift.date ?? '',
                      style: const TextStyle(
                          color: Color(0xFF8892B0), fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time,
                        color: Color(0xFF8892B0), size: 15),
                    const SizedBox(width: 6),
                    Text(
                      shift.formattedTimeRange,
                      style: const TextStyle(
                          color: Color(0xFF8892B0), fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB86FC),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text(
                  'View Slots',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: onViewSlots,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
