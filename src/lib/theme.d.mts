export type Theme = "light" | "dark" | "auto";
export const THEME_STORAGE_KEY: string;
export const THEME_CHANGE_EVENT: string;
export function readTheme(storage?: Pick<Storage, "getItem">): Theme;
export function applyTheme(theme: string, doc: Document, systemDark?: boolean): Theme;
export function currentTheme(): Theme;
export function selectTheme(theme: Theme): Theme;
export function initializeTheme(): () => void;
