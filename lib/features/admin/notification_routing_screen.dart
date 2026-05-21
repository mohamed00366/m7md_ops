// =============================================================================
// 🎯 Notification Routing — مَن يَتَلَقَّى ماذا (مَنح/سَحب بِالنَقَرات)
// =============================================================================
// شاشة تُكَمِّل notification_templates_screen:
//   • قَوالِب الإشعارات    → ماذا يُكتَب (title/body/toggles)
//   • شاشة التَوجيه (هُنا) → مَن يَتَلَقَّى (صَلاحِيّات + مَنح مُباشِر + فَلتَر دَولة)
//
// 3 أَقسام:
//   1) قائِمة الـ15 صَلاحِيّة (مَع الأَدوار المُسنَدة + عَدَد المُستَلِمين)
//   2) عِندَ النَقر → preview بِالمُستَلِمين الفِعليّين
//   3) أَزرار "مَنح/سَحب" لِأَيّ مُستَخدِم في النِظام
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/notification_routing_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

class NotificationRoutingScreen extends StatefulWidget {
  const NotificationRoutingScreen({super.key});

  @override
  State<NotificationRoutingScreen> createState() =>
      _NotificationRoutingScreenState();
}

class _NotificationRoutingScreenState extends State<NotificationRoutingScreen> {
  bool _loading = true;
  List<NotificationPermission> _perms = [];
  String _filter = 'all'; // all | leave | hr | forms | attendance | bus | sites | uniform | roster
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _perms = await NotificationRoutingService.instance.listPermissions();
    } catch (_) {
      _perms = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🎯 تَوجيه الإشعارات' : '🎯 Notification Routing',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _intro(isAr),
                _filterBar(isAr),
                Expanded(child: _permsList(isAr)),
              ],
            ),
    );
  }

  Widget _intro(bool isAr) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: AppColors.brand.withOpacity(0.06),
      child: Text(
        isAr
            ? 'كُلّ صَلاحِيّة تَتَحَكَّم بِمَن يَتَلَقَّى نَوع إشعار مُعَيَّن. اضغَط لِمُعايَنة المُستَلِمين فِعلِيّاً وَمَنح/سَحب الصَلاحِيّة.'
            : 'Each permission controls who gets a notification type. Tap to preview live recipients and grant/revoke.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _filterBar(bool isAr) {
    final categories = [
      ('all',        isAr ? 'الكُلّ' : 'All',         Icons.apps),
      ('leave',      isAr ? '🏖 إجازات' : '🏖 Leave',  null),
      ('hr',         isAr ? '👥 HR' : '👥 HR',        null),
      ('forms',      isAr ? '📝 نَماذِج' : '📝 Forms', null),
      ('attendance', isAr ? '⏰ حُضور' : '⏰ Attend',   null),
      ('bus',        isAr ? '🚌 باص' : '🚌 Bus',      null),
      ('sites',      isAr ? '🏢 مَواقِع' : '🏢 Sites', null),
      ('uniform',    isAr ? '👕 يونيفورم' : '👕 Uniform', null),
      ('roster',     isAr ? '📅 روستر' : '📅 Roster', null),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: isAr ? 'ابحَث…' : 'Search…',
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final c = categories[i];
                final selected = _filter == c.$1;
                return ChoiceChip(
                  label: Text(c.$2, style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = c.$1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _permsList(bool isAr) {
    final filtered = _perms.where((p) {
      final matchCat = _filter == 'all' || p.category == _filter;
      final matchSearch = _search.isEmpty ||
          p.key.toLowerCase().contains(_search.toLowerCase()) ||
          p.nameAr.contains(_search) ||
          p.nameEn.toLowerCase().contains(_search.toLowerCase());
      return matchCat && matchSearch;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          isAr ? 'لا تُوجَد نَتائِج' : 'No results',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _permCard(filtered[i], isAr),
    );
  }

  Widget _permCard(NotificationPermission p, bool isAr) {
    final categoryColor = _colorForCategory(p.category);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _openPreview(p),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: categoryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(p.category,
                        style: TextStyle(
                            color: categoryColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAr ? p.nameAr : p.nameEn,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${p.recipientCount} ${isAr ? "مُستَلِم" : "recipients"}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppColors.brand),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(p.key,
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              if (p.roleKeys.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: p.roleKeys
                      .map((r) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(r,
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ))
                      .toList(),
                )
              else
                Text(
                  isAr ? '⚠️ لا أَدوار مُسنَدة' : '⚠️ No roles assigned',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.warning),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorForCategory(String cat) {
    switch (cat) {
      case 'leave':
        return Colors.teal;
      case 'hr':
        return Colors.indigo;
      case 'forms':
        return Colors.purple;
      case 'attendance':
        return AppColors.brand;
      case 'bus':
        return Colors.deepOrange;
      case 'sites':
        return Colors.green;
      case 'uniform':
        return Colors.brown;
      case 'roster':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  void _openPreview(NotificationPermission p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecipientsPreview(perm: p, onRefresh: _load),
    );
  }
}

// ============================================================
// Preview bottom-sheet: المُستَلِمون الفِعليّون + مَنح/سَحب
// ============================================================
class _RecipientsPreview extends StatefulWidget {
  final NotificationPermission perm;
  final VoidCallback onRefresh;
  const _RecipientsPreview({required this.perm, required this.onRefresh});

  @override
  State<_RecipientsPreview> createState() => _RecipientsPreviewState();
}

class _RecipientsPreviewState extends State<_RecipientsPreview> {
  bool _loading = true;
  String? _countryId; // null = no filter
  List<NotificationRecipient> _recipients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _recipients = await NotificationRoutingService.instance
          .previewRecipients(widget.perm.key, countryId: _countryId);
    } catch (_) {
      _recipients = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final countries = MockRepository().countries;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isAr ? widget.perm.nameAr : widget.perm.nameEn,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900)),
                      Text(widget.perm.key,
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontFamily: 'monospace')),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 14),
          // فَلتَر دَولة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.public,
                    size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Text(isAr ? 'فَلتَر دَولة:' : 'Country filter:',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(isAr ? 'بِدون' : 'None',
                                style: const TextStyle(fontSize: 10)),
                            selected: _countryId == null,
                            onSelected: (_) {
                              setState(() => _countryId = null);
                              _load();
                            },
                          ),
                        ),
                        ...countries.map((c) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: ChoiceChip(
                                label: Text(c.nameEn,
                                    style: const TextStyle(fontSize: 10)),
                                selected: _countryId == c.id,
                                onSelected: (_) {
                                  setState(() => _countryId = c.id);
                                  _load();
                                },
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _recipients.isEmpty
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        isAr
                            ? 'لا يُوجَد مُستَلِمون مَع هذا الفَلتَر'
                            : 'No recipients with this filter',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ))
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: _recipients.length,
                      itemBuilder: (_, i) =>
                          _recipientCard(_recipients[i], isAr),
                    ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.person_add, size: 16),
              label: Text(isAr ? 'مَنح لِشَخص آخَر' : 'Grant to another user'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipientCard(NotificationRecipient r, bool isAr) {
    final isDirect = r.source.startsWith('🎯');
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor:
              r.isSuperAdmin ? Colors.amber.shade200 : Colors.grey.shade300,
          child: Text(r.fullName.isNotEmpty ? r.fullName[0] : '?',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900)),
        ),
        title: Text(r.fullName,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.source,
                style: TextStyle(
                    fontSize: 10,
                    color: r.isSuperAdmin
                        ? Colors.amber.shade800
                        : Colors.grey.shade700)),
            if (r.countries.isNotEmpty)
              Text(r.countries.join(' · '),
                  style: const TextStyle(fontSize: 9)),
          ],
        ),
        trailing: isDirect
            ? IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 18),
                tooltip: isAr ? 'سَحب المَنح' : 'Revoke',
                onPressed: () => _revoke(r),
              )
            : Tooltip(
                message: isAr ? 'مَنح عَبر دَور' : 'Via role',
                child: const Icon(Icons.workspace_premium,
                    size: 16, color: Colors.grey),
              ),
      ),
    );
  }

  Future<void> _revoke(NotificationRecipient r) async {
    final isAr = AppStrings.of(context).isAr;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'سَحب الصَلاحِيّة؟' : 'Revoke permission?'),
        content: Text(isAr
            ? '${r.fullName} لَن يَستَلِم هذه الإشعارات بَعد الآن.'
            : '${r.fullName} will no longer receive these notifications.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(isAr ? 'سَحب' : 'Revoke'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await NotificationRoutingService.instance
        .revokeFromUser(r.accountId, widget.perm.key);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(isAr ? '✅ تَمّ السَحب' : '✅ Revoked'),
      ));
      widget.onRefresh();
      _load();
    }
  }

  Future<void> _openAddDialog() async {
    final isAr = AppStrings.of(context).isAr;
    final accounts = MockRepository().accounts;
    final search = TextEditingController();
    final picked = await showModalBottomSheet<AppAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(builder: (ctx, setSt) {
          final filtered = accounts
              .where((a) =>
                  query.isEmpty ||
                  a.fullName.toLowerCase().contains(query.toLowerCase()) ||
                  a.username.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: search,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText:
                          isAr ? 'ابحَث عَن مُستَخدِم…' : 'Search user…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setSt(() => query = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final a = filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(a.fullName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(a.username,
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => Navigator.pop(ctx, a),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );

    if (picked == null) return;
    final ok = await NotificationRoutingService.instance
        .grantToUser(picked.id, widget.perm.key);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(isAr
            ? '✅ تَمّ مَنح ${picked.fullName}'
            : '✅ Granted to ${picked.fullName}'),
      ));
      widget.onRefresh();
      _load();
    }
  }
}
