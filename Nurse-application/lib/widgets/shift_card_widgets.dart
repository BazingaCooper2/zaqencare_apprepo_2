import 'package:flutter/material.dart';
import '../models/shift.dart';
import '../models/employee.dart';

// ─────────────────────────────────────────────
// SHARED SHIFT CARD WIDGET (Screenshot 3 Style)
// ─────────────────────────────────────────────

class IndividualShiftCard extends StatelessWidget {
  final Shift shift;
  final Employee employee;
  final VoidCallback onViewTasks;
  final VoidCallback? onViewDetails;

  const IndividualShiftCard({
    super.key,
    required this.shift,
    required this.employee,
    required this.onViewTasks,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = shift.statusColor;
    final statusText = shift.statusDisplayText;
    final formattedDate = shift.clockFormattedDate;
    final timeRangeWithDuration = shift.clockFormattedTimeRangeWithDuration;

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Status Badge & ID
            Row(
              children: [
                _buildStatusBadge(statusText, statusColor),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${shift.shiftId}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const Spacer(),
                if (shift.isBlockChild)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: const Text(
                      'Visit inside Block',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  )
                else if (shift.isIndividualShift)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: const Text(
                      'Standalone Visit',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Client Icon and Name
            Row(
              children: [
                Icon(Icons.person_pin_rounded, color: Colors.teal.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    shift.clientName ?? 'Unknown Client',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF202124),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date & Time Box (Teal Box style from SC 3)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F6F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0EAE8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 20, color: Color(0xFF2E7D6B)),
                      const SizedBox(width: 10),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Color(0xFF202124),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 20, color: Color(0xFF2E7D6B)),
                      const SizedBox(width: 10),
                      Text(
                        timeRangeWithDuration,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF202124),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons (View Details, View Tasks)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onViewDetails != null)
                  OutlinedButton(
                    onPressed: onViewDetails,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00695C),
                      side: const BorderSide(color: Color(0xFFAED581)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('View Details', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onViewTasks,
                  icon: const Icon(Icons.assignment_rounded, size: 18),
                  label: const Text('View Tasks', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE3F2FD),
                    foregroundColor: const Color(0xFF1976D2),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFBBDEFB)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Duration & Overtime Summary Boxes
            Row(
              children: [
                Expanded(
                  child: _buildSummaryBox(
                    'Duration',
                    () {
                      final h = shift.clockDurationHours;
                      if (h == null) return 'N/A';
                      final hrs = h.floor();
                      final mins = ((h - hrs) * 60).round();
                      return mins > 0 ? '${hrs}h ${mins}m' : '${hrs}h';
                    }(),
                    const Color(0xFFE3F2FD),
                    const Color(0xFF1976D2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryBox(
                    'Overtime',
                    () {
                      final h = shift.clockDurationHours;
                      if (h == null) return 'N/A';
                      final ot = h > 8 ? h - 8 : 0.0;
                      final hrs = ot.floor();
                      final mins = ((ot - hrs) * 60).round();
                      return mins > 0 ? '${hrs}h ${mins}m' : '${hrs}h';
                    }(),
                    const Color(0xFFFFF3E0),
                    const Color(0xFFE65100),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
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

  Widget _buildSummaryBox(String label, String value, Color bgColor, Color textColor) {
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

/// Same style as IndividualShiftCard but for block-child shifts.
/// Clock In is removed as per requirement.
class PremiumShiftCard extends StatelessWidget {
  final Shift shift;
  final Employee employee;
  final VoidCallback onViewTasks;
  final VoidCallback? onViewDetails;

  const PremiumShiftCard({
    super.key,
    required this.shift,
    required this.employee,
    required this.onViewTasks,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return IndividualShiftCard(
      shift: shift,
      employee: employee,
      onViewTasks: onViewTasks,
      onViewDetails: onViewDetails,
    );
  }
}

class ShiftStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ShiftStatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
