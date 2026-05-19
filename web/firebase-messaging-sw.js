// ============================================================================
// 🔔 Firebase Cloud Messaging — Web Service Worker
// ============================================================================
// Required by firebase_messaging on Flutter Web. Without this file the browser
// fails with: "failed-service-worker-registration ... unsupported MIME type
// ('text/html')" — because the dev server returns index.html instead.
//
// This file MUST live at /web/firebase-messaging-sw.js so it's served from
// the site root.
// ============================================================================

// Use the compat builds — the only ones supported inside a service worker
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

// Same config as DefaultFirebaseOptions.web in lib/firebase_options.dart
firebase.initializeApp({
  apiKey: 'AIzaSyB19RjkTYOavxBjUvD4200on-szC86zqjo',
  appId: '1:147542993139:web:eaab2d714af630371def86',
  messagingSenderId: '147542993139',
  projectId: 'm7-nexus',
  authDomain: 'm7-nexus.firebaseapp.com',
  storageBucket: 'm7-nexus.firebasestorage.app',
  measurementId: 'G-SWBNK3E5R9',
});

const messaging = firebase.messaging();

// Background message handler — fires when the tab is closed/backgrounded.
// Foreground messages are handled inside the Dart code (FcmService).
messaging.onBackgroundMessage((payload) => {
  // The Edge Function send-push sends `notification` + `data` blocks.
  const title = (payload.notification && payload.notification.title) ||
                (payload.data && payload.data.title) ||
                'M7 Nexus';
  const body  = (payload.notification && payload.notification.body) ||
                (payload.data && payload.data.body) || '';

  const options = {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: (payload.data && payload.data.notification_id) || 'm7-default',
    requireInteraction: false,
    data: payload.data || {},
  };

  self.registration.showNotification(title, options);
});

// Optional: focus / open the app when the user clicks the notification.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
