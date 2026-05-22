import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/site_onboarding_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rbac.dart';
import '../../models/site_onboarding.dart';
import '../../shared/m7_app_bar.dart';

/// 🏗 تَفاصيل موقِع جَديد + Setup Tracking
///
/// تَعرِض:
///   - مَعلومات الموقِع (عَميل، عُنوان، GPS، صاحِب القَرار…)
///   - الكادر والزِيّ
///   - التَسعير
///   - **Setup Tracking** — أَزرار تَبديل لِكُلّ من HR/uniform/training/equipment
///   - مُلاحَظات
///   - تَغيير الحالة الرَئيسيّة (pending → in_progress → live → archived)
class SiteOnboardingDetail extends StatefulWidget {
  final SiteOnboarding site;
  const SiteOnboardingDetail({super.key, required this.site});

  @override
  State<SiteOnboardingDetail> createState() => _SiteOnboardingDetailState();
}

class _SiteOnboardingDetailState extends State<SiteOnboardingDetail> {
  late final TextEditingController _notesCtrl;
  bool _savingNotes = false;
  bool _changingStatus = false;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.site.setupNotes ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  /// أَحدَث نُسخة من السِجِلّ بَعد التَحديثات
  SiteOnboarding get _site {
    final svc = SiteOnboardingService.instance;
    return svc.items.firstWhere(
      (s) => s.id == widget.site.id,
      orElse: () => widget.site,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();

    final canUpdate = auth.isSuperAdmin ||
        auth.permissions.contains(P.siteOnboardingUpdateSetup);
    final canGoLive = auth.isSuperAdmin ||
        auth.permissions.contains(P.siteOnboardingGoLive);
    final canArchive = auth.isSuperAdmin ||
        auth.permissions.contains(P.siteOnboardingArchive);

    return ChangeNotifierProvider.value(
      value: SiteOnboardingService.instance,
      child: Consumer<SiteOnboardingService>(
        builder: (ctx, svc, _) {
          final site = _site;
          final progress = site.setupProgress;

          return Scaffold(
            appBar: M7AppBar(
              title: site.clientName,
              subtitle: isAr
                  ? site.status.labelAr()
                  : site.status.labelEn(),
              actions: [
                if (_changingStatus)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _ProgressHeader(progress: progress, site: site, isAr: isAr),
                const SizedBox(height: 12),

                // ===== Setup Tracking =====
                _SectionCard(
                  title: isAr ? '🔧 تَتَبُّع التَجهيز' : '🔧 Setup Tracking',
                  child: Column(
                    children: [
                      _TrackingRow(
                        label: isAr ? 'الموارِد البَشَريّة' : 'HR',
                        icon: Icons.badge_outlined,
                        status: site.hrStatus,
                        enabled: canUpdate,
                        onChange: (v) =>
                            _updateSub(site.id, 'hr_status', v, isAr),
                        isAr: isAr,
                      ),
                      _TrackingRow(
                        label: isAr ? 'الزِيّ' : 'Uniform',
                        icon: Icons.checkroom_outlined,
                        status: site.uniformStatus,
                        enabled: canUpdate,
                        onChange: (v) =>
                            _updateSub(site.id, 'uniform_status', v, isAr),
                        isAr: isAr,
                      ),
                      _TrackingRow(
                        label: isAr ? 'التَدريب' : 'Training',
                        icon: Icons.school_outlined,
                        status: site.trainingStatus,
                        enabled: canUpdate,
                        onChange: (v) =>
                            _updateSub(site.id, 'training_status', v, isAr),
                        isAr: isAr,
                      ),
                      _TrackingRow(
                        label: isAr ? 'المُعَدّات' : 'Equipment',
                        icon: Icons.handyman_outlined,
                        status: site.equipmentStatus,
                        enabled: canUpdate,
                        onChange: (v) =>
                            _updateSub(site.id, 'equipment_status', v, isAr),
                        isAr: isAr,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Status transitions =====
                _SectionCard(
                  title: isAr ? '🚦 الحالة' : '🚦 Status',
                  child: _StatusActions(
                    site: site,
                    canGoLive: canGoLive,
                    canArchive: canArchive,
                    onChange: (newStatus) =>
                        _changeStatus(site.id, newStatus, isAr),
                    isAr: isAr,
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Client info =====
                _SectionCard(
                  title: isAr ? '👤 العَميل' : '👤 Client',
                  child: Column(
                    children: [
                      _KV(
                        k: isAr ? 'الاسم' : 'Name',
                        v: site.clientName,
                      ),
                      if (site.industry != null)
                        _KV(
                          k: isAr ? 'القِطاع' : 'Industry',
                          v: site.industry!,
                        ),
                      if (site.address != null)
                        _KV(
                          k: isAr ? 'العُنوان' : 'Address',
                          v: site.address!,
                        ),
                      if (site.gpsLat != null && site.gpsLng != null)
                        _KV(
                          k: 'GPS',
                          v:
                              '${site.gpsLat!.toStringAsFixed(5)}, ${site.gpsLng!.toStringAsFixed(5)}',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Decision maker =====
                if (site.decisionMakerName != null)
                  _SectionCard(
                    title:
                        isAr ? '🧑‍💼 صاحِب القَرار' : '🧑‍💼 Decision Maker',
                    child: Column(
                      children: [
                        _KV(
                          k: isAr ? 'الاسم' : 'Name',
                          v: site.decisionMakerName!,
                        ),
                        if (site.decisionMakerRole != null)
                          _KV(
                            k: isAr ? 'الوَظيفة' : 'Role',
                            v: site.decisionMakerRole!,
                          ),
                        if (site.decisionMakerPhone != null)
                          _KV(
                            k: isAr ? 'الهاتِف' : 'Phone',
                            v: site.decisionMakerPhone!,
                          ),
                        if (site.decisionMakerEmail != null)
                          _KV(
                            k: 'Email',
                            v: site.decisionMakerEmail!,
                          ),
                      ],
                    ),
                  ),
                if (site.decisionMakerName != null) const SizedBox(height: 12),

                // ===== Staff =====
                if (site.staffCount != null)
                  _SectionCard(
                    title: isAr ? '👥 الكادِر' : '👥 Staff',
                    child: Column(
                      children: [
                        _KV(
                          k: isAr ? 'العَدَد' : 'Count',
                          v: '${site.staffCount}',
                        ),
                        if (site.workingHours != null)
                          _KV(
                            k: isAr ? 'ساعات العَمَل' : 'Working hours',
                            v: site.workingHours!,
                          ),
                        if (site.workingDays != null)
                          _KV(
                            k: isAr ? 'أَيّام/أُسبوع' : 'Days/week',
                            v: '${site.workingDays}',
                          ),
                        if (site.jobTitles != null &&
                            site.jobTitles!.isNotEmpty)
                          _KV(
                            k: isAr ? 'المُسَمَّيات' : 'Job titles',
                            v: site.jobTitles!.entries
                                .map((e) => '${e.key}: ${e.value}')
                                .join(' • '),
                          ),
                      ],
                    ),
                  ),
                if (site.staffCount != null) const SizedBox(height: 12),

                // ===== Uniform =====
                if (site.uniformType != null)
                  _SectionCard(
                    title: isAr ? '👕 الزِيّ' : '👕 Uniform',
                    child: Column(
                      children: [
                        _KV(
                          k: isAr ? 'النَوع' : 'Type',
                          v: _uniformLabel(site.uniformType!, isAr),
                        ),
                        if (site.uniformPosition != null)
                          _KV(
                            k: isAr ? 'مَوضِع اللوغو' : 'Logo position',
                            v: site.uniformPosition!,
                          ),
                        if (site.uniformNotes != null &&
                            site.uniformNotes!.isNotEmpty)
                          _KV(
                            k: isAr ? 'مُلاحَظات' : 'Notes',
                            v: site.uniformNotes!,
                          ),
                        if (site.clientDeliveryDate != null)
                          _KV(
                            k: isAr ? 'تاريخ تَسليم العَميل' : 'Delivery date',
                            v: _fmtDate(site.clientDeliveryDate!),
                          ),
                      ],
                    ),
                  ),
                if (site.uniformType != null) const SizedBox(height: 12),

                // ===== Pricing =====
                if (site.pricingMode != null)
                  _SectionCard(
                    title: isAr ? '💰 التَسعير' : '💰 Pricing',
                    child: Column(
                      children: [
                        _KV(
                          k: isAr ? 'الوَضع' : 'Mode',
                          v: _pricingModeLabel(site.pricingMode!, isAr),
                        ),
                        if (site.customerPrice != null)
                          _KV(
                            k: isAr ? 'سِعر العَميل' : 'Customer price',
                            v:
                                '${site.customerPrice} ${site.currency}${site.customerPriceUnit != null ? " / ${site.customerPriceUnit}" : ""}',
                          ),
                        if (site.clientShareValue != null)
                          _KV(
                            k: isAr ? 'نِسبة العَميل' : 'Client share',
                            v:
                                '${site.clientShareValue}${site.clientShareType == 'percentage' ? "%" : " ${site.currency}"}',
                          ),
                        if (site.monthlyInvoiceAmount != null)
                          _KV(
                            k: isAr ? 'الفاتورة الشَهريّة' : 'Monthly invoice',
                            v:
                                '${site.monthlyInvoiceAmount} ${site.currency}',
                          ),
                        if (site.invoiceIssueDay != null)
                          _KV(
                            k: isAr ? 'يَوم إصدار الفاتورة' : 'Invoice day',
                            v: '${site.invoiceIssueDay}',
                          ),
                        if (site.paymentTermsDays != null)
                          _KV(
                            k: isAr ? 'مُهلة السَداد' : 'Payment terms',
                            v:
                                '${site.paymentTermsDays} ${isAr ? "يَوم" : "days"}',
                          ),
                        _KV(
                          k: isAr ? 'ضَريبة' : 'VAT',
                          v: '${site.vatPct}%',
                        ),
                        if (site.customPricingDescription != null &&
                            site.customPricingDescription!.isNotEmpty)
                          _KV(
                            k: isAr ? 'وَصف مُخَصَّص' : 'Custom description',
                            v: site.customPricingDescription!,
                          ),
                      ],
                    ),
                  ),
                if (site.pricingMode != null) const SizedBox(height: 12),

                // ===== Dates =====
                _SectionCard(
                  title: isAr ? '📅 التَواريخ' : '📅 Dates',
                  child: Column(
                    children: [
                      if (site.approvedAt != null)
                        _KV(
                          k: isAr ? 'تَمَّت المُوافَقة' : 'Approved',
                          v: _fmtDate(site.approvedAt!),
                        ),
                      if (site.proposedStartDate != null)
                        _KV(
                          k:
                              isAr ? 'البِداية المُقتَرَحة' : 'Proposed start',
                          v: _fmtDate(site.proposedStartDate!),
                        ),
                      if (site.actualStartDate != null)
                        _KV(
                          k: isAr ? 'البِداية الفِعليّة' : 'Actual start',
                          v: _fmtDate(site.actualStartDate!),
                        ),
                      if (site.contractDurationMonths != null)
                        _KV(
                          k: isAr ? 'مُدّة العَقد' : 'Contract duration',
                          v:
                              '${site.contractDurationMonths} ${isAr ? "شَهر" : "months"}',
                        ),
                      _KV(
                        k: isAr ? 'مُنذ المُوافَقة' : 'Days since approval',
                        v:
                            '${site.daysSinceApproval} ${isAr ? "يَوم" : "days"}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Notes =====
                _SectionCard(
                  title: isAr ? '📝 مُلاحَظات التَجهيز' : '📝 Setup Notes',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 4,
                        enabled: canUpdate && !_savingNotes,
                        decoration: InputDecoration(
                          hintText: isAr
                              ? 'مُلاحَظات…'
                              : 'Notes…',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (canUpdate)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: ElevatedButton.icon(
                            onPressed: _savingNotes
                                ? null
                                : () => _saveNotes(site.id, isAr),
                            icon: _savingNotes
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(isAr ? 'حِفظ' : 'Save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brand,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // Actions
  // ============================================================
  Future<void> _updateSub(
    String siteId,
    String field,
    SetupSubStatus v,
    bool isAr,
  ) async {
    final ok = await SiteOnboardingService.instance.updateSubStatus(
      siteId: siteId,
      field: field,
      newStatus: v,
    );
    if (!mounted) return;
    if (!ok) {
      _toast(isAr ? 'تَعَذَّر التَحديث' : 'Update failed', isError: true);
    }
  }

  Future<void> _changeStatus(
    String siteId,
    SiteStatus newStatus,
    bool isAr,
  ) async {
    setState(() => _changingStatus = true);
    final ok = await SiteOnboardingService.instance.updateStatus(
      siteId: siteId,
      newStatus: newStatus,
      actualStartDate:
          newStatus == SiteStatus.live ? DateTime.now() : null,
    );
    if (!mounted) return;
    setState(() => _changingStatus = false);
    if (!ok) {
      _toast(isAr ? 'تَعَذَّر التَحديث' : 'Status change failed',
          isError: true);
    } else {
      _toast(isAr ? 'تَمَّ بِنَجاح' : 'Updated');
    }
  }

  Future<void> _saveNotes(String siteId, bool isAr) async {
    setState(() => _savingNotes = true);
    final ok = await SiteOnboardingService.instance.updateSetupNotes(
      siteId: siteId,
      notes: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _savingNotes = false);
    if (!ok) {
      _toast(isAr ? 'تَعَذَّر الحِفظ' : 'Save failed', isError: true);
    } else {
      _toast(isAr ? 'حُفِظَت' : 'Saved');
    }
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  // ============================================================
  // Helpers
  // ============================================================
  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _pricingModeLabel(String mode, bool isAr) {
    switch (mode) {
      case 'cash_to_company':
        return isAr ? 'كاش لِلشَركة' : 'Cash to company';
      case 'cash_with_client_share':
        return isAr ? 'كاش مَع نِسبة لِلعَميل' : 'Cash + client share';
      case 'cash_to_client_we_invoice':
        return isAr
            ? 'كاش لِلعَميل + فاتورة شَهريّة'
            : 'Cash to client + monthly invoice';
      case 'free_we_invoice':
        return isAr
            ? 'مَجّاناً + فاتورة شَهريّة'
            : 'Free + monthly invoice';
      default:
        return isAr ? 'مُخَصَّص' : 'Custom';
    }
  }

  static String _uniformLabel(String type, bool isAr) {
    switch (type) {
      case 'company':
        return isAr ? 'زِيّ الشَركة' : 'Company uniform';
      case 'client_specified':
        return isAr ? 'يُحَدِّده العَميل' : 'Client specified';
      case 'client_supplied':
        return isAr ? 'يُسَلِّمه العَميل' : 'Client supplied';
      default:
        return type;
    }
  }
}

// ============================================================
// 🧱 Section card
// ============================================================
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// Progress header
// ============================================================
class _ProgressHeader extends StatelessWidget {
  final double progress;
  final SiteOnboarding site;
  final bool isAr;
  const _ProgressHeader({
    required this.progress,
    required this.site,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.brand,
            AppColors.brandDark,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isAr ? 'تَقَدُّم التَجهيز' : 'Setup Progress',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${progress.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(
                progress >= 100 ? AppColors.gold : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isAr
                ? '${site.daysSinceApproval} يَوماً مُنذ المُوافَقة'
                : '${site.daysSinceApproval} days since approval',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tracking row (HR / Uniform / Training / Equipment)
// ============================================================
class _TrackingRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final SetupSubStatus status;
  final bool enabled;
  final void Function(SetupSubStatus) onChange;
  final bool isAr;

  const _TrackingRow({
    required this.label,
    required this.icon,
    required this.status,
    required this.enabled,
    required this.onChange,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          DropdownButton<SetupSubStatus>(
            value: status,
            onChanged: enabled
                ? (v) {
                    if (v != null) onChange(v);
                  }
                : null,
            underline: const SizedBox(),
            isDense: true,
            items: SetupSubStatus.values
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        isAr ? s.labelAr() : s.labelEn(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _colorFor(s),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(SetupSubStatus s) {
    switch (s) {
      case SetupSubStatus.pending:
        return Colors.grey;
      case SetupSubStatus.inProgress:
        return AppColors.info;
      case SetupSubStatus.done:
        return AppColors.success;
      case SetupSubStatus.blocked:
        return AppColors.danger;
    }
  }
}

// ============================================================
// Status transition buttons
// ============================================================
class _StatusActions extends StatelessWidget {
  final SiteOnboarding site;
  final bool canGoLive;
  final bool canArchive;
  final void Function(SiteStatus) onChange;
  final bool isAr;

  const _StatusActions({
    required this.site,
    required this.canGoLive,
    required this.canArchive,
    required this.onChange,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final current = site.status;
    final readyForLive = site.isSetupComplete;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // pending → in_progress
        if (current == SiteStatus.pendingSetup)
          _StatusBtn(
            label: isAr ? 'بَدء التَجهيز' : 'Start setup',
            icon: Icons.play_arrow,
            color: AppColors.info,
            onTap: () => onChange(SiteStatus.setupInProgress),
          ),

        // in_progress → live (only if all sub-statuses are done)
        if (current == SiteStatus.setupInProgress && canGoLive)
          _StatusBtn(
            label: isAr ? '🟢 تَفعيل (Go Live)' : '🟢 Go Live',
            icon: Icons.rocket_launch,
            color: AppColors.success,
            disabled: !readyForLive,
            tooltip: !readyForLive
                ? (isAr
                    ? 'يَجب إكمال كُلّ خُطوات التَجهيز أَوّلاً'
                    : 'Complete all setup steps first')
                : null,
            onTap: () => onChange(SiteStatus.live),
          ),

        // live → archived
        if (current == SiteStatus.live && canArchive)
          _StatusBtn(
            label: isAr ? '📦 أَرشَفة' : '📦 Archive',
            icon: Icons.archive_outlined,
            color: Colors.grey,
            onTap: () => onChange(SiteStatus.archived),
          ),

        // archived → live (re-activate)
        if (current == SiteStatus.archived && canGoLive)
          _StatusBtn(
            label: isAr ? 'إعادة التَفعيل' : 'Reactivate',
            icon: Icons.refresh,
            color: AppColors.success,
            onTap: () => onChange(SiteStatus.live),
          ),

        // back to in_progress from pending (manual)
        if (current == SiteStatus.live && canGoLive)
          _StatusBtn(
            label: isAr ? 'العَودة لِلتَجهيز' : 'Back to setup',
            icon: Icons.undo,
            color: AppColors.warning,
            onTap: () => onChange(SiteStatus.setupInProgress),
          ),
      ],
    );
  }
}

class _StatusBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;
  final String? tooltip;

  const _StatusBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.disabled = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = ElevatedButton.icon(
      onPressed: disabled ? null : onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

// ============================================================
// Key/Value row
// ============================================================
class _KV extends StatelessWidget {
  final String k;
  final String v;
  const _KV({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
