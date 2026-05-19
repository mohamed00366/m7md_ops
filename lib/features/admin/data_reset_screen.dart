// =============================================================================
// 🗑️ Data Reset — consolidated bulk-wipe page
// =============================================================================
// Restricted to Super Admins. Every card asks the user to type 'DELETE' before
// running. Bundles the existing "Clear all rosters" + "Delete specific roster"
// screens as cards, plus 9 additional categories and a numbering reset.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/theme/app_colors.dart';
import 'clear_all_rosters_screen.dart';
import 'delete_specific_roster_screen.dart';

class DataResetScreen extends StatelessWidget {
  const DataResetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('🗑 Data Reset')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '⛔ Restricted to Super Admins only.\n'
              'Data reset operations are destructive and cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🗑 Data Reset'),
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== Top warning banner =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.08),
              border: Border.all(color: AppColors.danger.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.danger, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Every action below permanently deletes data from the '
                    'database. There is no undo. Use only to wipe test data '
                    'before launch or to reset a country onboarding.',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Section: ROSTERS (existing screens, kept as sub-pages) =====
          _section('📅 Rosters'),
          _navCard(
            context,
            icon: Icons.delete_sweep_outlined,
            color: AppColors.danger,
            title: 'Clear all rosters',
            subtitle:
                'Deletes every weekly roster, its assignments, and the bus-plan details derived from them.',
            destination: const ClearAllRostersScreen(),
          ),
          _navCard(
            context,
            icon: Icons.event_busy_outlined,
            color: Colors.deepOrange,
            title: 'Delete a specific roster',
            subtitle: 'Pick one week + point and remove just that roster.',
            destination: const DeleteSpecificRosterScreen(),
          ),

          // ===== Section: TRANSACTIONAL DATA =====
          _section('💼 Transactional data'),
          _wipeCard(
            context,
            icon: Icons.business_outlined,
            color: Colors.indigo,
            title: 'Sites onboarding',
            subtitle:
                'All submitted sites (sites_onboarding rows). The points/sites master tables stay.',
            confirmLabel: 'Wipe all sites',
            action: (ds) => ds.clearAllSites(),
          ),
          _wipeCard(
            context,
            icon: Icons.description_outlined,
            color: Colors.teal,
            title: 'Form submissions',
            subtitle:
                'All form_submissions + form_submission_actions. Templates are preserved.',
            confirmLabel: 'Wipe all submissions',
            action: (ds) => ds.clearAllFormSubmissions(),
          ),
          _wipeCard(
            context,
            icon: Icons.beach_access_outlined,
            color: Colors.amber.shade800,
            title: 'Leave requests + balances',
            subtitle:
                'All employee_leave_requests + employee_leave_balances rows.',
            confirmLabel: 'Wipe all leaves',
            action: (ds) => ds.clearAllLeaves(),
          ),
          _wipeCard(
            context,
            icon: Icons.checkroom_outlined,
            color: Colors.brown,
            title: 'Uniform issues + purchases',
            subtitle:
                'All employee_uniforms + uniform_purchases. The uniform_catalog stays.',
            confirmLabel: 'Wipe uniform records',
            action: (ds) => ds.clearAllUniformData(),
          ),
          _wipeCard(
            context,
            icon: Icons.local_laundry_service_outlined,
            color: Colors.purple,
            title: 'Amana laundry data',
            subtitle:
                'All vouchers, batches, requests, and missing reports.',
            confirmLabel: 'Wipe Amana data',
            action: (ds) => ds.clearAllAmana(),
          ),
          _wipeCard(
            context,
            icon: Icons.access_time_outlined,
            color: Colors.cyan.shade700,
            title: 'Attendance records',
            subtitle: 'All check-in / check-out records.',
            confirmLabel: 'Wipe attendance',
            action: (ds) => ds.clearAllAttendance(),
          ),
          _wipeCard(
            context,
            icon: Icons.directions_bus_outlined,
            color: Colors.green.shade700,
            title: 'Bus shift + trip logs',
            subtitle:
                'All bus_shift_logs + bus_trip_logs + bus_locations. Driver assignments stay.',
            confirmLabel: 'Wipe bus logs',
            action: (ds) => ds.clearAllBusLogs(),
          ),

          // ===== Section: SYSTEM =====
          _section('⚙️ System'),
          _wipeCard(
            context,
            icon: Icons.notifications_off_outlined,
            color: Colors.blueGrey,
            title: 'Notifications history',
            subtitle:
                'All in-app notifications. Templates are preserved.',
            confirmLabel: 'Wipe notifications',
            action: (ds) => ds.clearAllNotifications(),
          ),
          _wipeCard(
            context,
            icon: Icons.devices_other_outlined,
            color: Colors.deepPurple,
            title: 'Device tokens (FCM)',
            subtitle:
                'All registered devices. Users will re-register at their next login.',
            confirmLabel: 'Wipe device tokens',
            action: (ds) => ds.clearAllDeviceTokens(),
          ),
          _wipeCard(
            context,
            icon: Icons.face_retouching_off_outlined,
            color: Colors.pink.shade700,
            title: 'Face enrollments + photos',
            subtitle:
                'Deletes every employee_face_enrollments row, removes the photo files from storage, and resets mustEnrollFace=true on all accounts. Use this if you see false "duplicate face" matches caused by orphaned data.',
            confirmLabel: 'Wipe all photos',
            action: (ds) => ds.clearAllFaceEnrollments(),
          ),
          _wipeCard(
            context,
            icon: Icons.group_remove,
            color: Colors.red.shade800,
            title: '🔥 Delete ALL employees',
            subtitle:
                'Wipes every employee + cascades through rosters, leaves, attendance, bus logs, face data, documents, terminal logs. Accounts are PRESERVED (employee_id is nulled) so you keep your logins. Use only when starting fresh for a new country/season.',
            confirmLabel: 'DELETE all employees',
            confirmWord: 'PURGE',
            highlight: true,
            action: (ds) => ds.clearAllEmployees(),
          ),
          _wipeCard(
            context,
            icon: Icons.restart_alt,
            color: Colors.orange.shade800,
            title: 'Reset numbering counters',
            subtitle:
                'Resets every country_numbering_counters row to 0. Next codes (employee, voucher, …) will start from 1 again.',
            confirmLabel: 'Reset counters',
            confirmWord: 'RESET',
            action: (ds) => ds.resetAllNumberingCounters(),
          ),

          // ===== Section: NUCLEAR =====
          _section('💥 Nuclear option'),
          _wipeCard(
            context,
            icon: Icons.local_fire_department,
            color: Colors.red.shade900,
            title: 'WIPE EVERYTHING (except masters)',
            subtitle:
                'Runs every wipe above in one go: rosters, sites, forms, leaves, uniform, amana, attendance, bus logs, notifications, device tokens, and counter reset.',
            confirmLabel: 'NUCLEAR WIPE',
            confirmWord: 'NUKE',
            highlight: true,
            action: (ds) => _nuclearWipe(ds),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Section header.
  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey),
        ),
      );

  /// Card that navigates to a separate existing screen (Rosters section).
  Widget _navCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => destination),
        ),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  /// Card that opens a confirmation dialog and then runs an inline wipe.
  Widget _wipeCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String confirmLabel,
    required Future<int> Function(SupabaseDataService) action,
    String confirmWord = 'DELETE',
    bool highlight = false,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: highlight ? Colors.red.shade50 : null,
      child: ListTile(
        onTap: () => _runWipe(
          context,
          title: title,
          subtitle: subtitle,
          confirmLabel: confirmLabel,
          confirmWord: confirmWord,
          color: color,
          action: action,
        ),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: highlight ? Colors.red.shade900 : null)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: Icon(Icons.delete_outline, color: color),
      ),
    );
  }

  Future<void> _runWipe(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String confirmLabel,
    required String confirmWord,
    required Color color,
    required Future<int> Function(SupabaseDataService) action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmWipeDialog(
        title: title,
        subtitle: subtitle,
        confirmLabel: confirmLabel,
        confirmWord: confirmWord,
        color: color,
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;

    // Show progress
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Working…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final ds = SupabaseDataService();
    int count = 0;
    String? error;
    try {
      count = await action(ds);
      error = ds.lastError;
    } catch (e) {
      error = e.toString();
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close progress

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          error != null ? AppColors.warning : AppColors.success,
      duration: const Duration(seconds: 5),
      content: Text(
        error != null
            ? '⚠ $title: partial — $error'
            : '✅ $title: $count rows affected',
      ),
    ));
  }

  /// Sequential nuclear wipe — sums up all individual wipes' counts.
  static Future<int> _nuclearWipe(SupabaseDataService ds) async {
    int total = 0;
    final List<Future<int> Function()> steps = [
      () => ds.clearAllRosters(),
      () => ds.clearAllSites(),
      () => ds.clearAllFormSubmissions(),
      () => ds.clearAllLeaves(),
      () => ds.clearAllUniformData(),
      () => ds.clearAllAmana(),
      () => ds.clearAllAttendance(),
      () => ds.clearAllBusLogs(),
      () => ds.clearAllNotifications(),
      () => ds.clearAllDeviceTokens(),
      () => ds.clearAllFaceEnrollments(),
      () => ds.resetAllNumberingCounters(),
    ];
    for (final step in steps) {
      try {
        total += await step();
      } catch (_) {/* keep going */}
    }
    return total;
  }
}

// =============================================================================
// Confirmation dialog — requires typing the confirmWord exactly
// =============================================================================
class _ConfirmWipeDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String confirmLabel;
  final String confirmWord;
  final Color color;
  const _ConfirmWipeDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.confirmWord,
    required this.color,
  });

  @override
  State<_ConfirmWipeDialog> createState() => _ConfirmWipeDialogState();
}

class _ConfirmWipeDialogState extends State<_ConfirmWipeDialog> {
  final _ctrl = TextEditingController();
  bool _ack = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      _ack && _ctrl.text.trim().toUpperCase() == widget.confirmWord;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: widget.color),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitle, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _ack,
            onChanged: (v) => setState(() => _ack = v ?? false),
            title: const Text(
              'I understand this cannot be undone',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Type ${widget.confirmWord} to confirm:',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.confirmWord,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _canConfirm
              ? () => Navigator.pop(context, true)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.color,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.delete_forever, size: 16),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
