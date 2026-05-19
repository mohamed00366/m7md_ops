// =============================================================================
// 🧺 شاشة إعدادات نِظام "أَمانة" — إدارة أَنواع المَلابِس + روابِط
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../laundry/domain/models.dart';

class AmanaSettingsScreen extends StatefulWidget {
  const AmanaSettingsScreen({super.key});

  @override
  State<AmanaSettingsScreen> createState() => _AmanaSettingsScreenState();
}

class _AmanaSettingsScreenState extends State<AmanaSettingsScreen> {
  List<ClothingType> _types = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = SupabaseService().client;
      final rows = await c
          .from('clothing_types')
          .select()
          .order('sort_order', ascending: true);
      _types = (rows as List)
          .map((r) =>
              ClothingType.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(ClothingType t) async {
    try {
      final c = SupabaseService().client;
      await c
          .from('clothing_types')
          .update({'is_active': !t.isActive}).eq('id', t.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('فَشَل: $e'),
        ));
      }
    }
  }

  Future<void> _editType(ClothingType? existing) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TypeEditorDialog(existing: existing),
    );
    if (result == null) return;
    try {
      final c = SupabaseService().client;
      if (existing == null) {
        await c.from('clothing_types').insert(result);
      } else {
        await c
            .from('clothing_types')
            .update(result)
            .eq('id', existing.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('فَشَل الحِفظ: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧺 إعدادات أَمانة'),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        onPressed: () => _editType(null),
        icon: const Icon(Icons.add),
        label: const Text('نَوع جَديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('خَطَأ: $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _infoBanner(),
                      const SizedBox(height: 12),
                      const Text('📋 أَنواع المَلابِس',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      if (_types.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('لا تُوجَد أَنواع — أَضِف الأَوّل',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ..._types.map(_typeTile),
                    ],
                  ),
                ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.teal.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('عَن نِظام أَمانة',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.teal.shade900)),
                const SizedBox(height: 4),
                const Text(
                  'يَتَعامَل مَع طَلَبات المَغسلة، السَنَدات، الدُفعات وَالبَلاغات.\n'
                  '• كُلّ كَمب بُوص يَضبُط جَدوَل وَقت الاستِلام مِن لَوحة أَمانة\n'
                  '• الصَلاحِيّات تُدار مِن مَصفوفة الصَلاحِيّات (module=amana)\n'
                  '• "م.د" = اِختِصار يَظهَر بَدَلاً مِن أَسماء المَلابِس الحَسّاسة في الـPDF',
                  style: TextStyle(fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeTile(ClothingType t) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(t.emoji ?? '🧺',
              style: const TextStyle(fontSize: 24)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(t.nameAr,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            if (t.isSensitive)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('حَسّاس · م.د',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.deepPurple.shade900,
                        fontWeight: FontWeight.w900)),
              ),
          ],
        ),
        subtitle: Text(
          '${t.nameEn ?? "-"}  ·  تَرتيب ${t.sortOrder}',
          style: const TextStyle(fontSize: 10),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: t.isActive,
              onChanged: (_) => _toggleActive(t),
              activeColor: Colors.teal,
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _editType(t),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// مُحَرِّر نَوع المَلابِس
// =============================================================================
class _TypeEditorDialog extends StatefulWidget {
  final ClothingType? existing;
  const _TypeEditorDialog({this.existing});

  @override
  State<_TypeEditorDialog> createState() => _TypeEditorDialogState();
}

class _TypeEditorDialogState extends State<_TypeEditorDialog> {
  late final TextEditingController _nameAr;
  late final TextEditingController _nameEn;
  late final TextEditingController _emoji;
  late final TextEditingController _sort;
  bool _isSensitive = false;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameAr = TextEditingController(text: e?.nameAr ?? '');
    _nameEn = TextEditingController(text: e?.nameEn ?? '');
    _emoji = TextEditingController(text: e?.emoji ?? '');
    _sort = TextEditingController(text: '${e?.sortOrder ?? 0}');
    _isSensitive = e?.isSensitive ?? false;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _emoji.dispose();
    _sort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? '➕ نَوع مَلابِس جَديد'
          : '✏️ تَعديل نَوع'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameAr,
              decoration: const InputDecoration(
                labelText: 'الاسم بِالعَرَبيّ *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameEn,
              decoration: const InputDecoration(
                labelText: 'الاسم بِالإنجليزيّ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _emoji,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                    decoration: const InputDecoration(
                      labelText: 'Emoji',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _sort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'تَرتيب العَرض',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              title: const Text('حَسّاس (يَظهَر "م.د" في الـPDF)',
                  style: TextStyle(fontSize: 12)),
              value: _isSensitive,
              onChanged: (v) => setState(() => _isSensitive = v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('مُفَعَّل',
                  style: TextStyle(fontSize: 12)),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white),
          onPressed: () {
            if (_nameAr.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'name_ar': _nameAr.text.trim(),
              'name_en':
                  _nameEn.text.trim().isEmpty ? null : _nameEn.text.trim(),
              'emoji':
                  _emoji.text.trim().isEmpty ? null : _emoji.text.trim(),
              'sort_order': int.tryParse(_sort.text.trim()) ?? 0,
              'is_sensitive': _isSensitive,
              'is_active': _isActive,
            });
          },
          child: const Text('حِفظ'),
        ),
      ],
    );
  }
}
