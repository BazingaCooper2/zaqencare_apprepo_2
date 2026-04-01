import 'package:flutter/material.dart';
import '../models/shift.dart';
import '../models/employee.dart';
import '../services/care_plan_service.dart';
import '../widgets/shift_card_widgets.dart';
import 'task_list_screen.dart';
import 'client_details_screen.dart';

/// ✅ BlockSlotsScreen
/// Shows all child shifts for a block parent shift.
/// Each child behaves like an individual shift (clock in/out, tasks, details).
class BlockSlotsScreen extends StatefulWidget {
  final Shift blockShift;
  final Employee employee;

  const BlockSlotsScreen({
    super.key,
    required this.blockShift,
    required this.employee,
  });

  @override
  State<BlockSlotsScreen> createState() => _BlockSlotsScreenState();
}

class _BlockSlotsScreenState extends State<BlockSlotsScreen> {
  final _service = CarePlanService();
  List<Shift> _childShifts = [];
  bool _loading = true;
  String? _error;

  final Set<int> _clockingIn = {};
  final Set<int> _clockingOut = {};

  @override
  void initState() {
    super.initState();
    _loadChildShifts();
  }

  Future<void> _loadChildShifts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shifts =
          await _service.getChildShifts(widget.blockShift.shiftId);
      if (mounted) {
        setState(() {
          _childShifts = shifts;
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

  Future<void> _handleClockIn(Shift shift) async {
    if (_clockingIn.contains(shift.shiftId)) return;
    setState(() => _clockingIn.add(shift.shiftId));
    try {
      final ok = await _service.clockInShift(shift.shiftId);
      if (!ok) throw Exception('Clock-in failed');

      if (shift.clientId != null) {
        await _service.autoPopulateTasks(shift.shiftId, shift.clientId!);
      }

      if (mounted) {
        _showSnack('✅ Clocked in!');
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskListScreen(
              shift: shift,
              employee: widget.employee,
            ),
          ),
        );
        _loadChildShifts();
      }
    } catch (e) {
      if (mounted) _showSnack('❌ $e', isError: true);
    } finally {
      if (mounted) setState(() => _clockingIn.remove(shift.shiftId));
    }
  }

  Future<void> _handleClockOut(Shift shift) async {
    if (_clockingOut.contains(shift.shiftId)) return;
    setState(() => _clockingOut.add(shift.shiftId));
    try {
      final allDone = await _service.areAllTasksComplete(shift.shiftId);
      if (!allDone) {
        if (mounted) {
          _showSnack('⚠️ Complete or skip all tasks first.', isError: true);
        }
        return;
      }
      final ok = await _service.clockOutShift(shift.shiftId);
      if (!ok) throw Exception('Clock-out failed');
      if (mounted) {
        _showSnack('✅ Clocked out!');
        _loadChildShifts();
      }
    } catch (e) {
      if (mounted) _showSnack('❌ $e', isError: true);
    } finally {
      if (mounted) setState(() => _clockingOut.remove(shift.shiftId));
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1729),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D1B69),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.blockShift.department ?? 'Block Shift',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Text(
              'Slot Assignments',
              style: TextStyle(color: Color(0xFFBB86FC), fontSize: 13),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadChildShifts,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFBB86FC)));
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
            ElevatedButton(
                onPressed: _loadChildShifts,
                child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_childShifts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_alt_outlined,
                color: Colors.white.withValues(alpha: 0.3), size: 64),
            const SizedBox(height: 16),
            Text(
              'No slot assignments for this block',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadChildShifts,
      color: const Color(0xFFBB86FC),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _childShifts.length,
        itemBuilder: (context, index) {
          final shift = _childShifts[index];
          final isClockedIn =
              shift.shiftStatus?.toLowerCase() == 'in progress' ||
                  shift.shiftStatus?.toLowerCase() == 'in_progress';

          return IndividualShiftCard(
            shift: shift,
            employee: widget.employee,
            isClockedIn: isClockedIn,
            isClockingIn: _clockingIn.contains(shift.shiftId),
            isClockingOut: _clockingOut.contains(shift.shiftId),
            onClockIn: () => _handleClockIn(shift),
            onClockOut: () => _handleClockOut(shift),
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
              _loadChildShifts();
            },
            onViewDetails: shift.clientId != null
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClientDetailsScreen(
                            clientId: shift.clientId!),
                      ),
                    )
                : null,
          );
        },
      ),
    );
  }
}
