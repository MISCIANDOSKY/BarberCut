import { useState } from "react";
import { Modal } from "../components/UI";
import { currentTheme, selectTheme } from "../lib/theme.mjs";
import type { Theme } from "../lib/theme.mjs";
export default function GeneralSettings() {
 const [themeOpen,setThemeOpen]=useState(false);
 const [theme,setTheme]=useState<Theme>(currentTheme);
 return <>
 <nav className="profile-menu" aria-label="Impostazioni generali">
 <button type="button" className="secondary" onClick={()=>{setTheme(currentTheme());setThemeOpen(true);}}>
 <span>Tema</span><span aria-hidden="true">→</span>
 </button>
 </nav>
 {themeOpen&&<Modal title="Tema" wide close={()=>setThemeOpen(false)}>
 <p className="muted">Scegli l’aspetto di BarberUp. La modifica si applica subito e viene ricordata su questo dispositivo.</p>
 <fieldset className="theme-options">
 <legend>Tema dell’app</legend>
 {([{value:"light",label:"Tema chiaro",description:"Sfondi chiari e testo scuro."},{value:"dark",label:"Tema scuro",description:"L’aspetto originale di BarberUp."}] as const).map(option=>
 <label key={option.value} className={"theme-choice"+(theme===option.value?" is-selected":"")}>
 <input type="radio" name="app-theme" value={option.value} checked={theme===option.value} onChange={()=>setTheme(selectTheme(option.value))}/>
 <span><strong>{option.label}</strong><small>{option.description}</small></span>
 <span aria-hidden="true" className={"theme-preview theme-preview-"+option.value}><span/><span/><span/></span>
 </label>)}
 </fieldset>
 </Modal>}
 </>;
}
