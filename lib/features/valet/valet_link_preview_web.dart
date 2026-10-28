// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

/// One iframe for the whole session (re-used when the screen is opened again).
html.IFrameElement? _frame;
bool _registered = false;
Map<String, dynamic> _last = const {};
StreamSubscription<html.MessageEvent>? _sub;

void _send() {
  final w = _frame?.contentWindow;
  if (w == null) return;
  // JSON round trip: plain JS objects for postMessage
  w.postMessage(jsonDecode(jsonEncode(_last)), '*');
}

Widget buildPreview({required String state, required String lang, required String theme, required Map<String, dynamic> link}) {
  _last = {'type': 'vv-link', 'state': state, 'lang': lang, 'theme': theme, 'link': link};
  if (!_registered) {
    _registered = true;
    _frame = html.IFrameElement()
      ..src = 'https://vip-valet-uae.app/request/?demo=$state'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%';
    _frame!.onLoad.listen((_) => Future.delayed(const Duration(milliseconds: 300), _send));
    _sub = html.window.onMessage.listen((e) {
      final d = e.data;
      if (d is Map && d['type'] == 'vv-link-ready') _send();
    });
    ui_web.platformViewRegistry.registerViewFactory('vv-link-preview', (int _) => _frame!);
  }
  scheduleMicrotask(_send);
  assert(_sub != null);
  return const HtmlElementView(viewType: 'vv-link-preview');
}
