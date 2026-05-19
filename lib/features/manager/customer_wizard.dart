import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';
import 'customer_diagram.dart';

/// معالج إنشاء عميل بـ 3 خطوات: Master → Client → Point
/// كل خطوة في تاب منفصل، مع كود تلقائي ومخطط بصري في الأعلى
class CustomerWizardScreen extends StatefulWidget {
  const CustomerWizardScreen({super.key});

  @override
  State<CustomerWizardScreen> createState() => _CustomerWizardScreenState();
}

class _CustomerWizardScreenState extends State<CustomerWizardScreen>
    with TickerProviderStateMixin {
  late TabController _tabs;

  // ===== Master fields =====
  final _masterName = TextEditingController();
  final _masterLicense = TextEditingController();
  final _masterTax = TextEditingController();
  String? _masterIndustryId;
  DateTime? _masterStart;
  final _masterNotes = TextEditingController();

  // ===== Client fields =====
  String? _selectedMasterId;
  bool _autoCreateMaster = true; // افتراضياً تلقائي - يبسّط التجربة
  final _clientCompany = TextEditingController();
  final _clientShort = TextEditingController();
  final _clientAccounting = TextEditingController();
  String? _clientBusinessTypeId;
  final _clientEmail = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientTaxId = TextEditingController();
  final _clientNotes = TextEditingController();
  EntityStatus _clientStatus = EntityStatus.active;

  // ===== Point fields =====
  final _pointName = TextEditingController();
  final _pointDescription = TextEditingController();
  String? _pointCityId;
  String? _pointAreaId;
  final _pointAddress = TextEditingController();
  final _pointLat = TextEditingController();
  final _pointLng = TextEditingController();
  final List<PointClientLink> _linkedPointClients = [];
  String? _selectedClientForLink;
  final _linkUnit = TextEditingController();
  final _linkFloor = TextEditingController();

  // أكواد المعاينة
  String? _masterCodePreview;
  String? _clientCodePreview;
  String? _pointCodePreview;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCodePreviews());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _masterName.dispose();
    _masterLicense.dispose();
    _masterTax.dispose();
    _masterNotes.dispose();
    _clientCompany.dispose();
    _clientShort.dispose();
    _clientAccounting.dispose();
    _clientEmail.dispose();
    _clientPhone.dispose();
    _clientTaxId.dispose();
    _clientNotes.dispose();
    _pointName.dispose();
    _pointDescription.dispose();
    _pointAddress.dispose();
    _pointLat.dispose();
    _pointLng.dispose();
    _linkUnit.dispose();
    _linkFloor.dispose();
    super.dispose();
  }

  String? get _countryId =>
      context.read<AuthProvider>().selectedCountryId;

  void _refreshCodePreviews() {
    final repo = MockRepository();
    final c = _countryId;
    if (c == null) return;
    setState(() {
      _masterCodePreview = repo.previewCodeFor(c, 'master') ?? '—';
      _clientCodePreview = repo.previewCodeFor(c, 'branch') ?? '—';
      _pointCodePreview = repo.previewCodeFor(c, 'pos_point') ?? '—';
    });
  }

  NodeState get _masterNodeState {
    final filled = _masterName.text.trim().isNotEmpty ||
        _selectedMasterId != null ||
        _autoCreateMaster;
    if (_tabs.index == 0) {
      return filled ? NodeState.activeFilled : NodeState.active;
    }
    return filled ? NodeState.filled : NodeState.idle;
  }

  NodeState get _clientNodeState {
    final filled = _clientCompany.text.trim().isNotEmpty;
    if (_tabs.index == 1) {
      return filled ? NodeState.activeFilled : NodeState.active;
    }
    return filled ? NodeState.filled : NodeState.idle;
  }

  NodeState get _pointNodeState {
    final filled = _pointName.text.trim().isNotEmpty;
    if (_tabs.index == 2) {
      return filled ? NodeState.activeFilled : NodeState.active;
    }
    return filled ? NodeState.filled : NodeState.idle;
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final dataService = SupabaseDataService();
    final supaReady = SupabaseService().isReady;
    final countryId = _countryId;
    if (countryId == null) {
      _toast(s.countryRequired, isError: true);
      return;
    }

    if (_clientCompany.text.trim().isEmpty) {
      _toast(s.companyNameRequired, isError: true);
      _tabs.animateTo(1);
      return;
    }

    // helper: توليد كود (Supabase RPC أو Mock)
    Future<String> genCode(String technicalId, String fallback) async {
      if (supaReady) {
        final code = await dataService.consumeNextCode(
          technicalId: technicalId,
          countryId: countryId,
        );
        return code ?? fallback;
      }
      return repo.generateCodeFor(countryId, technicalId) ?? fallback;
    }

    // 1) إنشاء/جلب Master
    String masterId;
    if (_selectedMasterId != null) {
      masterId = _selectedMasterId!;
    } else if (_autoCreateMaster) {
      final code = await genCode('master', 'M-?');
      final m = Master(
        id: repo.generateId(),
        code: code,
        name: _clientCompany.text.trim(),
        countryId: countryId,
        autoCreated: true,
      );
      if (supaReady) {
        final created = await dataService.createMaster(m);
        if (created == null) {
          final err = dataService.lastError ?? '';
          _toast(
              s.isAr
                  ? 'فشل إنشاء Master: ${err.length > 80 ? "${err.substring(0, 80)}..." : err}'
                  : 'Failed to create Master: ${err.length > 80 ? "${err.substring(0, 80)}..." : err}',
              isError: true);
          return;
        }
        masterId = created.id;
      } else {
        repo.addMaster(m);
        masterId = m.id;
      }
    } else if (_masterName.text.trim().isNotEmpty) {
      final code = await genCode('master', 'M-?');
      final m = Master(
        id: repo.generateId(),
        code: code,
        name: _masterName.text.trim(),
        tradeLicense: _masterLicense.text.trim(),
        taxVat: _masterTax.text.trim(),
        industryId: _masterIndustryId,
        startDate: _masterStart,
        notes: _masterNotes.text.trim(),
        countryId: countryId,
      );
      if (supaReady) {
        final created = await dataService.createMaster(m);
        if (created == null) {
          final err = dataService.lastError ?? '';
          _toast(
              s.isAr
                  ? 'فشل إنشاء Master: ${err.length > 80 ? "${err.substring(0, 80)}..." : err}'
                  : 'Failed to create Master: ${err.length > 80 ? "${err.substring(0, 80)}..." : err}',
              isError: true);
          return;
        }
        masterId = created.id;
      } else {
        repo.addMaster(m);
        masterId = m.id;
      }
    } else {
      _toast(s.selectMasterFirst, isError: true);
      _tabs.animateTo(0);
      return;
    }

    // 2) إنشاء Client (Site)
    final clientCode = await genCode('branch', 'C-?');
    final newSite = Site(
      id: repo.generateId(),
      companyName: _clientCompany.text.trim(),
      shortName: _clientShort.text.trim().isEmpty
          ? clientCode
          : _clientShort.text.trim(),
      accountingName: _clientAccounting.text.trim(),
      masterId: masterId,
      businessTypeId: _clientBusinessTypeId,
      countryId: countryId,
      cityId: _pointCityId,
      areaId: _pointAreaId,
      fullAddress: _pointAddress.text.trim(),
      latitude: double.tryParse(_pointLat.text),
      longitude: double.tryParse(_pointLng.text),
      taxId: _clientTaxId.text.trim(),
      notes: _clientNotes.text.trim(),
      status: _clientStatus,
    );

    String siteId;
    if (supaReady) {
      final created = await dataService.createSite(newSite);
      if (created == null) {
        _toast(s.isAr ? 'فشل إنشاء العميل' : 'Failed to create Client',
            isError: true);
        return;
      }
      siteId = created.id;
    } else {
      repo.addSite(newSite);
      siteId = newSite.id;
    }

    // 3) إنشاء Point (إن وُجد اسم) + ربطه بالـ Site
    if (_pointName.text.trim().isNotEmpty) {
      final pointCode = await genCode('pos_point', 'POS-?');
      final newPoint = Point(
        id: repo.generateId(),
        code: pointCode,
        name: _pointName.text.trim(),
        description: _pointDescription.text.trim(),
        countryId: countryId,
        cityId: _pointCityId,
        areaId: _pointAreaId,
        fullAddress: _pointAddress.text.trim(),
        latitude: double.tryParse(_pointLat.text),
        longitude: double.tryParse(_pointLng.text),
      );

      String pointId;
      if (supaReady) {
        final created = await dataService.createPoint(newPoint);
        if (created == null) {
          _toast(s.isAr ? 'فشل إنشاء النقطة' : 'Failed to create Point',
              isError: true);
          return;
        }
        pointId = created.id;
      } else {
        newPoint.linkedClients.addAll(_linkedPointClients);
        newPoint.linkedClients.add(PointClientLink(clientId: siteId));
        repo.addPoint(newPoint);
        pointId = newPoint.id;
      }

      // ربط النقطة بالعميل الحالي + العملاء الإضافيين
      if (supaReady) {
        await dataService.linkSiteToPoint(
          pointId: pointId,
          siteId: siteId,
        );
        for (final link in _linkedPointClients) {
          if (link.clientId.isEmpty) continue;
          await dataService.linkSiteToPoint(
            pointId: pointId,
            siteId: link.clientId,
            unit: link.unit,
            floor: link.floor,
          );
        }
      }
    }

    if (!mounted) return;
    _toast(s.savedSuccess);
    Navigator.of(context).pop();
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final country = repo.countryById(auth.selectedCountryId);

    final stepDescs = [s.step1Desc, s.step2Desc, s.step3Desc];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.newCustomer),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(s.save),
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== Country bar + Diagram =====
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEBF4FF), Color(0xFFF0FFF4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFFCBD5E0)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                // شريط الدولة الصغير
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        country?.code ?? '?',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        country == null
                            ? s.countryRequired
                            : '${country.code} - ${country.displayName(s.isAr)}',
                        style: const TextStyle(
                          color: AppColors.brand,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        s.autoCodes,
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.brand,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // المخطط البصري
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: CustomerDiagram(
                    masterState: _masterNodeState,
                    clientState: _clientNodeState,
                    pointState: _pointNodeState,
                    onTapNode: (i) => _tabs.animateTo(i),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodyMedium?.color),
                      children: [
                        TextSpan(
                          text: s.isAr
                              ? 'الخطوة ${_tabs.index + 1}: '
                              : 'Step ${_tabs.index + 1}: ',
                          style: const TextStyle(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(text: stepDescs[_tabs.index]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ===== Tabs =====
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.brand,
              indicatorColor: AppColors.brand,
              indicatorWeight: 2.5,
              unselectedLabelColor: const Color(0xFF94A3B8),
              tabs: [
                _buildTabItem(1, s.masterStep, _masterNodeState),
                _buildTabItem(2, s.clientStep, _clientNodeState),
                _buildTabItem(3, s.pointStep, _pointNodeState),
              ],
            ),
          ),
          // ===== Tab content =====
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _MasterTab(
                  state: this,
                  countryCode: country?.code ?? '',
                ),
                _ClientTab(
                  state: this,
                  countryCode: country?.code ?? '',
                ),
                _PointTab(
                  state: this,
                  country: country,
                ),
              ],
            ),
          ),
          // ===== Save bar =====
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.brand, AppColors.brandDark],
              ),
            ),
            child: SafeArea(
              top: false,
              child: InkWell(
                onTap: _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        s.saveCustomer,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int num, String label, NodeState state) {
    final isFilled = state == NodeState.filled || state == NodeState.activeFilled;
    final isActive = state == NodeState.active || state == NodeState.activeFilled;
    Color bg;
    Color fg;
    if (isActive) {
      bg = AppColors.brand;
      fg = Colors.white;
    } else if (isFilled) {
      bg = AppColors.success;
      fg = Colors.white;
    } else {
      bg = const Color(0xFFE2E8F0);
      fg = const Color(0xFF94A3B8);
    }
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: isFilled
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : Text(
                    '$num',
                    style: TextStyle(
                      color: fg,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 1: Master
// ===========================================================================
class _MasterTab extends StatefulWidget {
  final _CustomerWizardScreenState state;
  final String countryCode;
  const _MasterTab({required this.state, required this.countryCode});

  @override
  State<_MasterTab> createState() => _MasterTabState();
}

class _MasterTabState extends State<_MasterTab> {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final st = widget.state;
    final repo = MockRepository();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AutoCodeBox(
            label: s.masterCode,
            code: st._masterCodePreview ?? '—',
          ),
          const SizedBox(height: 12),
          _SectionHeader(icon: Icons.info_outline, label: s.masterInformation),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: st._masterName,
                  onChanged: (_) => st.setState(() {}),
                  decoration: InputDecoration(
                    labelText: '${s.masterName} *',
                    hintText: s.masterNameHint,
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: st._masterLicense,
                      decoration: InputDecoration(labelText: s.tradeLicense),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: st._masterTax,
                      decoration: InputDecoration(labelText: s.taxVat),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: st._masterIndustryId,
                      decoration: InputDecoration(labelText: s.industry),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...repo.businessTypes.map((b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(b.displayName(s.isAr)),
                            )),
                      ],
                      onChanged: (v) => setState(() => st._masterIndustryId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: st._masterStart ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => st._masterStart = d);
                      },
                      child: AbsorbPointer(
                        child: TextField(
                          controller: TextEditingController(
                            text: st._masterStart == null
                                ? ''
                                : '${st._masterStart!.day}/${st._masterStart!.month}/${st._masterStart!.year}',
                          ),
                          decoration: InputDecoration(
                            labelText: s.startDateLbl,
                            hintText: 'dd/mm/yyyy',
                            suffixIcon: const Icon(Icons.calendar_today, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: st._masterNotes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: s.notes,
                    hintText: s.internalNotes,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 2: Client
// ===========================================================================
class _ClientTab extends StatefulWidget {
  final _CustomerWizardScreenState state;
  final String countryCode;
  const _ClientTab({required this.state, required this.countryCode});

  @override
  State<_ClientTab> createState() => _ClientTabState();
}

class _ClientTabState extends State<_ClientTab> {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final st = widget.state;
    final repo = MockRepository();
    final masters = st._countryId == null
        ? <Master>[]
        : repo.mastersInCountry(st._countryId!);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Link to Master block
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF0F9FF), Color(0xFFFAF5FF)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.brand, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.link, size: 16, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Text(s.linkToMaster,
                      style: const TextStyle(
                          color: AppColors.brand,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                Text(s.linkToMasterDesc,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                // Master selector - يظهر فقط لمن يريد ربط بـ Master موجود
                if (!st._autoCreateMaster) ...[
                  DropdownButtonFormField<String>(
                    value: st._selectedMasterId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: s.masterContract,
                      hintText: s.selectMaster,
                    ),
                    items: masters
                        .map((m) => DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(
                                '${m.code}  •  ${m.name}',
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => st._selectedMasterId = v),
                  ),
                  const SizedBox(height: 8),
                  // OR divider
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(s.orDivider,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 1)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 8),
                ],
                // Auto-create checkbox
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: st._autoCreateMaster
                        ? AppColors.success.withOpacity(0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: st._autoCreateMaster
                          ? AppColors.success
                          : const Color(0xFFCBD5E0),
                      width: 1.2,
                      style: st._autoCreateMaster
                          ? BorderStyle.solid
                          : BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: st._autoCreateMaster,
                        onChanged: (v) {
                          setState(() {
                            st._autoCreateMaster = v ?? false;
                            if (st._autoCreateMaster) {
                              st._selectedMasterId = null;
                            }
                          });
                        },
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.singleBranchAuto,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                )),
                            const SizedBox(height: 4),
                            Text(s.singleBranchAutoDesc,
                                style: Theme.of(context).textTheme.bodySmall),
                            if (st._autoCreateMaster) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: AppColors.success),
                                ),
                                child: Text(
                                  '${s.willCreate}: ${st._masterCodePreview ?? "—"}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _AutoCodeBox(
            label: s.clientCode,
            code: st._clientCodePreview ?? '—',
          ),
          const SizedBox(height: 12),
          // Basic Information
          _SectionHeader(icon: Icons.info_outline, label: s.basicInformation),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: st._clientCompany,
                  onChanged: (_) => st.setState(() {}),
                  decoration: InputDecoration(
                    labelText: '${s.companyName} *',
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: st._clientShort,
                      decoration: InputDecoration(labelText: s.shortName),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: st._clientAccounting,
                      decoration: InputDecoration(labelText: s.accountingName),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: st._clientBusinessTypeId,
                  decoration: InputDecoration(labelText: s.businessType2),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ...repo.businessTypes.map((b) => DropdownMenuItem(
                          value: b.id,
                          child: Text(b.displayName(s.isAr)),
                        )),
                  ],
                  onChanged: (v) =>
                      setState(() => st._clientBusinessTypeId = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Contact
          _SectionHeader(icon: Icons.contact_mail_outlined, label: s.contact),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: st._clientEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: s.email,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: st._clientPhone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: s.phone,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Additional
          _SectionHeader(icon: Icons.add_circle_outline, label: s.additional),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: st._clientTaxId,
                  decoration: InputDecoration(labelText: s.taxId),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(s.customerStatus,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Switch(
                      value: st._clientStatus == EntityStatus.active,
                      onChanged: (v) => setState(() {
                        st._clientStatus = v
                            ? EntityStatus.active
                            : EntityStatus.inactive;
                      }),
                    ),
                    StatusBadge(
                      label: st._clientStatus == EntityStatus.active
                          ? s.active
                          : s.inactive,
                      color: st._clientStatus == EntityStatus.active
                          ? AppColors.success
                          : AppColors.danger,
                      dense: true,
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: st._clientNotes,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.notes),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Files
          _SectionHeader(icon: Icons.attach_file, label: s.filesAndDocs),
          SectionCard(
            child: _FilesUploadBox(),
          ),
          const SizedBox(height: 80), // مساحة للـ save bar
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 3: Point
// ===========================================================================
class _PointTab extends StatefulWidget {
  final _CustomerWizardScreenState state;
  final Country? country;
  const _PointTab({required this.state, required this.country});

  @override
  State<_PointTab> createState() => _PointTabState();
}

class _PointTabState extends State<_PointTab> {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final st = widget.state;
    final repo = MockRepository();
    final country = widget.country;

    final availableCities = country == null
        ? <City>[]
        : repo.citiesOfCountry(country.id);
    final availableAreas = st._pointCityId == null
        ? <Area>[]
        : repo.areasOfCity(st._pointCityId!);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AutoCodeBox(
            label: s.pointCode,
            code: st._pointCodePreview ?? '—',
          ),
          const SizedBox(height: 10),
          // Info note
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline,
                  color: AppColors.info, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.pointInfoNote,
                    style: const TextStyle(
                        color: AppColors.info, fontSize: 11.5)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _SectionHeader(icon: Icons.place_outlined, label: s.pointInformation),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: st._pointName,
                  onChanged: (_) => st.setState(() {}),
                  decoration: InputDecoration(
                    labelText: '${s.pointName} *',
                    hintText: s.pointNameHint,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: st._pointDescription,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: s.pointDescription,
                    hintText: s.pointDescriptionHint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionHeader(icon: Icons.public, label: s.locationInfo),
          SectionCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.public,
                        color: AppColors.brand, size: 16),
                    const SizedBox(width: 6),
                    Text('${s.country2}: ',
                        style: const TextStyle(fontSize: 12)),
                    Text(
                      country?.displayName(s.isAr) ?? '?',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: st._pointCityId,
                      decoration: InputDecoration(labelText: '${s.city2} *'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...availableCities.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.displayName(s.isAr)),
                            )),
                      ],
                      onChanged: (v) => setState(() {
                        st._pointCityId = v;
                        st._pointAreaId = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: st._pointAreaId,
                      decoration: InputDecoration(labelText: s.area),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ...availableAreas.map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.displayName(s.isAr)),
                            )),
                      ],
                      onChanged: st._pointCityId == null
                          ? null
                          : (v) => setState(() => st._pointAreaId = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: st._pointAddress,
                  decoration: InputDecoration(
                    labelText: s.fullAddress,
                    prefixIcon: const Icon(Icons.home_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: st._pointLat,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.latitude),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: st._pointLng,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.longitude),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionHeader(icon: Icons.link, label: s.linkedClients),
          SectionCard(
            child: Column(
              children: [
                Text(s.linkedClientsDesc,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.start),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: st._selectedClientForLink,
                  decoration: InputDecoration(labelText: s.clientBranch),
                  items: [
                    DropdownMenuItem(value: null, child: Text('— ${s.selectMaster.replaceAll("Master", "Client").replaceAll("اسم تجاري", "فرع")} —')),
                    ...repo.sites.map((site) => DropdownMenuItem(
                          value: site.id,
                          child: Text(site.companyName,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) =>
                      setState(() => st._selectedClientForLink = v),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: st._linkUnit,
                      decoration: InputDecoration(labelText: s.unitShop),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: st._linkFloor,
                      decoration: InputDecoration(labelText: s.floorLbl),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    if (st._selectedClientForLink == null) return;
                    if (st._linkedPointClients.any(
                        (l) => l.clientId == st._selectedClientForLink)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(s.isAr
                              ? 'مرتبط بالفعل'
                              : 'Already linked'),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      st._linkedPointClients.add(PointClientLink(
                        clientId: st._selectedClientForLink!,
                        unit: st._linkUnit.text.trim(),
                        floor: st._linkFloor.text.trim(),
                      ));
                      st._selectedClientForLink = null;
                      st._linkUnit.clear();
                      st._linkFloor.clear();
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(s.linkClient),
                ),
                const SizedBox(height: 10),
                if (st._linkedPointClients.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(s.noClientsLinked,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center),
                  )
                else
                  ...st._linkedPointClients.map((link) {
                    final client = repo.sites.firstWhere(
                        (x) => x.id == link.clientId,
                        orElse: () => Site(
                            id: '', companyName: '?', shortName: ''));
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.brand.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(client.companyName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                              if (link.unit.isNotEmpty || link.floor.isNotEmpty)
                                Text(
                                  '${link.unit.isNotEmpty ? "${s.unitShop}: ${link.unit}" : ""}${link.unit.isNotEmpty && link.floor.isNotEmpty ? " · " : ""}${link.floor.isNotEmpty ? "${s.floorLbl}: ${link.floor}" : ""}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF94A3B8)),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: AppColors.danger),
                          onPressed: () {
                            setState(() {
                              st._linkedPointClients.remove(link);
                            });
                          },
                        ),
                      ]),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ===========================================================================
// Helper Widgets
// ===========================================================================
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 4, left: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.brand),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.brand)),
      ]),
    );
  }
}

class _AutoCodeBox extends StatelessWidget {
  final String label;
  final String code;
  const _AutoCodeBox({required this.label, required this.code});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0F9FF), Color(0xFFECFDF5)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.brand,
          width: 1.4,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF64748B))),
              const SizedBox(height: 2),
              Text(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            s.auto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ]),
    );
  }
}

class _FilesUploadBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFFCBD5E0),
              width: 1.5,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Icon(Icons.cloud_upload_outlined,
                  color: AppColors.brand, size: 32),
              const SizedBox(height: 6),
              Text(s.tapToSelectFiles,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              Text(s.filesAccepted,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(s.isAr
                          ? 'سيتم ربط file_picker عند Supabase Storage'
                          : 'file_picker integrates with Supabase Storage'),
                    ),
                  );
                },
                child: Text(s.chooseFile),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(s.noFiles,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
