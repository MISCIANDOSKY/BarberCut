import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { pushWorkerSource } from "../scripts/push-worker.mjs";
function harness(windows = []) {
  const handlers = {},
    notices = [],
    opened = [];
  const context = {
    URL,
    self: {
      registration: {
        scope: "https://example.test/BarberUp/",
        showNotification: async (title, options) => {
          notices.push({ title, options });
        },
      },
      clients: {
        matchAll: async () => windows,
        openWindow: async (url) => {
          opened.push(url);
        },
      },
      addEventListener: (name, fn) => {
        handlers[name] = fn;
      },
    },
  };
  vm.runInNewContext(pushWorkerSource(), context);
  return { handlers, notices, opened };
}
test("push displays the reminder even with no app window and ignores external payload URLs", async () => {
  const h = harness();
  let done;
  h.handlers.push({
    data: {
      json: () => ({
        title: "Promemoria appuntamento · 1 ora",
        body: "Ricordati del tuo appuntamento!",
        tag: "barberup-event",
        url: "https://untrusted.test/",
      }),
    },
    waitUntil: (p) => {
      done = p;
    },
  });
  await done;
  assert.equal(h.notices.length, 1);
  assert.equal(h.notices[0].options.body, "Ricordati del tuo appuntamento!");
  assert.equal(
    h.notices[0].options.data.url,
    "https://example.test/BarberUp/?appointments=1",
  );
  assert.equal(
    h.notices[0].options.icon,
    "https://example.test/BarberUp/icons/icon-192.png",
  );
  assert.equal(h.notices[0].options.tag, "barberup-event");
});
test("malformed payload still creates a visible notification", async () => {
  const h = harness();
  let done;
  h.handlers.push({
    data: {
      json: () => {
        throw Error("invalid");
      },
    },
    waitUntil: (p) => {
      done = p;
    },
  });
  await done;
  assert.equal(h.notices[0].title, "BarberUp");
});
test("notification opens personal appointments or focuses the existing PWA", async () => {
  const h = harness();
  let done,
    closed = false;
  h.handlers.notificationclick({
    notification: {
      close: () => {
        closed = true;
      },
    },
    waitUntil: (p) => {
      done = p;
    },
  });
  await done;
  assert.ok(closed);
  assert.equal(h.opened[0], "https://example.test/BarberUp/?appointments=1");
  let navigated,
    focused = false;
  const second = harness([
    {
      url: "https://example.test/BarberUp/",
      navigate: async (url) => {
        navigated = url;
        return {
          focus: async () => {
            focused = true;
          },
        };
      },
    },
  ]);
  second.handlers.notificationclick({
    notification: { close: () => {} },
    waitUntil: (p) => {
      done = p;
    },
  });
  await done;
  assert.equal(navigated, "https://example.test/BarberUp/?appointments=1");
  assert.ok(focused);
  assert.equal(second.opened.length, 0);
});
