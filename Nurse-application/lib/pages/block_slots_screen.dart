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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.blockShift.department ?? 'Block Shift',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Slot Assignments',
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChildShifts,
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
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
                color: colorScheme.onSurface.withValues(alpha: 0.3), size: 64),
            const SizedBox(height: 16),
            Text(
              'No slot assignments for this block',
              style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadChildShifts,
      color: colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _childShifts.length,
        itemBuilder: (context, index) {
          final shift = _childShifts[index];
          
          return PremiumShiftCard(
            shift: shift,
            employee: widget.employee,
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
