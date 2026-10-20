import { useEffect, useState } from "react";
import { Modal } from "../components/UI";
import { supabase, result } from "../lib/api";
import { sendRecoveryEmail, verifyRecoveryCode } from "../lib/recovery.mjs";

export default function PasswordRecovery({initialEmail="",lockEmail=false,close,verified}: {initialEmail?:string;lockEmail?:boolean;close:()=>void;verified:()=>void}) {
  const [email,setEmail]=useState(initialEmail),[code,setCode]=useState(""),[stage,setStage]=useState("email");
  const [busy,setBusy]=useState(false),[retry,setRetry]=useState(0),[error,setError]=useState(""),[notice,setNotice]=useState("");
  useEffect(()=>{if(!retry)return;const timer=window.setTimeout(()=>setRetry(n=>Math.max(0,n-1)),1000);return()=>window.clearTimeout(timer);},[retry]);
  async function send() {
    if(busy||retry)return;
    setBusy(true);setError("");setNotice("");
    try{
      await sendRecoveryEmail(supabase.auth,email,location.origin+import.meta.env.BASE_URL);
      setCode("");setRetry(60);setStage("code");
      setNotice("Se l’email è associata a un account, riceverai il codice e il pulsante per reimpostare la password. Controlla anche Spam e Posta indesiderata.");
    }catch{setError("Errore nell’invio, riprovare fra qualche minuto.");}
    finally{setBusy(false);}
  }
  return <Modal title="Reimposta password" close={()=>{if(!busy)close();}}>
    <p>Puoi usare il codice ricevuto via email per restare nella PWA, oppure premere “Reimposta password” nell’email.</p>
    {error&&<p className="form-error" role="alert">{error}</p>}
    {notice&&<p className="notice" role="status">{notice}</p>}
    <form onSubmit={async event=>{
      event.preventDefault();
      if(stage==="email"){await send();return;}
      if(busy)return;
      setBusy(true);setError("");
      try{await verifyRecoveryCode(supabase.auth,email,code);verified();}
      catch{setError("Errore: codice non valido o scaduto. Riprova oppure richiedi un nuovo codice.");}
      finally{setBusy(false);}
    }}>
      <label>Email<input name="recovery-email" type="email" autoComplete="email" value={email} readOnly={lockEmail||stage==="code"} required disabled={busy} onChange={e=>{setEmail(e.target.value);setError("");}}/></label>
      {stage==="code"&&<label>Codice ricevuto via email<input name="recovery-code" type="text" inputMode="numeric" autoComplete="one-time-code" value={code} pattern="[0-9]+" required disabled={busy} autoFocus onChange={e=>{setCode(e.target.value.replace(/[^0-9]/g,""));setError("");}}/></label>}
      <button type="submit" className="primary" disabled={busy||(stage==="email"&&retry>0)}>{busy?"Attendi…":stage==="email"?(retry?"Riprova tra "+retry+" secondi":"Invia codice e link via email"):"Verifica codice e continua"}</button>
    </form>
    {stage==="email"?<button type="button" className="text" disabled={busy||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())} onClick={()=>{setCode("");setError("");setStage("code");}}>Ho già un codice</button>:<>
      <button type="button" className="secondary" disabled={busy||retry>0} onClick={()=>void send()}>{retry?"Invia di nuovo tra "+retry+" secondi":"Invia un nuovo codice"}</button>
      <button type="button" className="text" disabled={busy} onClick={()=>{setStage("email");setError("");setNotice("");}}>Torna all’email</button>
    </>}
    <p className="muted">Se non trovi il messaggio, controlla anche le cartelle Spam e Posta indesiderata. Codice e link sono alternativi: usa una sola modalità.</p>
  </Modal>;
}
export function ResetPasswordDialog({close,done}: {close:()=>void;done:()=>void}) {
  const [password,setPassword]=useState(""),[confirmation,setConfirmation]=useState(""),[busy,setBusy]=useState(false),[error,setError]=useState("");
  return <Modal title="Scegli una nuova password" close={()=>{if(!busy)close();}}>
    {error&&<p className="form-error" role="alert">{error}</p>}
    <form onSubmit={async event=>{
      event.preventDefault();if(busy)return;
      if(password!==confirmation){setError("Le due password non coincidono.");return;}
      setBusy(true);setError("");
      try{await result(supabase.auth.updateUser({password}));done();}
      catch(e){
        const message=e instanceof Error?e.message:"";
        setError(/same_password/i.test(message)?"Scegli una password diversa da quella precedente.":/weak|password.*least|password.*short/i.test(message)?"La password non è abbastanza sicura. Scegli una password più lunga e riprova.":"Non riesco ad aggiornare la password. Riprova; se il codice o il link è scaduto, richiedine uno nuovo.");
      }finally{setBusy(false);}
    }}>
      <label>Nuova password<input type="password" minLength={8} required autoComplete="new-password" disabled={busy} value={password} onChange={e=>{setPassword(e.target.value);setError("");}}/></label>
      <label>Ripeti nuova password<input type="password" minLength={8} required autoComplete="new-password" disabled={busy} value={confirmation} onChange={e=>{setConfirmation(e.target.value);setError("");}}/></label>
      <button className="primary" disabled={busy}>{busy?"Salvataggio…":"Salva password"}</button>
    </form>
  </Modal>;
}
