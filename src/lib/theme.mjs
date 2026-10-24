export const THEME_STORAGE_KEY = "barberup-theme";
export const THEME_CHANGE_EVENT = "barberup-theme-change";
function normalizeTheme(value) {
  return value === "light" || value === "dark" ? value : "auto";
}
export function readTheme(storage) {
  try {
    return normalizeTheme(storage?.getItem(THEME_STORAGE_KEY));
  } catch {
    return "auto";
  }
}
export function applyTheme(theme, doc, systemDark = true) {
  const selected = normalizeTheme(theme);
  const resolved =
    selected === "auto" ? (systemDark ? "dark" : "light") : selected;
  const changed =
    doc.documentElement.dataset.theme !== resolved ||
    doc.documentElement.dataset.themePreference !== selected;
  doc.documentElement.dataset.theme = resolved;
  doc.documentElement.dataset.themePreference = selected;
  doc.documentElement.style.colorScheme = resolved;
  const meta = doc.querySelector('meta[name="theme-color"]');
  if (meta)
    meta.setAttribute("content", resolved === "light" ? "#f7f6f2" : "#151815");
  if (changed) doc.dispatchEvent?.(new Event(THEME_CHANGE_EVENT));
  return selected;
}
function browserStorage() {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}
function systemQuery() {
  try {
    return window.matchMedia?.("(prefers-color-scheme: dark)") ?? null;
  } catch {
    return null;
  }
}
export function currentTheme() {
  return normalizeTheme(
    document.documentElement.dataset.themePreference ??
      document.documentElement.dataset.theme,
  );
}
export function selectTheme(theme) {
  const selected = applyTheme(theme, document, systemQuery()?.matches ?? true);
  try {
    browserStorage()?.setItem(THEME_STORAGE_KEY, selected);
  } catch {}
  return selected;
}
export function initializeTheme() {
  const media = systemQuery();
  const applyPreference = () =>
    applyTheme(readTheme(browserStorage()), document, media?.matches ?? true);
  applyPreference();
  const storageChanged = (event) => {
    if (event.key === THEME_STORAGE_KEY || event.key === null)
      applyPreference();
  };
  const systemChanged = () => {
    if (currentTheme() === "auto")
      applyTheme("auto", document, media?.matches ?? true);
  };
  const resumed = () => {
    if (!document.hidden) systemChanged();
  };
  window.addEventListener("storage", storageChanged);
  window.addEventListener("focus", systemChanged);
  window.addEventListener("pageshow", systemChanged);
  document.addEventListener("visibilitychange", resumed);
  if (media?.addEventListener) media.addEventListener("change", systemChanged);
  else media?.addListener?.(systemChanged);
  return () => {
    window.removeEventListener("storage", storageChanged);
    window.removeEventListener("focus", systemChanged);
    window.removeEventListener("pageshow", systemChanged);
    document.removeEventListener("visibilitychange", resumed);
    if (media?.removeEventListener)
      media.removeEventListener("change", systemChanged);
    else media?.removeListener?.(systemChanged);
  };
}
