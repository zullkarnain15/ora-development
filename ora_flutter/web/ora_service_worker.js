'use strict';

const SHARE_CACHE = 'ora-share-target-v1';
const SHARE_ROUTE = 'share-target';
const PAYLOAD_ROUTE = '_ora_share_payload';
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const PAYLOAD_MAX_AGE_MS = 15 * 60 * 1000;

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method === 'POST' && isScopeRoute(url, SHARE_ROUTE)) {
    event.respondWith(receiveShare(request));
    return;
  }
  if (isPayloadRoute(url)) {
    if (request.method === 'GET') {
      event.respondWith(readPayload(request));
    } else if (request.method === 'DELETE') {
      event.respondWith(deletePayload(url));
    }
  }
});

function isScopeRoute(url, route) {
  return url.origin === self.location.origin &&
    url.pathname === new URL(route, self.registration.scope).pathname;
}

function isPayloadRoute(url) {
  const prefix = new URL(`${PAYLOAD_ROUTE}/`, self.registration.scope);
  return url.origin === prefix.origin && url.pathname.startsWith(prefix.pathname);
}

async function receiveShare(request) {
  try {
    const form = await request.formData();
    const title = cleanText(form.get('title'));
    const text = cleanText(form.get('text'));
    const url = cleanText(form.get('url'));
    const sharedImages = form.getAll('activity_images');
    const image = sharedImages.find(isAcceptedImage) || null;
    if (!title && !text && !url && !image) {
      const error = sharedImages.some(isOversizedImage) ? 'too_large' : 'empty';
      await notifyClients({type: 'ORA_ACTIVITY_SHARE_ERROR', error});
      return openOra({share_target: '1', share_error: error});
    }

    await removeExpiredPayloads();
    const shareId = createShareId();
    const cache = await caches.open(SHARE_CACHE);
    const metadataUrl = payloadUrl(shareId, 'json');
    const imageUrl = payloadUrl(shareId, 'image');
    const sourceText = `${title || ''}\n${text || ''}\n${url || ''}`;
    const metadata = {
      title,
      text,
      url,
      sourceHint: sourceText.toLowerCase().includes('strava') ? 'STRAVA' : null,
      receivedAt: new Date().toISOString(),
      imageMimeType: image ? (image.type || 'image/jpeg') : null,
      imageName: image ? (image.name || 'shared-activity.jpg') : null,
      hasImage: Boolean(image),
    };
    await cache.put(
      metadataUrl,
      new Response(JSON.stringify(metadata), {
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
        },
      }),
    );
    if (image) {
      await cache.put(
        imageUrl,
        new Response(image, {
          headers: {
            'Content-Type': metadata.imageMimeType,
            'Cache-Control': 'no-store',
          },
        }),
      );
    }
    await notifyClients({type: 'ORA_ACTIVITY_SHARE', shareId});
    return openOra({share_target: '1', share_id: shareId});
  } catch (_) {
    await notifyClients({type: 'ORA_ACTIVITY_SHARE_ERROR', error: 'read_failed'});
    return openOra({share_target: '1', share_error: 'read_failed'});
  }
}

function isAcceptedImage(value) {
  return value instanceof Blob &&
    value.size > 0 &&
    value.size <= MAX_IMAGE_BYTES &&
    (!value.type || value.type.startsWith('image/'));
}

function isOversizedImage(value) {
  return value instanceof Blob && value.size > MAX_IMAGE_BYTES;
}

function cleanText(value) {
  if (typeof value !== 'string') return null;
  const cleaned = value.trim();
  return cleaned.length ? cleaned : null;
}

function createShareId() {
  if (self.crypto && typeof self.crypto.randomUUID === 'function') {
    return self.crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function payloadUrl(shareId, extension) {
  return new URL(`${PAYLOAD_ROUTE}/${shareId}.${extension}`, self.registration.scope).toString();
}

function openOra(parameters) {
  const destination = new URL('./', self.registration.scope);
  for (const [name, value] of Object.entries(parameters)) {
    destination.searchParams.set(name, value);
  }
  return Response.redirect(destination.toString(), 303);
}

async function notifyClients(message) {
  const windows = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  for (const client of windows) client.postMessage(message);
}

async function readPayload(request) {
  const cached = await caches.match(request);
  return cached || new Response('', {status: 404});
}

async function deletePayload(url) {
  const shareId = payloadIdFromUrl(url);
  if (!shareId) return new Response('', {status: 400});
  const cache = await caches.open(SHARE_CACHE);
  await Promise.all([
    cache.delete(payloadUrl(shareId, 'json')),
    cache.delete(payloadUrl(shareId, 'image')),
  ]);
  return new Response('', {status: 204});
}

function payloadIdFromUrl(url) {
  const fileName = url.pathname.split('/').pop() || '';
  const match = fileName.match(/^([a-zA-Z0-9-]+)(?:\.(?:json|image))?$/);
  return match ? match[1] : null;
}

async function removeExpiredPayloads() {
  const cache = await caches.open(SHARE_CACHE);
  const keys = await cache.keys();
  const now = Date.now();
  await Promise.all(keys.map(async (request) => {
    if (!request.url.endsWith('.json')) return;
    const response = await cache.match(request);
    if (!response) return;
    try {
      const metadata = await response.json();
      const receivedAt = Date.parse(metadata.receivedAt || '');
      if (Number.isFinite(receivedAt) && now - receivedAt <= PAYLOAD_MAX_AGE_MS) return;
    } catch (_) {
      // Invalid metadata is removed with its paired image below.
    }
    const shareId = payloadIdFromUrl(new URL(request.url));
    if (!shareId) return;
    await Promise.all([
      cache.delete(payloadUrl(shareId, 'json')),
      cache.delete(payloadUrl(shareId, 'image')),
    ]);
  }));
}
