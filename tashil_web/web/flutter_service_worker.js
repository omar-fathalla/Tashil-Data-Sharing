'use strict';

// Kill switch for leftover Flutter PWA workers: take over, drop Cache Storage,
// unregister, and reload so a new hosting deploy is fetched from the network.
// This file is also copied into the build after `flutter build --pwa-strategy=none`
// so already-installed workers at /flutter_service_worker.js update to this script.

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(Promise.resolve());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      await self.clients.claim();
    } catch (e) {
      console.warn('Failed to claim clients:', e);
    }
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch (e) {
      console.warn('Failed to clear caches:', e);
    }
    try {
      await self.registration.unregister();
    } catch (e) {
      console.warn('Failed to unregister the service worker:', e);
    }
    try {
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) {
        if (client.url && 'navigate' in client) {
          client.navigate(client.url);
        }
      }
    } catch (e) {
      console.warn('Failed to navigate some service worker clients:', e);
    }
  })());
});
