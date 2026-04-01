import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../models/shift.dart';
import '../main.dart';
import 'time_tracking_page.dart';
import '../widgets/custom_loading_screen.dart';

class ClockInOutPage extends StatefulWidget {
  final Employee employee;

  const ClockInOutPage({super.key, required this.employee});

  @override
  State<ClockInOutPage> createState() => _ClockInOutPageState();
}

class _ClockInOutPageState extends State<ClockInOutPage> {
  bool _isLoading = true;
  List<Shift> _payrollBlocks = [];
  List<Shift> _standaloneVisits = [];
  Shift? _clockedInShift;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final todayStr = now.toIso8601String().substring(0, 10);
    
    try {
      // Check if already clocked in somewhere
      try {
        final activeShiftData = await supabase
            .from('shift')
            .select('*, client(*)')
            .eq('emp_id', widget.employee.empId)
            .not('clock_in', 'is', null)
            .filter('clock_out', 'is', null)
            .order('clock_in', ascending: false)
            .limit(1)
            .maybeSingle();
            
        if (activeShiftData != null) {
           _clockedInShift = Shift.fromJson(activeShiftData);
        } else {
           _clockedInShift = null;
        }
      } catch (_) {}

      // 1. Fetch Payroll Blocks
      final blocksResponse = await supabase
          .from('shift')
          .select('*')
          .eq('emp_id', widget.employee.empId)
          .eq('shift_mode', 'block')
          .isFilter('parent_block_id', null)
          .gte('date', todayStr)
          .order('date');

      // 2. Fetch Standalone Visits
      final standaloneResponse = await supabase
          .from('shift')
          .select('*, client_final(*)')
          .eq('emp_id', widget.employee.empId)
          .eq('shift_mode', 'individual')
          .isFilter('parent_block_id', null)
          .gte('date', todayStr)
          .order('date');

      setState(() {
        _payrollBlocks = (blocksResponse as List).map((e) => Shift.fromJson(e)).toList();
        _standaloneVisits = (standaloneResponse as List).map((e) {
             final s = Shift.fromJson(e);
             if (e['client_final'] != null && e['client_final'].isNotEmpty) {
                 return s.copyWith(client: s.client); // already mapped in fromJson fallback handles client_final occasionally
             }
             return s;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading clock in data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading shifts: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _navigateToTracking(Shift shift) {
      Navigator.of(context).push(
         MaterialPageRoute(builder: (context) => TimeTrackingPage(employee: widget.employee, scheduleId: shift.shiftId.toString()))
      ).then((_) => _loadData());
  }

  void _showChildShifts(Shift blockShift) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _BlockChildsSheet(
          blockShift: blockShift,
          employee: widget.employee,
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
         appBar: AppBar(title: const Text('Active Session')),
         body: Center(
            child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                   const Icon(Icons.timer, size: 60, color: Colors.green),
                   const SizedBox(height: 16),
                   Text('You are clocked in to shift #${_clockedInShift!.shiftId}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 24),
                   ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15), backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      child: const Text('Go to Live Tracking Map', style: TextStyle(fontSize: 16)),
                      onPressed: () => _navigateToTracking(_clockedInShift!),
                   )
               ]
            )
         )
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clock In / Out'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
             // SECTION 1: PAYROLL BLOCKS
             Text('Payroll Blocks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
             const SizedBox(height: 8),
             if (_payrollBlocks.isEmpty)
                Card(
                   color: Colors.grey.shade100,
                   child: const Padding(padding: EdgeInsets.all(16), child: Text('No blocks scheduled from today onwards.'))
                )
             else
                ..._payrollBlocks.map((b) => _buildBlockCard(b)),
             
             const SizedBox(height: 24),
             
             // SECTION 2: STANDALONE VISITS
             Text('Standalone Visits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
             const SizedBox(height: 8),
             if (_standaloneVisits.isEmpty)
                Card(
                   color: Colors.grey.shade100,
                   child: const Padding(padding: EdgeInsets.all(16), child: Text('No standalone visits scheduled from today onwards.'))
                )
             else
                ..._standaloneVisits.map((s) => _buildStandaloneCard(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockCard(Shift block) {
      return Card(
         margin: const EdgeInsets.only(bottom: 12),
         elevation: 2,
         child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.blue.shade100, child: const Icon(Icons.grid_view, color: Colors.blue)),
            title: Text(block.department ?? 'Block Assignment', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${block.date} • ${block.formattedTimeRange}'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showChildShifts(block),
         )
      );
  }

  Widget _buildStandaloneCard(Shift shift) {
      return Card(
         margin: const EdgeInsets.only(bottom: 12),
         elevation: 2,
         child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.green.shade100, child: const Icon(Icons.person, color: Colors.green)),
            title: Text(shift.clientName ?? 'Visit #${shift.shiftId}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${shift.date} • ${shift.formattedTimeRange}'),
            trailing: ElevatedButton(
               style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
               child: const Text('Select'),
               onPressed: () => _navigateToTracking(shift),
            )
         )
      );
  }
}

class _BlockChildsSheet extends StatefulWidget {
  final Shift blockShift;
  final Employee employee;
  final Function(Shift) onChildSelected;

  const _BlockChildsSheet({required this.blockShift, required this.employee, required this.onChildSelected});

  @override
  State<_BlockChildsSheet> createState() => _BlockChildsSheetState();
}

class _BlockChildsSheetState extends State<_BlockChildsSheet> {
  List<Shift> _childShifts = [];
  bool _isLoading = true;

  @override
  void initState() {
     super.initState();
     _loadChildren();
  }

  Future<void> _loadChildren() async {
     try {
         final response = await supabase
             .from('shift')
             .select('*, client:client_final(*)')
             .eq('parent_block_id', widget.blockShift.shiftId)
             .order('shift_start_time');
             
         setState(() {
            _childShifts = (response as List).map((e) => Shift.fromJson(e)).toList();
            _isLoading = false;
         });
     } catch (e) {
         setState(() => _isLoading = false);
     }
  }

  @override
  Widget build(BuildContext context) {
     return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
               Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 16))
               ),
               Text('Visits in Block #${widget.blockShift.shiftId}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
               const SizedBox(height: 16),
               if (_isLoading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
               else if (_childShifts.isEmpty)
                  const Expanded(child: Center(child: Text('No assigned visits in this block yet.')))
               else
                  Expanded(
                     child: ListView.builder(
                        controller: PrimaryScrollController.of(context),
                        itemCount: _childShifts.length,
                        itemBuilder: (context, index) {
                           final child = _childShifts[index];
                           final status = child.shiftStatus?.toLowerCase().trim();
                           final isCompleted = status == 'clocked_out' || status == 'completed';
                           return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: isCompleted ? Colors.grey.shade100 : Colors.white,
                              child: ListTile(
                                 title: Text(child.clientName ?? 'Client Visit', style: TextStyle(fontWeight: FontWeight.bold, decoration: isCompleted ? TextDecoration.lineThrough : null)),
                                 subtitle: Text('${child.formattedStartTime} - ${child.formattedEndTime}\nStatus: ${child.statusDisplayText}'),
                                 trailing: isCompleted ? const Icon(Icons.check_circle, color: Colors.green) : ElevatedButton(
                                    child: const Text('Select'),
                                    onPressed: () => widget.onChildSelected(child),
                                 ),
                              )
                           );
                        }
                     )
                  )
           ]
        )
     );
  }
}
