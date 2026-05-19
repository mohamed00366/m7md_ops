// =============================================================================
// 🔔 FCM Web — VAPID public key
// =============================================================================
// Required ONLY for Web push (Chrome / Edge). On Android / iOS this is ignored.
//
// HOW TO GET THIS KEY:
//   1. Open https://console.firebase.google.com/project/m7-nexus/settings/cloudmessaging
//   2. Scroll to "Web configuration" → "Web push certificates"
//   3. Click "Generate key pair"
//   4. Copy the long base64 string (starts with "B…")
//   5. Paste it below between the quotes.
//
// Leave empty ('') to skip Web push silently.
// =============================================================================

class FcmConfig {
  /// Web push VAPID public key — paste from Firebase Console.
  static const String webVapidKey = 'BEQWFDlKHi5enrNZVS27GmTdxf5m0JhWHTP2byYk_JzHF36HDCx2ecoPrsqrDKIKpON_-G-eV9M-5Id4eELT69E';

  /// True when Web push is fully configured.
  static bool get webPushEnabled => webVapidKey.isNotEmpty;
}
