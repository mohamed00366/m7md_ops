import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildPreview({required String state, required String lang, required String theme, required Map<String, dynamic> link}) {
  return Center(
    child: OutlinedButton.icon(
      icon: const Icon(Icons.open_in_new),
      label: const Text('Open the page preview'),
      onPressed: () => launchUrl(Uri.parse('https://vip-valet-uae.app/request/?demo=$state')),
    ),
  );
}
