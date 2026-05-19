import 'package:flutter/material.dart';

import '../../features/admin/account_report_screen.dart';
import '../../features/admin/employee_profile_hub.dart';
import '../../features/camp_boss/buses/bus_hub.dart';
import '../../features/manager/customers/master_report_screen.dart';
import '../../features/manager/customers/point_hub.dart';
import '../../features/manager/customers/site_hub.dart';
import '../../repositories/mock_repository.dart';

/// 🔲 خِدمة QR Codes لِلكِيانات
///
/// تَوليد وَفَكّ روابِط QR بِصيغة `m7://entity/{type}/{id}`.
/// مَثَلاً: `m7://entity/employee/abc123`
///
/// يُمكِن مَسحها بِأَيّ كاميرا QR ثُمَّ فَكّها هُنا لِفَتح Hub الكِيان.
class EntityQrService {
  EntityQrService._();
  static final instance = EntityQrService._();

  static const String _scheme = 'm7';
  static const String _host = 'entity';

  /// تَوليد payload لِلـQR
  String encode({required String entityType, required String entityId}) {
    return '$_scheme://$_host/$entityType/$entityId';
  }

  /// فَكّ payload وَإرجاع (type, id) أَو null لَو غَير صَحيح
  EntityRef? decode(String payload) {
    try {
      final uri = Uri.parse(payload.trim());
      if (uri.scheme != _scheme) return null;
      if (uri.host != _host) return null;
      final parts = uri.pathSegments;
      if (parts.length < 2) return null;
      return EntityRef(type: parts[0], id: parts[1]);
    } catch (_) {
      return null;
    }
  }

  /// فَتح Hub لِلكِيان بِناءً عَلى نَوعه وَمَعرّفه
  bool openInHub(BuildContext context, EntityRef ref) {
    final repo = MockRepository();
    Widget? screen;
    switch (ref.type) {
      case 'employee':
        final e = repo.employees.where((x) => x.id == ref.id).firstOrNull;
        if (e != null) screen = EmployeeProfileHub(employee: e);
        break;
      case 'bus':
        final b = repo.buses.where((x) => x.id == ref.id).firstOrNull;
        if (b != null) screen = BusHub(bus: b);
        break;
      case 'master':
        final m = repo.masters.where((x) => x.id == ref.id).firstOrNull;
        if (m != null) screen = MasterReportScreen(master: m);
        break;
      case 'site':
        final s = repo.sites.where((x) => x.id == ref.id).firstOrNull;
        if (s != null) screen = SiteHub(site: s);
        break;
      case 'point':
        final p = repo.points.where((x) => x.id == ref.id).firstOrNull;
        if (p != null) screen = PointHub(point: p);
        break;
      case 'account':
        final a = repo.accounts.where((x) => x.id == ref.id).firstOrNull;
        if (a != null) screen = AccountReportScreen(account: a);
        break;
    }
    if (screen == null) return false;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
    return true;
  }
}

/// مَرجِع كِيان مُختَصَر
class EntityRef {
  final String type;
  final String id;
  const EntityRef({required this.type, required this.id});

  @override
  String toString() => '$type/$id';
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
