export const THEME_STORAGE_KEY = "barberup-theme";
export function readTheme(storage) {
 try { return storage?.getItem(THEME_STORAGE_KEY)==="light"?"light":"dark"; }
 catch { return "dark"; }
}
export function applyTheme(theme, doc) {
 const selected=theme==="light"?"light":"dark";
 doc.documentElement.dataset.theme=selected;
 doc.documentElement.style.colorScheme=selected;
 const meta=doc.querySelector('meta[name="theme-color"]');
 if(meta)meta.setAttribute("content",selected==="light"?"#f7f6f2":"#151815");
 return selected;
}
function browserStorage() {
 try{return window.localStorage;}catch{return undefined;}
}
export function currentTheme() {
 return document.documentElement.dataset.theme==="light"?"light":"dark";
}
export function selectTheme(theme) {
 const selected=applyTheme(theme,document);
 try{browserStorage()?.setItem(THEME_STORAGE_KEY,selected);}catch{}
 return selected;
}
export function initializeTheme() {
 applyTheme(readTheme(browserStorage()),document);
 window.addEventListener("storage",event=>{
 if(event.key===THEME_STORAGE_KEY||event.key===null)
 applyTheme(readTheme(browserStorage()),document);
 });
}
