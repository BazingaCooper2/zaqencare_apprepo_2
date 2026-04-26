import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shift_offer_record.dart';
import '../models/employee.dart';
import '../services/shift_offers_service.dart';
import '../main.dart';
import '../widgets/custom_loading_screen.dart';

class ShiftOffersPage extends StatefulWidget {
  final Employee employee;

  const ShiftOffersPage({super.key, required this.employee});

  @override
  State<ShiftOffersPage> createState() => _ShiftOffersPageState();
}

class _ShiftOffersPageState extends State<ShiftOffersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ShiftOfferRecord> _allOffers = [];
  List<ShiftOfferRecord> _pendingOffers = [];
  List<ShiftOfferRecord> _acceptedOffers = [];
  List<ShiftOfferRecord> _rejectedOffers = [];
  List<ShiftOfferRecord> _todayOffers = [];

  Map<String, int> _counts = {
    'total': 0,
    'pending': 0,
    'accepted': 0,
    'rejected': 0,
    'expired': 0,
    'today': 0,
  };

  double _acceptanceRate = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadOffers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      debugPrint(
          '🔄 REFRESHING OFFERS for EmpID: ${widget.employee.empId} ...');

      // detailed logging for debugging
      final all =
          await ShiftOffersService.fetchAllOffers(widget.employee.empId);
      debugPrint('📊 UI: Loaded ${all.length} total offers');

      final pending =
          await ShiftOffersService.fetchPendingOffers(widget.employee.empId);
      debugPrint('📊 UI: Loaded ${pending.length} pending offers');

      final accepted =
          await ShiftOffersService.fetchAcceptedOffers(widget.employee.empId);
      final rejected =
          await ShiftOffersService.fetchRejectedOffers(widget.employee.empId);
      final counts =
          await ShiftOffersService.getOfferCounts(widget.employee.empId);
      final rate =
          await ShiftOffersService.getAcceptanceRate(widget.employee.empId);

      final now = DateTime.now();
      final todayOffers = all.where((o) {
        if (o.sentAt == null) return false;
        return o.sentAt!.year == now.year &&
            o.sentAt!.month == now.month &&
            o.sentAt!.day == now.day;
      }).toList();

      counts['today'] = todayOffers.length;

      if (!mounted) return;

      setState(() {
        _allOffers = all;
        _pendingOffers = pending;
        _acceptedOffers = accepted;
        _rejectedOffers = rejected;
        _todayOffers = todayOffers;
        _counts = counts;
        _acceptanceRate = rate;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('❌ UI Error loading offers: $e');
      debugPrint(stack.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading offers: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadOffers,
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0EE),
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            const Text('Shift Offers',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
            Text(
              'Available Offers for ID: ${widget.employee.empId}',
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.normal),
            ),
          ],
        ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadOffers,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => _runDiagnostic(context),
            tooltip: 'Diagnostic',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: 'All (${_counts['total']})'),
            Tab(text: 'Pending (${_counts['pending']})'),
            Tab(text: 'Accepted (${_counts['accepted']})'),
            Tab(text: 'Rejected (${_counts['rejected']})'),
            Tab(text: 'Today (${_counts['today']})'),
          ],
        ),
      ),
      body: _isLoading
          ? const CustomLoadingScreen(message: 'Updating marketplace...', isOverlay: true)
          : Column(
              children: [
                _buildModernStatistics(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOffersList(_allOffers, 'No marketplace history'),
                      _buildOffersList(_pendingOffers, 'No open offers available'),
                      _buildOffersList(_acceptedOffers, 'No accepted offers'),
                      _buildOffersList(_rejectedOffers, 'No rejected offers'),
                      _buildOffersList(_todayOffers, 'No new offers today'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModernStatistics() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('TOTAL', _counts['total'].toString(), const Color(0xFF1A73E8)),
          _buildStatItem('PENDING', _counts['pending'].toString(), Colors.orange),
          _buildStatItem('RATE', '${_acceptanceRate.toStringAsFixed(0)}%', Colors.green),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade400, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildOffersList(List<ShiftOfferRecord> offers, String emptyMessage) {
    if (offers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
              child: Icon(Icons.inventory_2_outlined, size: 50, color: Colors.grey.shade300),
            ),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(fontSize: 15, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return AnimationLimiter(
      child: RefreshIndicator(
        onRefresh: _loadOffers,
        color: const Color(0xFF1A73E8),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: offers.length,
          itemBuilder: (context, index) {
            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 375),
              child: SlideAnimation(
                verticalOffset: 30.0,
                child: FadeInAnimation(
                  child: _buildOfferCard(offers[index]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOfferCard(ShiftOfferRecord offer) {
    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;

    switch (offer.status?.toLowerCase()) {
      case 'accepted':
        statusColor = const Color(0xFF2E7D32);
        statusBgColor = const Color(0xFFE8F5E9);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        statusColor = const Color(0xFFC62828);
        statusBgColor = const Color(0xFFFFEBEE);
        statusIcon = Icons.cancel_rounded;
        break;
      case 'pending':
        statusColor = const Color(0xFFEF6C00);
        statusBgColor = const Color(0xFFFFF3E0);
        statusIcon = Icons.hourglass_top_rounded;
        break;
      default:
        statusColor = const Color(0xFF1565C0);
        statusBgColor = const Color(0xFFE3F2FD);
        statusIcon = Icons.info_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showOfferDetails(offer),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'ID: #${offer.offersId}',
                          style: const TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.w800, fontSize: 11),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: statusBgColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor.withOpacity(0.1))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 6),
                            Text(
                              offer.statusDisplay.toUpperCase(),
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.person_outline_rounded, color: Color(0xFF1A1A2E), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CLIENT NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text(offer.clientName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        _buildInfoItem(Icons.calendar_month_rounded, 'DATE', offer.shiftDate ?? 'N/A'),
                        Container(width: 1, height: 24, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(horizontal: 16)),
                        _buildInfoItem(Icons.schedule_rounded, 'TIME', offer.shiftTimeDisplay),
                      ],
                    ),
                  ),
                  if (offer.clientAddress != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Expanded(child: Text(offer.clientAddress!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (offer.isPending)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _handleOfferAction(offer, 'accepted'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A73E8),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Claim Shift', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _handleOfferAction(offer, 'rejected'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFC62828),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: const Color(0xFFC62828).withOpacity(0.2))),
                        ),
                        child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
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

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1A73E8)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5)),
                Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showOfferDetails(ShiftOfferRecord offer) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Colors.white,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Offer Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Offer ID', '#${offer.offersId}'),
            _buildDetailRow('Status', offer.statusDisplay),
            _buildDetailRow('Client', offer.clientName),
            _buildDetailRow('Date', offer.shiftDate ?? 'N/A'),
            _buildDetailRow('Time', offer.shiftTimeDisplay),
            _buildDetailRow('Address', offer.clientAddress ?? 'N/A'),
            _buildDetailRow('Received', offer.formattedSentAt),
            if (offer.responseTime != null) _buildDetailRow('Responded', offer.formattedResponseTime),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(value, style: const TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _handleOfferAction(ShiftOfferRecord offer, String status) async {
    setState(() => _isLoading = true);
    final success = await ShiftOffersService.updateOfferStatus(
      offersId: offer.offersId,
      status: status,
      shiftId: offer.shiftId,
      empId: offer.empId,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marketplace updated successfully'),
          backgroundColor: const Color(0xFF1A73E8),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadOffers();
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update marketplace'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _runDiagnostic(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final sb = StringBuffer();
    sb.writeln('Diagnostic Report for EmpID: ${widget.employee.empId}');
    sb.writeln('--------------------------------------------------');

    try {
      // 1. Check basic connection / RLS visibility
      sb.writeln('1. Checking table access...');
      try {
        final countRes = await supabase
            .from('shift_offers')
            .select()
            .limit(1)
            .count(CountOption.exact);
        sb.writeln('   ✅ Access OK. Visible Total Rows: ${countRes.count}');
      } catch (e) {
        sb.writeln('   ❌ Test Failed. Possible RLS blocking.');
        sb.writeln('   Error: $e');
      }

      // 2. Check for ANY data (raw fetch)
      sb.writeln('\n2. Fetching any 1 row (no filter)...');
      try {
        final anyRow = await supabase.from('shift_offers').select().limit(1);
        if (anyRow.isNotEmpty) {
          sb.writeln('   ✅ Found data: ${anyRow[0].toString()}');
        } else {
          sb.writeln(
              '   ⚠️ No rows returned. Table might be empty or RLS hidden.');
        }
      } catch (e) {
        sb.writeln('   ❌ Error: $e');
      }

      // 3. Check for specific Employee data
      sb.writeln('\n3. Fetching for EmpID ${widget.employee.empId}...');
      try {
        final myRows = await supabase
            .from('shift_offers')
            .select()
            .eq('emp_id', widget.employee.empId)
            .limit(5);
        if (myRows.isNotEmpty) {
          sb.writeln('   ✅ Found ${myRows.length} rows for you.');
          sb.writeln('   First row status: ${myRows[0]['status']}');
        } else {
          sb.writeln('   ⚠️ No rows found for ID ${widget.employee.empId}.');
        }
      } catch (e) {
        sb.writeln('   ❌ Error: $e');
      }
    } catch (e) {
      sb.writeln('\n❌ Critical Error: $e');
    }

    if (context.mounted) {
      Navigator.pop(context); // close loading
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('DB Diagnostic'),
          content: SingleChildScrollView(
            child: Text(
              sb.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _loadOffers();
              },
              child: const Text('Retry Load'),
            ),
          ],
        ),
      );
    }
  }
}
