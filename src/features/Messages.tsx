import { useCallback, useEffect, useRef, useState } from "react";
import { Empty, Modal } from "../components/UI";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";

type Contact = { id: string; name: string };
type Conversation = { thread_id?: string; client_id: string; name: string };
function messageError(error: unknown) {
  const text = error instanceof Error ? error.message : String(error);
  if (text.includes("MESSAGE_REPLY_CLOSED")) return "Puoi rispondere solo nel giorno in cui ricevi un messaggio, fino alla mezzanotte italiana. Attendi un nuovo messaggio dalla barberia.";
  if (text.includes("MESSAGE_RATE_LIMIT")) return "Hai inviato molti messaggi. Attendi un minuto e riprova.";
  if (text.includes("MESSAGE_CLIENT_UNAVAILABLE")) return "Questo account non è disponibile per i messaggi.";
  if (text.includes("INVALID_MESSAGE")) return "Scrivi un messaggio da 1 a 2.000 caratteri.";
  return friendly(error);
}
function stamp(value: string) {
  return new Intl.DateTimeFormat("it-IT", { timeZone:"Europe/Rome", dateStyle:"short", timeStyle:"short" }).format(new Date(value));
}
function changed() { window.dispatchEvent(new Event("barberup:messages-changed")); }

export function MessageContact({ clientId, name, label = "Invia messaggio" }: { clientId: string; name: string; label?: string }) {
  const [open,setOpen] = useState(false);
  return <>
    <button type="button" className="text message-contact" onClick={() => setOpen(true)}>{label}</button>
    {open && <Modal title="Messaggi" wide className="messaging-dialog" close={() => setOpen(false)}>
      <Messages initialClient={{id:clientId,name}} />
    </Modal>}
  </>;
}

export default function Messages({ initialClient }: { initialClient?: Contact }) {
  const [rows,setRows] = useState<Row[]>([]);
  const [canStart,setCanStart] = useState(false);
  const [loaded,setLoaded] = useState(false);
  const [error,setError] = useState("");
  const [selection,setSelection] = useState<Conversation|null>(initialClient ? {client_id:initialClient.id,name:initialClient.name}:null);
  const [searching,setSearching] = useState(false);
  const [query,setQuery] = useState("");
  const [contacts,setContacts] = useState<Contact[]>([]);
  const [searchBusy,setSearchBusy] = useState(false);
  const [more,setMore] = useState(false);
  const revision = useRef(0);
  const load = useCallback(async (append=false,offset=0) => {
    const version=++revision.current;
    try {
      const data=await result<Row>(supabase.rpc("message_inbox",{p_offset:offset}));
      if(version!==revision.current)return;
      setRows(old=>append?[...old,...data.items.filter((item:Row)=>!old.some(x=>x.id===item.id))]:data.items);
      setCanStart(data.can_start===true);setMore(data.items.length===100);setLoaded(true);setError("");
      if(initialClient) setSelection(current=>{
        const existing=data.items.find((r:Row)=>r.client_id===initialClient.id);
        return current && !current.thread_id && current.client_id===initialClient.id && existing
          ? {...current,thread_id:existing.id}:current;
      });
    } catch(e) { if(version===revision.current){setError(messageError(e));setLoaded(true);} }
  },[initialClient?.id]);
  useEffect(()=>{
    const update=()=>{if(!document.hidden&&navigator.onLine)void load();};
    void load();
    const timer=window.setInterval(update,15000);
    window.addEventListener("focus",update);window.addEventListener("online",update);
    document.addEventListener("visibilitychange",update);
    return()=>{revision.current++;window.clearInterval(timer);window.removeEventListener("focus",update);window.removeEventListener("online",update);document.removeEventListener("visibilitychange",update);};
  },[load]);
  useEffect(()=>{
    if(!searching || !canStart)return;
    let stopped=false;
    const term=query.trim();
    setContacts([]);setSearchBusy(term.length>=2);
    const timer=window.setTimeout(async()=>{
      if(term.length<2)return;
      try{
        const data=await result<Contact[]>(supabase.rpc("message_recipients",{p_query:term,p_offset:0}));
        if(!stopped){setContacts(data);setError("");}
      }catch(e){if(!stopped)setError(messageError(e));}
      finally{if(!stopped)setSearchBusy(false);}
    },300);
    return()=>{stopped=true;window.clearTimeout(timer);};
  },[query,searching,canStart]);
  if(selection) return <MessageThread key={selection.thread_id || selection.client_id} conversation={selection} canStart={canStart}
    back={()=>{setSelection(null);setSearching(false);void load();}}
    sent={id=>{setSelection(s=>s?{...s,thread_id:id}:s);void load();changed();}} />;
  return <section className="messaging">
    <div className="message-toolbar">
      {canStart && <button type="button" className="primary" onClick={()=>{setSearching(s=>!s);setQuery("");setContacts([]);setError("");}}>
        {searching?"Le mie conversazioni":"Nuovo messaggio"}
      </button>}
      <button type="button" className="text" onClick={()=>void load()}>Aggiorna</button>
    </div>
    {error&&<p className="form-error" role="alert">{error}</p>}
    {!canStart&&<p className="muted">Puoi rispondere ai messaggi della barberia solo nello stesso giorno in cui li ricevi, fino alla mezzanotte italiana. Non puoi iniziare una conversazione.</p>}
    {searching?<div className="message-inbox-scroll content-stack">
      <label>Cerca cliente per nome, cognome o telefono<input type="search" value={query} maxLength={100} onChange={e=>setQuery(e.target.value)} autoComplete="off"/></label>
      {query.trim().length<2?<p className="muted">Inserisci almeno due caratteri.</p>:searchBusy?<p role="status">Ricerca…</p>:!contacts.length?<Empty>Nessun cliente trovato.</Empty>:null}
      {contacts.map(c=><button type="button" className="secondary message-inbox-item" key={c.id} onClick={()=>{const existing=rows.find(r=>r.client_id===c.id);setSelection({thread_id:existing?.id,client_id:c.id,name:c.name});}}>{c.name}<span aria-hidden="true">→</span></button>)}
    </div>:<div className="message-inbox-scroll content-stack">
      {!loaded?<p role="status">Caricamento messaggi…</p>:!rows.length?<Empty>Non ci sono ancora messaggi.</Empty>:null}
      {rows.map(r=><button type="button" className="secondary message-inbox-item" key={r.id} onClick={()=>setSelection({thread_id:r.id,client_id:r.client_id,name:r.name})}>
        <span><strong>{r.name}</strong><small>{r.last_body}</small><small>{stamp(r.last_at)}</small></span>
        {r.unread>0&&<span className="message-unread" aria-label={r.unread+" messaggi non letti"}>{r.unread}</span>}
      </button>)}
      {more&&<button type="button" className="secondary" onClick={()=>void load(true,rows.length)}>Carica altre conversazioni</button>}
    </div>}
  </section>;
}

