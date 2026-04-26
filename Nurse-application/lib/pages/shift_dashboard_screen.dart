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
/// Displays today's schedule for the logged-in employee.
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
      backgroundColor: const Color(0xFFE8F0EE), // Premium light mint background
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        centerTitle: false,
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
              style: TextStyle(
                color: Colors.white.withOpacity(0.6), 
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadShifts,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A1A2E)));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.orange, size: 48),
              const SizedBox(height: 16),
              const Text('Failed to load schedule', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadShifts, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_blocks.isEmpty && _standalone.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available_rounded, color: Colors.grey.shade300, size: 64),
            const SizedBox(height: 16),
            const Text('No shifts for today', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadShifts,
      color: const Color(0xFF1A1A2E),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Block Assignments Section
          if (_blocks.any((b) => _blockChildren.containsKey(b.shiftId))) ...[
            _buildSectionHeader('BLOCK ASSIGNMENTS', Colors.purple),
            const SizedBox(height: 16),
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
            const SizedBox(height: 32),
          ],

          // Standalone Visits Section
          if (_standalone.isNotEmpty) ...[
            _buildSectionHeader('STANDALONE VISITS', const Color(0xFF1A73E8)),
            const SizedBox(height: 16),
            ..._standalone.map((shift) => IndividualShiftCard(
                  shift: shift,
                  employee: widget.employee,
                  isClockedIn: shift.isActive,
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

  Widget _buildSectionHeader(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1A2E), 
            fontSize: 13, 
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
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
                      const ShiftStatusBadge(label: 'BLOCK', color: Colors.purple),
                      const Spacer(),
                      Text(
                        '#${shift.shiftId}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade400),
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
                        child: Icon(Icons.grid_view_rounded, color: Colors.purple.shade400, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shift.department ?? 'Block Program',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text('Assigned Schedule', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _buildInfo(Icons.calendar_today_rounded, shift.date ?? '', 'Date'),
                      const SizedBox(width: 32),
                      _buildInfo(Icons.access_time_rounded, shift.formattedTimeRange, 'Time'),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      label: const Text('View Assigned Slots', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: onViewSlots,
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

  Widget _buildInfo(IconData icon, String text, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.purple.shade400),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A1A2E))),
        ),
      ],
    );
  }
}
