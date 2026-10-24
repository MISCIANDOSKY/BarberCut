import test from "node:test";
import assert from "node:assert/strict";
import {
  readTheme,
  applyTheme,
  THEME_STORAGE_KEY,
  initializeTheme,
  selectTheme,
  currentTheme,
} from "../src/lib/theme.mjs";
test("Il tema predefinito è Auto, anche con preferenze non valide o storage bloccato", () => {
  for (const value of [null, "system", "unexpected"])
    assert.equal(
      readTheme({
        getItem: (key) => {
          assert.equal(key, THEME_STORAGE_KEY);
          return value;
        },
      }),
      "auto",
    );
  assert.equal(readTheme(), "auto");
  assert.equal(
    readTheme({
      getItem() {
        throw new Error("blocked");
      },
    }),
    "auto",
  );
  assert.equal(readTheme({ getItem: () => "light" }), "light");
  assert.equal(readTheme({ getItem: () => "dark" }), "dark");
});
test("Il cambio aggiorna insieme palette, controlli e colore della barra PWA", () => {
  const meta = {
    setAttribute(name, value) {
      assert.equal(name, "content");
      this.content = value;
    },
  };
  const doc = {
    documentElement: { dataset: {}, style: {} },
    querySelector(selector) {
      assert.equal(selector, 'meta[name="theme-color"]');
      return meta;
    },
  };
  assert.equal(applyTheme("light", doc), "light");
  assert.equal(doc.documentElement.dataset.theme, "light");
  assert.equal(doc.documentElement.style.colorScheme, "light");
  assert.equal(meta.content, "#f7f6f2");
  assert.equal(applyTheme("dark", doc), "dark");
  assert.equal(doc.documentElement.dataset.theme, "dark");
  assert.equal(doc.documentElement.style.colorScheme, "dark");
  assert.equal(meta.content, "#151815");
  assert.equal(applyTheme("unexpected", doc), "auto");
  assert.doesNotThrow(() =>
    applyTheme("light", {
      documentElement: { dataset: {}, style: {} },
      querySelector: () => null,
    }),
  );
});

test("Auto conserva la scelta e risolve la palette del sistema", () => {
  const doc = {
    documentElement: { dataset: {}, style: {} },
    querySelector: () => null,
  };
  assert.equal(readTheme({ getItem: () => "auto" }), "auto");
  assert.equal(applyTheme("auto", doc, false), "auto");
  assert.equal(doc.documentElement.dataset.theme, "light");
  assert.equal(doc.documentElement.dataset.themePreference, "auto");
  assert.equal(applyTheme("auto", doc, true), "auto");
  assert.equal(doc.documentElement.dataset.theme, "dark");
  assert.equal(doc.documentElement.dataset.themePreference, "auto");
});
test("Auto segue cambi sistema e ripresa; i temi manuali restano fissi", () => {
  const oldWindow = Object.getOwnPropertyDescriptor(globalThis, "window");
  const oldDocument = Object.getOwnPropertyDescriptor(globalThis, "document");
  const values = new Map([[THEME_STORAGE_KEY, "auto"]]);
  const media = new EventTarget();
  media.matches = false;
  const win = new EventTarget();
  win.localStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
  };
  win.matchMedia = (query) => {
    assert.equal(query, "(prefers-color-scheme: dark)");
    return media;
  };
  const doc = new EventTarget();
  doc.documentElement = { dataset: {}, style: {} };
  doc.hidden = false;
  const meta = {
    content: "",
    setAttribute(name, value) {
      this.content = value;
    },
  };
  doc.querySelector = () => meta;
  let stop = () => {};
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: win,
  });
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: doc,
  });
  try {
    stop = initializeTheme();
    assert.equal(currentTheme(), "auto");
    assert.equal(doc.documentElement.dataset.theme, "light");
    media.matches = true;
    media.dispatchEvent(new Event("change"));
    assert.equal(doc.documentElement.dataset.theme, "dark");
    assert.equal(values.get(THEME_STORAGE_KEY), "auto");
    selectTheme("light");
    media.matches = false;
    media.dispatchEvent(new Event("change"));
    media.matches = true;
    media.dispatchEvent(new Event("change"));
    assert.equal(doc.documentElement.dataset.theme, "light");
    selectTheme("dark");
    media.matches = false;
    media.dispatchEvent(new Event("change"));
    assert.equal(doc.documentElement.dataset.theme, "dark");
    selectTheme("auto");
    assert.equal(doc.documentElement.dataset.theme, "light");
    media.matches = true;
    win.dispatchEvent(new Event("focus"));
    assert.equal(doc.documentElement.dataset.theme, "dark");
    assert.equal(meta.content, "#151815");
    media.matches = false;
    doc.dispatchEvent(new Event("visibilitychange"));
    assert.equal(doc.documentElement.dataset.theme, "light");
    values.set(THEME_STORAGE_KEY, "dark");
    win.dispatchEvent(
      Object.assign(new Event("storage"), { key: THEME_STORAGE_KEY }),
    );
    assert.equal(currentTheme(), "dark");
    values.set(THEME_STORAGE_KEY, "auto");
    win.dispatchEvent(
      Object.assign(new Event("storage"), { key: THEME_STORAGE_KEY }),
    );
    assert.equal(currentTheme(), "auto");
    assert.equal(doc.documentElement.dataset.theme, "light");
    stop();
    media.matches = true;
    media.dispatchEvent(new Event("change"));
    assert.equal(doc.documentElement.dataset.theme, "light");
  } finally {
    stop();
    if (oldWindow) Object.defineProperty(globalThis, "window", oldWindow);
    else delete globalThis.window;
    if (oldDocument) Object.defineProperty(globalThis, "document", oldDocument);
    else delete globalThis.document;
  }
});
test("Il bootstrap prima del rendering usa Auto e rispetta i temi manuali", async () => {
  const { readFile } = await import("node:fs/promises");
  const { runInNewContext } = await import("node:vm");
  const html = await readFile(
    new URL("../index.html", import.meta.url),
    "utf8",
  );
  const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  for (const [saved, systemDark, expected] of [
    [null, false, "light"],
    [null, true, "dark"],
    ["unexpected", false, "light"],
    ["auto", false, "light"],
    ["auto", true, "dark"],
    ["light", true, "light"],
    ["dark", false, "dark"],
  ]) {
    const doc = {
      documentElement: { dataset: {}, style: {} },
      querySelector: () => ({ setAttribute() {} }),
    };
    runInNewContext(script, {
      document: doc,
      localStorage: { getItem: () => saved },
      window: { matchMedia: () => ({ matches: systemDark }) },
    });
    assert.equal(doc.documentElement.dataset.theme, expected);
    assert.equal(doc.documentElement.dataset.themePreference, ["light", "dark", "auto"].includes(saved) ? saved : "auto");
  }
});
