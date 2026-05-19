// =============================================================================
// 🏷 شارة حالة لِلسَنَدات وَالطَلَبات وَالدُفعات وَالبَلاغات
// =============================================================================
import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'laundry_colors.dart';

class LaundryStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const LaundryStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  factory LaundryStatusBadge.forRequest(LaundryRequestStatus s) {
    return LaundryStatusBadge(
      label: s.labelAr,
      color: _requestColor(s),
      icon: _requestIcon(s),
    );
  }

  factory LaundryStatusBadge.forVoucher(VoucherStatus s) {
    return LaundryStatusBadge(
      label: s.labelAr,
      color: _voucherColor(s),
      icon: _voucherIcon(s),
    );
  }

  factory LaundryStatusBadge.forBatch(BatchStatus s) {
    return LaundryStatusBadge(
      label: s.labelAr,
      color: _batchColor(s),
      icon: _batchIcon(s),
    );
  }

  factory LaundryStatusBadge.forReport(MissingReportStatus s) {
    return LaundryStatusBadge(
      label: s.labelAr,
      color: _reportColor(s),
      icon: _reportIcon(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, color: Colors.white, size: 11),
          if (icon != null) const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // Request
  static Color _requestColor(LaundryRequestStatus s) {
    switch (s) {
      case LaundryRequestStatus.pendingConfirmation:
        return LaundryColors.statusPending;
      case LaundryRequestStatus.confirmedWithChanges:
        return LaundryColors.warning;
      case LaundryRequestStatus.confirmed:
        return LaundryColors.statusConfirmed;
      case LaundryRequestStatus.cancelled:
      case LaundryRequestStatus.expired:
        return LaundryColors.statusDelivered;
    }
  }

  static IconData _requestIcon(LaundryRequestStatus s) {
    switch (s) {
      case LaundryRequestStatus.pendingConfirmation:
        return Icons.hourglass_top;
      case LaundryRequestStatus.confirmedWithChanges:
        return Icons.edit_note;
      case LaundryRequestStatus.confirmed:
        return Icons.check_circle;
      case LaundryRequestStatus.cancelled:
        return Icons.cancel;
      case LaundryRequestStatus.expired:
        return Icons.timer_off;
    }
  }

  // Voucher
  static Color _voucherColor(VoucherStatus s) {
    switch (s) {
      case VoucherStatus.confirmed:
        return LaundryColors.statusConfirmed;
      case VoucherStatus.inLaundry:
        return LaundryColors.statusInLaundry;
      case VoucherStatus.returnedComplete:
        return LaundryColors.success;
      case VoucherStatus.returnedWithMissing:
        return LaundryColors.statusMissing;
      case VoucherStatus.delivered:
        return LaundryColors.statusDelivered;
    }
  }

  static IconData _voucherIcon(VoucherStatus s) {
    switch (s) {
      case VoucherStatus.confirmed:
        return Icons.receipt_long;
      case VoucherStatus.inLaundry:
        return Icons.local_laundry_service;
      case VoucherStatus.returnedComplete:
        return Icons.check_circle;
      case VoucherStatus.returnedWithMissing:
        return Icons.warning;
      case VoucherStatus.delivered:
        return Icons.done_all;
    }
  }

  // Batch
  static Color _batchColor(BatchStatus s) {
    switch (s) {
      case BatchStatus.preparing:
        return LaundryColors.statusPending;
      case BatchStatus.inLaundry:
        return LaundryColors.statusInLaundry;
      case BatchStatus.returned:
        return LaundryColors.success;
      case BatchStatus.closed:
        return LaundryColors.statusDelivered;
    }
  }

  static IconData _batchIcon(BatchStatus s) {
    switch (s) {
      case BatchStatus.preparing:
        return Icons.inventory_2;
      case BatchStatus.inLaundry:
        return Icons.local_shipping;
      case BatchStatus.returned:
        return Icons.move_to_inbox;
      case BatchStatus.closed:
        return Icons.archive;
    }
  }

  // Report
  static Color _reportColor(MissingReportStatus s) {
    switch (s) {
      case MissingReportStatus.open:
        return LaundryColors.danger;
      case MissingReportStatus.underReview:
        return LaundryColors.warning;
      case MissingReportStatus.compensated:
      case MissingReportStatus.found:
      case MissingReportStatus.closed:
        return LaundryColors.success;
    }
  }

  static IconData _reportIcon(MissingReportStatus s) {
    switch (s) {
      case MissingReportStatus.open:
        return Icons.error;
      case MissingReportStatus.underReview:
        return Icons.search;
      case MissingReportStatus.compensated:
        return Icons.payments;
      case MissingReportStatus.found:
        return Icons.task_alt;
      case MissingReportStatus.closed:
        return Icons.lock;
    }
  }
}