function MessageThread({conversation,canStart,back,sent}:{conversation:Conversation;canStart:boolean;back:()=>void;sent:(id:string)=>void}) {
  const [rows,setRows]=useState<Row[]>([]);
  const [meta,setMeta]=useState<Row|null>(null);
  const [draft,setDraft]=useState("");
  const [error,setError]=useState("");
  const [busy,setBusy]=useState(false);
  const [loading,setLoading]=useState(!!conversation.thread_id);
  const [older,setOlder]=useState(false);
  const [more,setMore]=useState(false);
  const [clock,setClock]=useState(Date.now());
  const offset=useRef(0);
  const inFlight=useRef(false),alive=useRef(true);
  const list=useRef<HTMLDivElement>(null);
  const scroll=useRef<{bottom:boolean;height?:number}>({bottom:true});
  const nonce=useRef<{body:string;nonce:string}|null>(null);
  const historyLoaded=useRef(false);
  const load=useCallback(async(before?:string)=>{
    if(!conversation.thread_id||inFlight.current)return;
    inFlight.current=true;
    if(before)setOlder(true);
    try{
      const data=await result<Row>(supabase.rpc("message_history",{p_thread:conversation.thread_id,p_before:before||null}));
      if(!alive.current)return;
      const el=list.current;
      scroll.current=before?{bottom:false,height:el?.scrollHeight||0}:{bottom:!el||el.scrollHeight-el.scrollTop-el.clientHeight<100};
      offset.current=Date.now()-Date.parse(data.server_time);
      setClock(Date.now());setMeta(data);
      setRows(current=>{
        const all=new Map(current.map(r=>[r.id,r]));
        for(const item of data.items)all.set(item.id,item);
        return [...all.values()].sort((a,b)=>BigInt(a.id)<BigInt(b.id)?-1:BigInt(a.id)>BigInt(b.id)?1:0);
      });
      if(before||!historyLoaded.current)setMore(data.items.length===100);
      historyLoaded.current=true;
      setLoading(false);
      if(!before&&data.items.length){
        const last=data.items[data.items.length-1];
        const {error}=await supabase.rpc("read_message_thread",{p_thread:conversation.thread_id,p_through:last.id});
        if(!error&&alive.current)changed();
      }
    }catch(e){if(alive.current){setError(messageError(e));setLoading(false);}}
    finally{inFlight.current=false;if(alive.current)setOlder(false);}
  },[conversation.thread_id]);
  useEffect(()=>{
    alive.current=true;
    const update=()=>{if(!document.hidden&&navigator.onLine)void load();};
    void load();
    const timer=window.setInterval(update,10000);
    const clockTimer=window.setInterval(()=>setClock(Date.now()),1000);
    window.addEventListener("focus",update);window.addEventListener("online",update);document.addEventListener("visibilitychange",update);
    return()=>{alive.current=false;window.clearInterval(timer);window.clearInterval(clockTimer);window.removeEventListener("focus",update);window.removeEventListener("online",update);document.removeEventListener("visibilitychange",update);};
  },[load]);
  useEffect(()=>{
    const el=list.current;if(!el)return;
    if(scroll.current.height!==undefined){el.scrollTop+=el.scrollHeight-scroll.current.height;scroll.current={bottom:false};}
    else if(scroll.current.bottom)el.scrollTop=el.scrollHeight;
  },[rows]);
  const allowed=conversation.thread_id
    ?meta?.can_send===true&&(meta.can_start===true||!meta.reply_until||clock-offset.current<Date.parse(meta.reply_until))
    :canStart;
  return <section className="messaging">
    <div className="message-toolbar"><button type="button" className="text" onClick={back} disabled={busy}>← Tutte le conversazioni</button><strong>{meta?.name||conversation.name}</strong></div>
    {error&&<p className="form-error" role="alert">{error}</p>}
    <div className="message-history" ref={list} role="log" aria-label="Conversazione" aria-live="polite" aria-relevant="additions">
      {more&&rows.length>0&&<button type="button" className="text" disabled={older} onClick={()=>void load(rows[0].id)}>{older?"Caricamento…":"Carica messaggi precedenti"}</button>}
      {loading?<p role="status">Caricamento conversazione…</p>:!rows.length?<p className="muted">Scrivi il primo messaggio a {conversation.name}.</p>:null}
      {rows.map(r=><article key={r.id} className={"message-bubble"+(r.own?" is-own":"")}><p>{r.body}</p><small>{r.own?"Tu · ":""}{stamp(r.created_at)}</small></article>)}
    </div>
    {!canStart&&!loading&&<p className="message-reply-help muted">{allowed?"Puoi rispondere fino alla mezzanotte di oggi, ora italiana.":"Le risposte sono chiuse. Potrai rispondere quando riceverai un nuovo messaggio dalla barberia."}</p>}
    <form className="message-composer" onSubmit={async e=>{
      e.preventDefault();if(busy||!allowed||!draft.trim())return;
      const body=draft.trim();
      if(!nonce.current||nonce.current.body!==body)nonce.current={body,nonce:crypto.randomUUID()};
      setBusy(true);setError("");
      try{
        const data=await result<Row>(supabase.rpc("send_direct_message",{p_body:body,p_nonce:nonce.current.nonce,p_thread:conversation.thread_id||null,p_client:conversation.thread_id?null:conversation.client_id}));
        if(!alive.current)return;
        setDraft("");nonce.current=null;scroll.current={bottom:true};
        setRows(current=>current.some(r=>r.id===data.id)?current:[...current,{id:data.id,body,own:true,created_at:new Date().toISOString()}]);
        if(conversation.thread_id)await load();
        sent(data.thread_id);
      }catch(e){if(alive.current){setError(messageError(e));if(String(e).includes("MESSAGE_REPLY_CLOSED"))void load();}}
      finally{if(alive.current)setBusy(false);}
    }}>
      <label>Messaggio<textarea rows={3} maxLength={2000} value={draft} onChange={e=>setDraft(e.target.value)} disabled={busy||!allowed} placeholder={allowed?"Scrivi un messaggio…":"Risposte non disponibili"} required /></label>
      <div className="message-composer-actions"><small>{draft.length}/2000 · Solo testo, nessun allegato</small><button type="submit" className="primary" disabled={busy||!allowed||!draft.trim()}>{busy?"Invio…":"Invia messaggio"}</button></div>
    </form>
  </section>;
}
