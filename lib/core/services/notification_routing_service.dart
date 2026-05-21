// =============================================================================
// 🎯 خِدمة تَوجيه الإشعارات — تَكشِف عَن صَلاحِيّات notifications.receive.*
// وَتَسمَح بِمَنح/سَحب الإسناد + مَعاينة المُستَلِمين الفِعليّين.
// =============================================================================
import 'supabase_service.dart';

/// مَجموعة صَلاحِيّة استِقبال إشعار + الأَدوار المُسنَدة + عَدَد المُستَلِمين
class NotificationPermission {
  final String key;           // notifications.receive.leave.approval_requests
  final String nameAr;
  final String nameEn;
  final String module;        // notifications
  final List<String> roleKeys; // [manager, hr_manager, admin, ...]
  final int recipientCount;   // كَم مُستَلِم نَشِط (قَبل فَلتَر الدَولة)

  NotificationPermission({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.module,
    required this.roleKeys,
    required this.recipientCount,
  });

  /// مُلَخَّص الفِئة: leave / hr / forms / attendance / bus / sites / uniform / roster
  String get category {
    final parts = key.split('.');
    if (parts.length >= 3) return parts[2];
    return 'other';
  }

  String get eventName {
    final parts = key.split('.');
    if (parts.length >= 4) return parts[3];
    return '';
  }
}

/// مُستَلِم فِعليّ لِإشعار (يَعمَل كَـ "preview" قَبل أَن يُرسَل)
class NotificationRecipient {
  final String accountId;
  final String username;
  final String fullName;
  final bool isSuperAdmin;
  final List<String> countries;
  final String source; // 'role:<roleKey>' أَو 'direct'
  NotificationRecipient({
    required this.accountId,
    required this.username,
    required this.fullName,
    required this.isSuperAdmin,
    required this.countries,
    required this.source,
  });
}

class NotificationRoutingService {
  NotificationRoutingService._();
  static final instance = NotificationRoutingService._();

  /// 1️⃣ كُلّ صَلاحِيّات الإشعار + الأَدوار المُسنَدة + عَدَد المُستَلِمين
  Future<List<NotificationPermission>> listPermissions() async {
    final c = SupabaseService().client;

    final perms = await c
        .from('permissions')
        .select('id, key, name_ar, name_en, module')
        .like('key', 'notifications.receive.%')
        .order('key');

    final list = <NotificationPermission>[];
    for (final p in (perms as List).cast<Map<String, dynamic>>()) {
      final permId = p['id'];

      // الأَدوار المُسنَدة لِهذه الصَلاحِيّة
      final roleRows = await c
          .from('role_permissions')
          .select('roles(key)')
          .eq('permission_id', permId);
      final roleKeys = (roleRows as List)
          .map((r) {
            final role = (r as Map)['roles'];
            return role is Map ? role['key'] as String? : null;
          })
          .where((k) => k != null)
          .cast<String>()
          .toList()
        ..sort();

      // عَدَد المُستَلِمين (المُستَخدِمون النَشِطون الذين لَدَيهم الصَلاحِيّة عَبر دَور أَو مُباشَرَةً)
      int count = 0;
      try {
        final res = await c.rpc('count_notification_recipients', params: {
          'p_permission_key': p['key'],
        });
        if (res is int) count = res;
        if (res is num) count = res.toInt();
      } catch (_) {
        // fallback: قَدِّر بِناءً عَلى عَدَد الأَدوار (تَقريبيّ)
        count = roleKeys.length;
      }

      list.add(NotificationPermission(
        key: p['key'] as String,
        nameAr: (p['name_ar'] ?? '') as String,
        nameEn: (p['name_en'] ?? '') as String,
        module: (p['module'] ?? '') as String,
        roleKeys: roleKeys,
        recipientCount: count,
      ));
    }
    return list;
  }

