import 'package:flutter/widgets.dart';

import 'valet_link_preview_stub.dart' if (dart.library.html) 'valet_link_preview_web.dart' as impl;

/// Live preview of the customer request page (`/request/?demo=<state>`): on the web an iframe that gets the
/// unsaved texts / settings with postMessage; elsewhere a button that opens the demo page.
class LinkPreview extends StatelessWidget {
  const LinkPreview({super.key, required this.state, required this.lang, required this.theme, required this.link});
  final String state;
  final String lang;
  final String theme;
  final Map<String, dynamic> link;

  static const base = 'https://vip-valet-uae.app/request/';

  @override
  Widget build(BuildContext context) => impl.buildPreview(state: state, lang: lang, theme: theme, link: link);
}
