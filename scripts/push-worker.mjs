export function pushWorkerSource() {
  return String.raw`
self.addEventListener('push', event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch {}
  const title = typeof payload.title === 'string' ? payload.title.slice(0, 150) : 'Promemoria appuntamento';
  const body = typeof payload.body === 'string' ? payload.body.slice(0, 1000) : 'Ricordati del tuo appuntamento. Apri l’app per vedere i dettagli.';
  const kind = payload.kind === 'message' ? 'message' : 'appointment';
  const target = new URL(kind === 'message' ? './?messages=1' : './?appointments=1', self.registration.scope);
  event.waitUntil(self.registration.showNotification(title, {
    body, icon: new URL('./icons/icon-192.png', self.registration.scope).href,
    badge: new URL('./icons/icon-192.png', self.registration.scope).href,
    tag: typeof payload.tag === 'string' ? payload.tag.slice(0, 100) : 'barberup-reminder',
    data: {url: target.href, kind},
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const kind = event.notification.data && event.notification.data.kind;
  const target = new URL(kind === 'message' ? './?messages=1' : './?appointments=1', self.registration.scope).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    const existing = windows.find(client => client.url.startsWith(self.registration.scope));
    if (existing) {
      const navigated = await existing.navigate(target);
      if (navigated) await navigated.focus();
    } else await self.clients.openWindow(target);
  })());
});
`;
}
