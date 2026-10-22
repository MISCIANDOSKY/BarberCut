import { useState } from "react";
import { Modal } from "../components/UI";
import { supabase, result } from "../lib/api";
import type { Row } from "../lib/api";
export default function TermsGate({terms,ready,error,reload,onAccepted,logout}: {
 terms:Row|null;ready:boolean;error:string;reload:()=>Promise<void>;onAccepted:()=>void;logout:()=>Promise<void>;
}) {
 const [review,setReview]=useState(true),[busy,setBusy]=useState(false),[localError,setLocalError]=useState("");
 async function leave(){
  if(busy)return;setBusy(true);setLocalError("");
  try{await logout();}catch{setLocalError("Non riesco a uscire dall’account. Riprova.");}finally{setBusy(false);}
 }
 async function accept(){
  if(busy||!terms)return;setBusy(true);setLocalError("");
  try{
   await result(supabase.rpc("accept_current_terms",{p_id:terms.id}));
   await reload();onAccepted();
  }catch{
   setLocalError("Accettazione non riuscita. I termini potrebbero essere cambiati: controlla il testo aggiornato e riprova.");
   await reload();
  }finally{setBusy(false);}
 }
 return <div className="app terms-lock">
 <header className="topbar"><h1>BarberUp</h1><button className="text" disabled={busy} onClick={()=>void leave()}>Esci dall’account</button></header>
 <main className="content-stack terms-lock-content">
 {!ready?<><h2>Verifica dei termini</h2><p role="status">Controlliamo se hai già accettato i termini attuali.</p></>:<>
 <h2>Accetta i nuovi termini per continuare</h2>
 <p>L’uso dell’app è sospeso finché non accetti i termini e condizioni aggiornati. Il tuo account resta disponibile.</p>
 <p className="muted">Puoi cambiare idea in qualsiasi momento: rileggi il testo e premi Accetta.</p>
 <button className="primary" disabled={busy} onClick={()=>{setLocalError("");setReview(true);}}>Rileggi e accetta i termini</button>
 </>}
 {(localError||error)&&<p className="form-error" role="alert">{localError||error}</p>}
 {!ready&&<button className="secondary" disabled={busy} onClick={()=>void reload()}>Riprova verifica</button>}
 </main>
 {ready&&terms&&review&&<Modal title="Nuovi termini e condizioni" wide close={()=>{if(!busy)setReview(false);}}>
 <p className="notice">La barberia ha pubblicato nuovi termini e condizioni. Leggi il testo e scegli se accettare. Se rifiuti, non potrai usare l’app; potrai tornare qui e accettare in qualsiasi momento.</p>
 <h3>Versione {terms.version}</h3>
 <p className="legal">{terms.body}</p>
 {(localError||error)&&<p className="form-error" role="alert">{localError||error}</p>}
 <div className="terms-consent-actions">
 <button className="secondary" disabled={busy} onClick={()=>setReview(false)}>Rifiuta</button>
 <button className="primary" disabled={busy||!navigator.onLine} onClick={()=>void accept()}>{busy?"Attendi…":"Accetta i nuovi termini"}</button>
 </div>
 <button className="text" disabled={busy} onClick={()=>void leave()}>Esci dall’account</button>
 </Modal>}
 </div>;
}