  /// 2️⃣ مَعاينة المُستَلِمين الفِعليّين لِصَلاحِيّة (مَع فَلتَر دَولة اختِياريّ)
  Future<List<NotificationRecipient>> previewRecipients(
    String permissionKey, {
    String? countryId,
  }) async {
    final c = SupabaseService().client;

    // 1) جَلب الحِسابات النَشِطة عَبر الأَدوار
    final viaRoles = await c
        .from('accounts')
        .select(
            'id, username, full_name, is_super_admin, '
            'user_roles(roles(key, role_permissions(permissions(key))))')
        .eq('is_active', true);

    final List<NotificationRecipient> result = [];
    final seen = <String>{};

    for (final row in (viaRoles as List).cast<Map<String, dynamic>>()) {
      final accId = row['id'] as String;
      final isSuper = (row['is_super_admin'] ?? false) as bool;

      // هل لَدَيه الصَلاحِيّة؟ (super_admin = نَعَم تِلقائيّاً)
      bool has = isSuper;
      String? sourceRole;
      if (!has) {
        final urs = row['user_roles'];
        if (urs is List) {
          for (final ur in urs) {
            final role = (ur as Map)['roles'];
            if (role is Map) {
              final perms = role['role_permissions'];
              if (perms is List) {
                for (final rp in perms) {
                  final perm = (rp as Map)['permissions'];
                  if (perm is Map && perm['key'] == permissionKey) {
                    has = true;
                    sourceRole = role['key'] as String?;
                    break;
                  }
                }
              }
            }
            if (has) break;
          }
        }
      }

      if (!has) continue;

      // فَلتَر الدَولة
      if (countryId != null && !isSuper) {
        final hasCountry = await c
            .from('user_countries')
            .select('user_id')
            .eq('user_id', accId)
            .eq('country_id', countryId)
            .maybeSingle();
        if (hasCountry == null) continue;
      }

      // جَلب الدُوَل المُرتَبِطة
      final countries = await c
          .from('user_countries')
          .select('countries(name_en)')
          .eq('user_id', accId);
      final countryNames = (countries as List)
          .map((r) {
            final co = (r as Map)['countries'];
            return co is Map ? co['name_en'] as String? : null;
          })
          .where((n) => n != null)
          .cast<String>()
          .toList();

      if (seen.add(accId)) {
        result.add(NotificationRecipient(
          accountId: accId,
          username: (row['username'] ?? '') as String,
          fullName: (row['full_name'] ?? '') as String,
          isSuperAdmin: isSuper,
          countries: countryNames,
          source: isSuper ? '⭐ super_admin' : 'دَور: ${sourceRole ?? "?"}',
        ));
      }
    }

    // 2) المَنح المُباشِر عَبر user_permission_overrides
    try {
      final direct = await c
          .from('user_permission_overrides')
          .select(
              'user_id, granted, '
              'accounts(id, username, full_name, is_super_admin), '
              'permissions!inner(key)')
          .eq('granted', true)
          .eq('permissions.key', permissionKey);

      for (final r in (direct as List).cast<Map<String, dynamic>>()) {
        final acc = r['accounts'];
        if (acc is! Map) continue;
        final accId = acc['id'] as String;
        if (!seen.add(accId)) continue;

        // فَلتَر الدَولة لِلمَنح المُباشِر
        if (countryId != null && (acc['is_super_admin'] ?? false) != true) {
          final hasCountry = await c
              .from('user_countries')
              .select('user_id')
              .eq('user_id', accId)
              .eq('country_id', countryId)
              .maybeSingle();
          if (hasCountry == null) continue;
        }

        final countries = await c
            .from('user_countries')
            .select('countries(name_en)')
            .eq('user_id', accId);
        final countryNames = (countries as List)
            .map((x) {
              final co = (x as Map)['countries'];
              return co is Map ? co['name_en'] as String? : null;
            })
            .where((n) => n != null)
            .cast<String>()
            .toList();

        result.add(NotificationRecipient(
          accountId: accId,
          username: (acc['username'] ?? '') as String,
          fullName: (acc['full_name'] ?? '') as String,
          isSuperAdmin: (acc['is_super_admin'] ?? false) as bool,
          countries: countryNames,
          source: '🎯 مَنح مُباشِر',
        ));
      }
    } catch (_) {
      // user_permission_overrides قَد لا يُحتَوي عَلى FK joinable
    }

    result.sort((a, b) {
      if (a.isSuperAdmin && !b.isSuperAdmin) return -1;
      if (!a.isSuperAdmin && b.isSuperAdmin) return 1;
      return a.fullName.compareTo(b.fullName);
    });
    return result;
  }

  /// 3️⃣ مَنح صَلاحِيّة إشعار لِمُستَخدِم مُحَدَّد (override مُباشِر)
  Future<bool> grantToUser(String accountId, String permissionKey) async {
    try {
      final c = SupabaseService().client;
      final perm = await c
          .from('permissions')
          .select('id')
          .eq('key', permissionKey)
          .single();
      await c.from('user_permission_overrides').upsert({
        'user_id': accountId,
        'permission_id': perm['id'],
        'granted': true,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 4️⃣ سَحب صَلاحِيّة إشعار من مُستَخدِم
  Future<bool> revokeFromUser(String accountId, String permissionKey) async {
    try {
      final c = SupabaseService().client;
      final perm = await c
          .from('permissions')
          .select('id')
          .eq('key', permissionKey)
          .single();
      await c
          .from('user_permission_overrides')
          .delete()
          .eq('user_id', accountId)
          .eq('permission_id', perm['id']);
      return true;
    } catch (_) {
      return false;
    }
  }
}
