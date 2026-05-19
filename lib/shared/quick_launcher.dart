import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/services/launcher_history.dart';
import '../core/theme/app_colors.dart';
import '../models/lookups.dart';
import '../models/models.dart';
import '../repositories/mock_repository.dart';
import '../features/admin/config_export_screen.dart';
import '../features/admin/department_profile_screen.dart';
import '../features/admin/employee_profile_screen.dart';
import '../features/admin/impersonate_picker.dart';
import '../features/admin/job_title_profile_screen.dart';
import '../features/admin/system_health_screen.dart';
import '../features/admin/bulk_permissions_matrix_screen.dart';
import '../features/admin/approval_matrix_screen.dart';
import '../features/admin/org_builder_screen.dart';
import '../features/admin/organization_chart_screen.dart';

/// 🔍 المُطلِق السريع (Quick Launcher / Spotlight)
///
/// واجهة بحث عالميّة (مثل Cmd+K) تتيح للمستخدم القفز إلى أيّ كيان في النظام:
///   - موظّفين (بالاسم أو الكود)
///   - مسمّيات وظيفيّة (بالاسم)
///   - أقسام (بالاسم)
///   - نماذج (بالكود أو الاسم)
///
/// كيفيّة الاستخدام:
///   ```dart
///   QuickLauncher.show(context);
///   ```
///
/// أو من خلال زرّ بحث في AppBar.
class QuickLauncher {
  QuickLauncher._();

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _LauncherDialog(),
    );
  }
}

class _LauncherDialog extends StatefulWidget {
  const _LauncherDialog();

  @override
  State<_LauncherDialog> createState() => _LauncherDialogState();
}

