export type Theme = "light" | "dark";
export const THEME_STORAGE_KEY: string;
export function readTheme(storage?: Pick<Storage,"getItem">): Theme;
export function applyTheme(theme: string, doc: Document): Theme;
export function currentTheme(): Theme;
export function selectTheme(theme: Theme): Theme;
export function initializeTheme(): void;
