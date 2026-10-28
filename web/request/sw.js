/* M7 NEXUS request page – service worker (309).
   Only used to show car alerts as system notifications while the page is open in the background
   (Android Chrome needs a service worker for notifications). No caching. */
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  var url = (e.notification.data && e.notification.data.url) || '/request/';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
    for (var i = 0; i < list.length; i++) {
      if (list[i].url.split('#')[0] === url.split('#')[0] && 'focus' in list[i]) return list[i].focus();
    }
    for (var j = 0; j < list.length; j++) if ('focus' in list[j]) return list[j].focus();
    return self.clients.openWindow ? self.clients.openWindow(url) : null;
  }));
});