class _LauncherDialogState extends State<_LauncherDialog> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    // 🆕 Session 23: تحميل التاريخ
    LauncherHistory.instance.recent().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final results = _search(_query);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== Search bar =====
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.brand, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: isAr
                            ? 'ابحث عن موظف، مسمّى، قسم، نموذج...'
                            : 'Search employee, title, dept, form...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                      onChanged: (v) => setState(() => _query = v.trim()),
                      onSubmitted: (_) {
                        // Open first result
                        final flat = results.expand((g) => g.items).toList();
                        if (flat.isNotEmpty) {
                          flat.first.onTap(context);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Esc',
                  ),
                ],
              ),
            ),
            // ===== Results =====
            Flexible(
              child: results.isEmpty
                  ? _emptyState(isAr)
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final group in results) ...[
                          _GroupHeader(label: isAr ? group.titleAr : group.titleEn),
                          for (final item in group.items)
                            _ResultRow(
                              item: item,
                              onClose: () => Navigator.of(context).pop(),
                            ),
                        ],
                      ],
                    ),
            ),
            // ===== Hint footer =====
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 12, color: Colors.grey[700]),
                  const SizedBox(width: 4),
                  Text(
                    isAr
                        ? 'اضغط Enter للقفز إلى أوّل نتيجة'
                        : 'Press Enter to jump to first result',
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.grey[700]),
                  ),
                  const Spacer(),
                  Text(
                    '${results.fold<int>(0, (sum, g) => sum + g.items.length)} ${isAr ? "نتيجة" : "results"}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w800,
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

  Widget _emptyState(bool isAr) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, color: Colors.grey[400], size: 40),
          const SizedBox(height: 8),
          Text(
            _query.isEmpty
                ? (isAr
                    ? 'ابدأ الكتابة للبحث...'
                    : 'Start typing to search...')
                : (isAr
                    ? 'لا توجد نتائج لـ "$_query"'
                    : 'No results for "$_query"'),
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  List<_ResultGroup> _search(String query) {
    final repo = MockRepository();
    if (query.isEmpty) {
      final groups = <_ResultGroup>[];
      // 🆕 Session 23: التاريخ في الأعلى
      final history = LauncherHistory.instance.recentSync();
      if (history.isNotEmpty) {
        final historyItems = <_ResultItem>[];
        for (final h in history.take(5)) {
          final item = _historyItemToResult(h, repo);
          if (item != null) historyItems.add(item);
        }
        if (historyItems.isNotEmpty) {
          groups.add(_ResultGroup(
            titleAr: '🕒 الأخيرة',
            titleEn: '🕒 Recent',
            items: historyItems,
          ));
        }
      }
      // 🆕 Session 13: الأوامر السريعة
      groups.add(_ResultGroup(
        titleAr: '⚡ أوامر سريعة',
        titleEn: '⚡ Quick Actions',
        items: _quickActions().take(6).toList(),
      ));
      // أوّل 5 موظفين (إن لم تكن في التاريخ)
      if (repo.employees.isNotEmpty) {
        final historyEmpIds = history
            .where((h) => h.kind == 'employee')
            .map((h) => h.id)
            .toSet();
        final freshEmps = repo.employees
            .where((e) => !historyEmpIds.contains(e.id))
            .take(5)
            .toList();
        if (freshEmps.isNotEmpty) {
          groups.add(_ResultGroup(
            titleAr: '⭐ موظفون',
            titleEn: '⭐ Employees',
            items: freshEmps.map((e) => _employeeItem(e)).toList(),
          ));
        }
      }
      return groups;
    }

    final q = query.toLowerCase();
    final groups = <_ResultGroup>[];

    // 🆕 Session 13: الأوامر السريعة (تطابق بالكلمات المفتاحيّة)
    final actions = _quickActions().where((a) {
      // ابحث في العنوان وكلمات مفتاحيّة
      if (a.titleAr.toLowerCase().contains(q)) return true;
      if (a.titleEn.toLowerCase().contains(q)) return true;
      if (a.subtitleAr.toLowerCase().contains(q)) return true;
      if (a.subtitleEn.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
    if (actions.isNotEmpty) {
      groups.add(_ResultGroup(
        titleAr: '⚡ أوامر (${actions.length})',
        titleEn: '⚡ Actions (${actions.length})',
        items: actions,
      ));
    }

    // ===== Employees =====
    final emps = repo.employees
        .where((e) =>
            e.fullName.toLowerCase().contains(q) ||
            e.code.toLowerCase().contains(q))
        .take(8)
        .toList();
    if (emps.isNotEmpty) {
      groups.add(_ResultGroup(
        titleAr: '👤 موظفون (${emps.length})',
        titleEn: '👤 Employees (${emps.length})',
        items: emps.map((e) => _employeeItem(e)).toList(),
      ));
    }

    // ===== Job Titles =====
    final jts = repo.jobTitles
        .where((j) =>
            j.nameAr.toLowerCase().contains(q) ||
            j.nameEn.toLowerCase().contains(q))
        .take(8)
        .toList();
    if (jts.isNotEmpty) {
      groups.add(_ResultGroup(
        titleAr: '💼 مسمّيات (${jts.length})',
        titleEn: '💼 Job Titles (${jts.length})',
        items: jts.map((j) => _jobTitleItem(j)).toList(),
      ));
    }

    // ===== Departments =====
    final depts = repo.departments
        .where((d) =>
            d.nameAr.toLowerCase().contains(q) ||
            d.nameEn.toLowerCase().contains(q))
        .take(8)
        .toList();
    if (depts.isNotEmpty) {
      groups.add(_ResultGroup(
        titleAr: '🏢 أقسام (${depts.length})',
        titleEn: '🏢 Departments (${depts.length})',
        items: depts.map((d) => _departmentItem(d)).toList(),
      ));
    }

    // ===== Form Templates =====
    final forms = repo.formTemplates
        .where((t) =>
            t.code.toLowerCase().contains(q) ||
            t.nameAr.toLowerCase().contains(q) ||
            t.nameEn.toLowerCase().contains(q))
        .take(5)
        .toList();
    if (forms.isNotEmpty) {
      groups.add(_ResultGroup(
        titleAr: '📑 نماذج (${forms.length})',
        titleEn: '📑 Forms (${forms.length})',
        items: forms.map((t) => _formItem(t)).toList(),
      ));
    }

    return groups;
  }

  /// 🆕 Session 13: قائمة الأوامر السريعة المتاحة في المُطلِق
  List<_ResultItem> _quickActions() {
    return [
      _ResultItem(
        icon: Icons.health_and_safety_outlined,
        titleAr: 'صحّة النظام',
        titleEn: 'System Health',
        subtitleAr: 'تحليل الفجوات والمؤشّرات',
        subtitleEn: 'Health KPIs and gaps',
        color: AppColors.success,
        onTap: (ctx) {
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('System Health'),
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              body: const SystemHealthScreen(),
            ),
          ));
        },
      ),
      _ResultItem(
        icon: Icons.security_outlined,
        titleAr: 'مصفوفة الصلاحيّات',
        titleEn: 'Permissions Matrix',
        subtitleAr: 'تحرير جماعيّ لكلّ المسمّيات',
        subtitleEn: 'Bulk edit all job titles',
        color: AppColors.brand,
        onTap: (ctx) {
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Permissions Matrix'),
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
              ),
              body: const BulkPermissionsMatrixScreen(),
            ),
          ));
        },
      ),
      _ResultItem(
        icon: Icons.grid_view_outlined,
        titleAr: 'مصفوفة الموافقات',
        titleEn: 'Approval Matrix',
        subtitleAr: 'سلاسل الموافقات + الفجوات',
        subtitleEn: 'Workflow chains + gaps',
        color: AppColors.warning,
        onTap: (ctx) {
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Approval Matrix'),
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              body: const ApprovalMatrixScreen(),
            ),
          ));
        },
      ),
      _ResultItem(
        icon: Icons.account_tree_outlined,
        titleAr: 'الهيكل التنظيمي',
        titleEn: 'Organization Chart',
        subtitleAr: 'عرض شجريّ للأقسام والمسمّيات',
        subtitleEn: 'Tree view of org',
        color: AppColors.info,
        onTap: (ctx) {
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Organization Chart'),
                backgroundColor: AppColors.info,
                foregroundColor: Colors.white,
              ),
              body: const OrganizationChartScreen(),
            ),
          ));
        },
      ),
      _ResultItem(
        icon: Icons.drag_indicator,
        titleAr: 'محرّر الهيكل (سحب وإفلات)',
        titleEn: 'Org Builder (drag-drop)',
        subtitleAr: 'إعادة ترتيب الأقسام والمسمّيات',
        subtitleEn: 'Restructure org by dragging',
        color: AppColors.purple,
        onTap: (ctx) {
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Org Builder'),
                backgroundColor: AppColors.purple,
                foregroundColor: Colors.white,
              ),
              body: const OrgBuilderScreen(),
            ),
          ));
        },
      ),
      _ResultItem(
        icon: Icons.theater_comedy_outlined,
        titleAr: 'العرض كحساب',
        titleEn: 'Impersonate',
        subtitleAr: 'جرّب التطبيق بعين أيّ موظف',
        subtitleEn: 'Try app as any employee',
        color: AppColors.danger,
        onTap: (ctx) {
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Impersonate'),
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              body: const ImpersonatePicker(),
            ),
          ));
        },
      ),
      _ResultItem(
        icon: Icons.cloud_sync_outlined,
        titleAr: 'تصدير/استيراد JSON',
        titleEn: 'Export/Import Config',
        subtitleAr: 'نسخة احتياطيّة كاملة للإعدادات',
        subtitleEn: 'Backup/restore full config',
        color: AppColors.teal,
        onTap: (ctx) {
          Navigator.of(ctx).pop();
          Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Config Export/Import'),
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              body: const ConfigExportScreen(),
            ),
          ));
        },
      ),
    ];
  }

  /// 🆕 Session 23: حلّ HistoryItem إلى _ResultItem حيّ
  _ResultItem? _historyItemToResult(HistoryItem h, MockRepository repo) {
    switch (h.kind) {
      case 'employee':
        try {
          final e = repo.employees.firstWhere((x) => x.id == h.id);
          return _employeeItem(e);
        } catch (_) {
          return null;
        }
      case 'job_title':
        final jt = repo.jobTitleById(h.id);
        return jt == null ? null : _jobTitleItem(jt);
      case 'department':
        try {
          final d = repo.departments.firstWhere((x) => x.id == h.id);
          return _departmentItem(d);
        } catch (_) {
          return null;
        }
      case 'form':
        try {
          final t = repo.formTemplates.firstWhere((x) => x.id == h.id);
          return _formItem(t);
        } catch (_) {
          return null;
        }
      default:
        return null;
    }
  }

  _ResultItem _employeeItem(Employee e) {
    return _ResultItem(
      icon: Icons.person_outline,
      titleAr: e.fullName,
      titleEn: e.fullName,
      subtitleAr: 'كود: ${e.code}',
      subtitleEn: 'Code: ${e.code}',
      color: AppColors.brand,
      onTap: (ctx) {
        // 🆕 سجّل في التاريخ
        LauncherHistory.instance.add(HistoryItem(
          kind: 'employee',
          id: e.id,
          labelAr: e.fullName,
          labelEn: e.fullName,
        ));
        Navigator.of(ctx).pop();
        Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => EmployeeProfileScreen(employee: e),
        ));
      },
    );
  }

  _ResultItem _jobTitleItem(JobTitle j) {
    final color = _hexToColor(j.color) ?? AppColors.brand;
    return _ResultItem(
      icon: Icons.badge_outlined,
      titleAr: j.nameAr,
      titleEn: j.nameEn,
      subtitleAr: j.level > 0
          ? 'L${j.level} • ${j.dashboardType.label(true)}'
          : j.dashboardType.label(true),
      subtitleEn: j.level > 0
          ? 'L${j.level} • ${j.dashboardType.label(false)}'
          : j.dashboardType.label(false),
      color: color,
      onTap: (ctx) {
        // 🆕 سجّل في التاريخ
        LauncherHistory.instance.add(HistoryItem(
          kind: 'job_title',
          id: j.id,
          labelAr: j.nameAr,
          labelEn: j.nameEn,
        ));
        Navigator.of(ctx).pop();
        Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => JobTitleProfileScreen(jobTitle: j),
        ));
      },
    );
  }

  _ResultItem _departmentItem(Department d) {
    return _ResultItem(
      icon: Icons.apartment_outlined,
      titleAr: d.nameAr,
      titleEn: d.nameEn,
      subtitleAr: d.level > 0 ? 'مستوى ${d.level}' : 'قسم جذر',
      subtitleEn: d.level > 0 ? 'Level ${d.level}' : 'Root department',
      color: AppColors.teal,
      onTap: (ctx) {
        // 🆕 سجّل في التاريخ
        LauncherHistory.instance.add(HistoryItem(
          kind: 'department',
          id: d.id,
          labelAr: d.nameAr,
          labelEn: d.nameEn,
        ));
        Navigator.of(ctx).pop();
        Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => DepartmentProfileScreen(department: d),
        ));
      },
    );
  }

  _ResultItem _formItem(FormTemplate t) {
    return _ResultItem(
      icon: Icons.assignment_outlined,
      titleAr: t.nameAr,
      titleEn: t.nameEn,
      subtitleAr: t.code,
      subtitleEn: t.code,
      color: AppColors.warning,
      onTap: (ctx) {
        // 🆕 سجّل في التاريخ
        LauncherHistory.instance.add(HistoryItem(
          kind: 'form',
          id: t.id,
          labelAr: t.nameAr,
          labelEn: t.nameEn,
        ));
        // ليس لدينا شاشة ملفّ نموذج بعد — نُغلق فقط مع SnackBar
        Navigator.of(ctx).pop();
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Form: ${t.nameAr} (${t.code})'),
        ));
      },
    );
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final s = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Models
// ============================================================

class _ResultGroup {
  final String titleAr;
  final String titleEn;
  final List<_ResultItem> items;
  _ResultGroup({
    required this.titleAr,
    required this.titleEn,
    required this.items,
  });
}

class _ResultItem {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final Color color;
  final void Function(BuildContext) onTap;
  _ResultItem({
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.color,
    required this.onTap,
  });
}

// ============================================================
// Widgets
// ============================================================

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[700],
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final _ResultItem item;
  final VoidCallback onClose;
  const _ResultRow({required this.item, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return InkWell(
      onTap: () => item.onTap(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(item.icon, color: item.color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? item.titleAr : item.titleEn,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isAr ? item.subtitleAr : item.subtitleEn,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 11, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }
}
