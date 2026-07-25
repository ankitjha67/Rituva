// Rituva service worker — cache the app shell for offline; API calls always hit network.
const CACHE = 'rituva-shell-v1';
const SHELL = ['/app/', '/app/index.html', '/app/styles.css', '/app/app.js',
               '/app/manifest.webmanifest', '/app/icon.svg'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) =>
    Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  // Only the static shell is cache-first; everything else (the API) is network.
  if (e.request.method === 'GET' && url.pathname.startsWith('/app/')) {
    e.respondWith(caches.match(e.request).then((r) => r || fetch(e.request)));
  }
});
