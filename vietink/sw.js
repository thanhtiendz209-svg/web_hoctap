'use strict';

const cachePrefix = 'ink-study-web-shell-';
const cacheName = cachePrefix + '0.5.0';
const home = new URL('./', self.registration.scope);
const indexPage = new URL('index.html', home);
const assets = new Set([
  './index.html',
  './editor.css?v=0.5.0',
  './app.js?v=0.5.0',
  './editor.js?v=0.5.0',
  './install.js?v=0.5.0',
  './manifest.webmanifest',
  './icons/favicon.ico',
  './icons/app-icon.png',
  './icons/app-icon-512.png',
  './icons/app-icon-maskable-512.png',
].map((path) => new URL(path, home).href));

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(cacheName).then((cache) =>
    cache.addAll([...assets].map((url) => new Request(url, { cache: 'reload' }))),
  ));
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter((key) => key.startsWith(cachePrefix) && key !== cacheName)
      .map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

async function openApp(request) {
  try {
    return await fetch(request);
  } catch {
    const cache = await caches.open(cacheName);
    return await cache.match(indexPage.href) ?? Response.error();
  }
}

async function loadAsset(request) {
  const cache = await caches.open(cacheName);
  return await cache.match(request) ?? fetch(request);
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== home.origin) return;
  if (request.mode === 'navigate' &&
      (url.pathname === home.pathname || url.pathname === indexPage.pathname)) {
    event.respondWith(openApp(request));
  } else if (assets.has(url.href)) {
    event.respondWith(loadAsset(request));
  }
});
