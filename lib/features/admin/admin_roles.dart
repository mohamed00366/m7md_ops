import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';

/// شاشة إدارة الأدوار وصلاحياتها الافتراضية
class AdminRoles extends StatefulWidget {
  const AdminRoles({super.key});

  @override
  State<AdminRoles> createState() => _AdminRolesState();
}

class _AdminRolesState extends State<AdminRoles> {
  RoleDef? _selected;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    // فلترة الأدوار حسب الهرمية: غير Super Admin لا يرى super_admin role
    final visibleRoles = repo.roleDefs.where((r) {
      if (auth.isSuperAdmin) return true;
      return r.key != SystemRoles.superAdmin;
    }).toList();
    if (visibleRoles.isEmpty) {
      return Center(
        child: Text(
          s.isAr ? 'لا توجد أدوار مرئية لك' : 'No visible roles',
          style: const TextStyle(color: AppColors.textSecondaryLight),
        ),
      );
    }
    if (_selected == null || !visibleRoles.contains(_selected)) {
      _selected = visibleRoles.first;
    }

    final selectedPerms = repo.rolePermissions
        .where((rp) => rp.roleId == _selected!.id)
        .map((rp) => rp.permissionId)
        .toSet();

    // تجميع الصلاحيات حسب module
    final modules = <String, List<PermissionDef>>{};
    for (final p in repo.permissionDefs) {
      modules.putIfAbsent(p.module, () => []).add(p);
    }

    return Column(
      children: [
        // ===== شريط الأدوار =====
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: visibleRoles.map((r) {
              final isSel = _selected?.id == r.id;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  selected: isSel,
                  onSelected: (_) => setState(() => _selected = r),
                  label: Text(s.isAr ? r.nameAr : r.nameEn),
                  selectedColor: AppColors.brand,
                  labelStyle: TextStyle(
                    color: isSel ? Colors.white : null,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        // ===== معلومات الدور =====
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isAr ? _selected!.nameAr : _selected!.nameEn,
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textDark
                                : AppColors.textLight,
                            fontSize: 16,
                            fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${selectedPerms.length} ${s.isAr ? "صلاحية" : "permissions"}',
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_selected!.key == SystemRoles.superAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      s.isAr ? 'كل الصلاحيات' : 'All permissions',
                      style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ),
        // ===== شبكة الصلاحيات =====
        Expanded(
          child: _selected!.key == SystemRoles.superAdmin
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.workspace_premium,
                            size: 56, color: AppColors.warning),
                        const SizedBox(height: 12),
                        Text(
                          s.isAr
                              ? 'دور Super Admin يملك كل الصلاحيات تلقائياً'
                              : 'Super Admin has all permissions automatically',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  children: modules.entries.map((entry) {
                    return _ModuleSection(
                      module: entry.key,
                      perms: entry.value,
                      selected: selectedPerms,
                      isAr: s.isAr,
                      isDark: isDark,
                      onToggle: (permId, granted) async {
                        final auth = context.read<AuthProvider>();
                        final byUser = auth.currentUser?.id ?? '';
                        final updated = selectedPerms.toSet();
                        if (granted) {
                          updated.add(permId);
                        } else {
                          updated.remove(permId);
                        }
                        final supaReady = SupabaseService().isReady;
                        if (supaReady) {
                          final ds = SupabaseDataService();
                          final ok = await ds.setRolePermissions(
                              _selected!.id, updated.toList());
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.red,
                                content:
                                    Text(ds.lastError ?? 'Failed to save'),
                              ),
                            );
                            return;
                          }
                        } else {
                          repo.setRolePermissions(
                              _selected!.id, updated.toList(), byUser);
                        }
                        // 🆕 تَحديث صَلاحيّات المُستَخدِم الحاليّ فَوريّاً
                        if (mounted) {
                          try {
                            await context
                                .read<AuthProvider>()
                                .refreshPermissions();
                          } catch (_) {}
                        }
                        if (mounted) setState(() {});
                      },
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _ModuleSection extends StatelessWidget {
  final String module;
  final List<PermissionDef> perms;
  final Set<String> selected;
  final bool isAr;
  final bool isDark;
  final void Function(String permId, bool granted) onToggle;
  const _ModuleSection({
    required this.module,
    required this.perms,
    required this.selected,
    required this.isAr,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.5),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            module.toUpperCase(),
            style: const TextStyle(
                color: AppColors.brand,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          ...perms.map((p) {
            final on = selected.contains(p.id);
            return SwitchListTile(
              title: Text(
                isAr ? p.nameAr : p.nameEn,
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(p.key,
                  style: TextStyle(
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                      fontSize: 9)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: (v) => onToggle(p.id, v),
            );
          }),
        ],
      ),
    );
  }
}
