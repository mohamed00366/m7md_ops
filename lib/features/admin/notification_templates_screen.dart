// =============================================================================
// 🔔 Notification Templates — admin settings screen (English UI)
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/services/notification_templates_service.dart';

class NotificationTemplatesScreen extends StatefulWidget {
  const NotificationTemplatesScreen({super.key});

  @override
  State<NotificationTemplatesScreen> createState() =>
      _NotificationTemplatesScreenState();
}

class _NotificationTemplatesScreenState
    extends State<NotificationTemplatesScreen> {
  List<NotificationTemplate> _all = [];
  bool _loading = true;
  String? _error;
  String _moduleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _all = await NotificationTemplatesService.instance.list();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<NotificationTemplate> get _filtered {
    if (_moduleFilter == 'all') return _all;
    return _all.where((t) => t.module == _moduleFilter).toList();
  }

  /// Modules present in the data + ordered list for chips
  List<String> get _modules {
    final present = _all.map((t) => t.module).toSet();
    // Stable, predictable order that matches the seed migration
    const order = [
      'hr',
      'leave',
      'uniform',
      'rooms',
      'amana',
      'bus',
      'forms',
      'attendance',
      'roster',
      'auth',
      'system',
      'sites',
    ];
    final ordered = order.where(present.contains).toList();
    // Append anything we don't know about (future modules)
    final extras = present.difference(ordered.toSet()).toList()..sort();
    return ['all', ...ordered, ...extras];
  }

  /// English display name for every module
  String _moduleLabel(String m) {
    switch (m) {
      case 'all':
        return 'All';
      case 'hr':
        return '👥 HR';
      case 'leave':
        return '🏖 Leave';
      case 'uniform':
        return '👕 Uniform';
      case 'rooms':
        return '🏠 Rooms';
      case 'amana':
        return '🧺 Amana';
      case 'bus':
        return '🚌 Buses';
      case 'forms':
        return '📋 Forms';
      case 'attendance':
        return '⏰ Attendance';
      case 'roster':
        return '📅 Roster';
      case 'auth':
        return '🔐 Auth';
      case 'system':
        return '⚙️ System';
      case 'sites':
        return '🏢 Sites';
      default:
        return m;
    }
  }

  /// English display name for recipient role
  String _recipientLabel(String role) {
    switch (role) {
      case 'employee':
        return 'Employee';
      case 'camp_boss':
        return 'Camp Boss';
      case 'manager':
        return 'Manager';
      case 'hr':
        return 'HR';
      case 'admin':
        return 'Admin';
      case 'driver':
        return 'Driver';
      case 'supervisor':
        return 'Supervisor';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔔 Notification Templates'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error: $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : Column(
                  children: [
                    _moduleChips(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: _filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  Center(child: Text('No templates found')),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) =>
                                    _templateCard(_filtered[i]),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _moduleChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.indigo.shade50,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _modules.map((m) {
            final selected = m == _moduleFilter;
            final count = m == 'all'
                ? _all.length
                : _all.where((t) => t.module == m).length;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  '${_moduleLabel(m)}  $count',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: selected,
                onSelected: (_) => setState(() => _moduleFilter = m),
                selectedColor: Colors.indigo.shade700,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.indigo.shade900,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _templateCard(NotificationTemplate t) {
    // Prefer English; fall back to Arabic only if English is missing
    final displayTitle =
        (t.titleEn != null && t.titleEn!.isNotEmpty) ? t.titleEn! : t.titleAr;
    final displayBody =
        (t.bodyEn != null && t.bodyEn!.isNotEmpty) ? t.bodyEn! : t.bodyAr;

    final sample = NotificationTemplatesService.sampleVars(t.module);
    final previewTitle =
        NotificationTemplatesService.renderPreview(displayTitle, sample);
    final previewBody =
        NotificationTemplatesService.renderPreview(displayBody, sample);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _editTemplate(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: t.isEnabled ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.eventKey,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '→ ${_recipientLabel(t.recipientRole)}',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.indigo.shade900,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(previewTitle,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(previewBody,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              if (t.description != null && t.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(t.description!,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade700)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _channelChip('In-app', Icons.notifications, t.sendInapp),
                  const SizedBox(width: 6),
                  _channelChip('Push', Icons.smartphone, t.sendPush),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editTemplate(t),
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('Edit',
                        style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _channelChip(String label, IconData icon, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: enabled ? Colors.green.shade50 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: enabled ? Colors.green : Colors.grey.shade400, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 11,
              color: enabled ? Colors.green.shade900 : Colors.grey.shade600),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: enabled ? Colors.green.shade900 : Colors.grey.shade600,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Future<void> _editTemplate(NotificationTemplate t) async {
    final updated = await showDialog<NotificationTemplate>(
      context: context,
      builder: (_) => _TemplateEditorDialog(template: t),
    );
    if (updated == null) return;
    final ok = await NotificationTemplatesService.instance.update(updated);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.green,
        content: Text('✓ Template saved'),
      ));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.red,
        content: Text('Failed to save'),
      ));
    }
  }
}

// =============================================================================
// Editor dialog — edit title/body + channel toggles + live preview
// =============================================================================
class _TemplateEditorDialog extends StatefulWidget {
  final NotificationTemplate template;
  const _TemplateEditorDialog({required this.template});

  @override
  State<_TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _enabled;
  late bool _push;
  late bool _inapp;

  @override
  void initState() {
    super.initState();
    // Prefer English fields; fall back to Arabic if English is empty
    final initialTitle =
        (widget.template.titleEn != null && widget.template.titleEn!.isNotEmpty)
            ? widget.template.titleEn!
            : widget.template.titleAr;
    final initialBody =
        (widget.template.bodyEn != null && widget.template.bodyEn!.isNotEmpty)
            ? widget.template.bodyEn!
            : widget.template.bodyAr;
    _title = TextEditingController(text: initialTitle);
    _body = TextEditingController(text: initialBody);
    _enabled = widget.template.isEnabled;
    _push = widget.template.sendPush;
    _inapp = widget.template.sendInapp;
    _title.addListener(_rebuild);
    _body.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _insertVar(TextEditingController c, String v) {
    final placeholder = '{$v}';
    final sel = c.selection;
    if (sel.start < 0) {
      c.text = c.text + placeholder;
      c.selection = TextSelection.collapsed(offset: c.text.length);
    } else {
      final before = c.text.substring(0, sel.start);
      final after = c.text.substring(sel.end);
      c.text = before + placeholder + after;
      c.selection =
          TextSelection.collapsed(offset: before.length + placeholder.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final sample = NotificationTemplatesService.sampleVars(t.module);
    final previewTitle =
        NotificationTemplatesService.renderPreview(_title.text, sample);
    final previewBody =
        NotificationTemplatesService.renderPreview(_body.text, sample);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t.eventKey,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (t.description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(t.description!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      const Text('Title',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _title,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Body',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _body,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (t.availableVars.isNotEmpty) ...[
                        const Text('Variables (tap to insert):',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: t.availableVars.map((v) {
                            return PopupMenuButton<int>(
                              tooltip: 'Insert into…',
                              child: Chip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: Colors.indigo.shade50,
                                label: Text('{$v}',
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11)),
                              ),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 0,
                                    child: Text('Insert into title')),
                                PopupMenuItem(
                                    value: 1,
                                    child: Text('Insert into body')),
                              ],
                              onSelected: (i) => i == 0
                                  ? _insertVar(_title, v)
                                  : _insertVar(_body, v),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.visibility,
                                    size: 14,
                                    color: Colors.indigo.shade700),
                                const SizedBox(width: 4),
                                Text('Preview (with sample values):',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.indigo.shade700,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(previewTitle,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text(previewBody,
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(),
                      SwitchListTile(
                        dense: true,
                        title: const Text('Enabled',
                            style: TextStyle(fontSize: 13)),
                        subtitle: const Text(
                            'If off, this notification will not be sent at all',
                            style: TextStyle(fontSize: 10)),
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        title: const Text('In-app notification',
                            style: TextStyle(fontSize: 13)),
                        value: _inapp,
                        onChanged: _enabled
                            ? (v) => setState(() => _inapp = v)
                            : null,
                      ),
                      SwitchListTile(
                        dense: true,
                        title: const Text('Push (mobile)',
                            style: TextStyle(fontSize: 13)),
                        value: _push,
                        onChanged: _enabled
                            ? (v) => setState(() => _push = v)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save'),
                    onPressed: () {
                      // Write to BOTH _en and _ar so the trigger renderer works
                      // regardless of which field it reads. We treat the
                      // editor content as the canonical English version.
                      Navigator.pop(
                        context,
                        widget.template.copyWith(
                          titleEn: _title.text.trim(),
                          bodyEn: _body.text.trim(),
                          titleAr: _title.text.trim(),
                          bodyAr: _body.text.trim(),
                          isEnabled: _enabled,
                          sendPush: _push,
                          sendInapp: _inapp,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
