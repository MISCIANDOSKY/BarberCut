import { useEffect, useState } from "react";
import { Empty, Modal } from "../components/UI";
import { createLatestRequest } from "../lib/latestRequest.mjs";
import { supabase,result,friendly,today,timeLabel,dateLabel,euro } from "../lib/api";
import { romeDay } from "../lib/dates.mjs";
import type { Row } from "../lib/api";
import RescheduleAppointment from "./RescheduleAppointment";

export default function ShopAgenda({onAccessChanged}:{onAccessChanged:()=>void}) {
 const [barbers,setBarbers]=useState<Row[]>([]),[selectedBarber,setSelectedBarber]=useState("");
 const [day,setDay]=useState(today),[rows,setRows]=useState<Row[]>([]),[order,setOrder]=useState("future"),[now,setNow]=useState(Date.now);
 const [loadingBarbers,setLoadingBarbers]=useState(true),[loading,setLoading]=useState(false),[error,setError]=useState("");
 const [detail,setDetail]=useState<Row|null>(null),[moving,setMoving]=useState(false),[busy,setBusy]=useState(false),[revision,setRevision]=useState(0);
 const barber=barbers.some(b=>b.id===selectedBarber)?selectedBarber:barbers[0]?.id||"";
 const ordered=[...rows].sort((a,b)=>{
  const ap=new Date(a.end_at).getTime()<=now,bp=new Date(b.end_at).getTime()<=now;
  if(ap!==bp)return order==="future"?Number(ap)-Number(bp):Number(bp)-Number(ap);
  const diff=new Date(a.start_at).getTime()-new Date(b.start_at).getTime();
  return ((order==="future"?!ap:ap)?diff:-diff)||String(a.id).localeCompare(String(b.id));
 });
 useEffect(()=>{
  const request=createLatestRequest<Row[]>({
   load:()=>result(supabase.rpc("shop_barbers")),
   onData:list=>{setBarbers(list);setLoadingBarbers(false);},
   onError:e=>{setBarbers([]);setLoadingBarbers(false);setError(friendly(e));if(e instanceof Error&&e.message.includes("ACCESS_DENIED"))onAccessChanged();}
  });
  const update=()=>{if(!document.hidden&&navigator.onLine)void request.refresh();};
  void request.refresh();const timer=window.setInterval(update,30000);
  window.addEventListener("focus",update);window.addEventListener("online",update);document.addEventListener("visibilitychange",update);
  return()=>{request.stop();window.clearInterval(timer);window.removeEventListener("focus",update);window.removeEventListener("online",update);document.removeEventListener("visibilitychange",update);};
 },[onAccessChanged]);
 useEffect(()=>{
  setRows([]);setError("");setLoading(!!barber);if(!barber||!day)return;
  const request=createLatestRequest<Row[]>({
   load:()=>result(supabase.rpc("shop_agenda",{p_barber:barber,p_day:day})),
   onData:list=>{setRows(list);setNow(Date.now());setLoading(false);setError("");},
   onError:e=>{setRows([]);setLoading(false);setError(friendly(e));if(e instanceof Error&&e.message.includes("ACCESS_DENIED"))onAccessChanged();}
  });
  const update=()=>{setNow(Date.now());if(!document.hidden&&navigator.onLine)void request.refresh();};
  void request.refresh();const timer=window.setInterval(update,30000);
  window.addEventListener("focus",update);window.addEventListener("online",update);document.addEventListener("visibilitychange",update);
  return()=>{request.stop();window.clearInterval(timer);window.removeEventListener("focus",update);window.removeEventListener("online",update);document.removeEventListener("visibilitychange",update);};
 },[barber,day,revision,onAccessChanged]);
 function shiftDay(offset:number) {
  setRows([]);setDay(current=>{const date=new Date((current||today())+"T12:00:00Z");date.setUTCDate(date.getUTCDate()+offset);return date.toISOString().slice(0,10);});
 }
 return <section className="content-stack" aria-label="Agenda della barberia">
 {loadingBarbers?<p role="status">Caricamento barbieri…</p>:barbers.length?<div className="shop-barber-tabs" role="group" aria-label="Scegli il barbiere">{barbers.map(b=><button type="button" className={barber===b.id?"primary":"secondary"} aria-pressed={barber===b.id} key={b.id} onClick={()=>{setRows([]);setSelectedBarber(b.id);setDetail(null);setMoving(false);}}>{b.name}</button>)}</div>:!error&&<Empty>Nessun barbiere attivo associato alla barberia.</Empty>}
 <div className="agenda-day-navigation">
 <button type="button" className="secondary" aria-label="Giorno precedente" title="Giorno precedente" onClick={()=>shiftDay(-1)}>←</button>
 <label className="booking-date-field">Giorno<span className="booking-date-control"><input type="date" value={day} onChange={e=>{setRows([]);setDay(e.target.value);}}/></span></label>
 <button type="button" className="secondary" aria-label="Giorno successivo" title="Giorno successivo" onClick={()=>shiftDay(1)}>→</button>
 </div>
 <label>Ordine appuntamenti<select value={order} onChange={e=>setOrder(e.target.value)}><option value="future">Prima i futuri</option><option value="past">Prima i passati</option></select></label>
 {error&&<p className="form-error" role="alert">{error}</p>}
 {loading?<p role="status">Caricamento appuntamenti…</p>:<div className="agenda">
 {ordered.map(e=><button type="button" className={"agenda-row"+(new Date(e.end_at).getTime()<=now?" is-past":"")} key={e.id} title="Apri tutti i dettagli" onClick={()=>{setDetail(e);setMoving(false);setError("");}}>
 <strong>{timeLabel(e.start_at)}</strong><span>{e.client_name||"Cliente"}<small>{e.service_name}</small></span><span>↗</span>
 </button>)}
 </div>}
 {!loading&&barber&&!rows.length&&!error&&<Empty>Nessun appuntamento per questo giorno.</Empty>}
 {detail&&<Modal title="Dettaglio appuntamento" close={()=>{if(!busy){setMoving(false);setDetail(null);}}}>
 <h3>{detail.client_name||"Cliente"}</h3><p>{detail.service_name}<br/>{dateLabel(detail.start_at)} · {timeLabel(detail.start_at)}{detail.price!=null&&<> · {euro(detail.price)}</>}</p>
 {detail.phone&&<a className="primary" href={"tel:"+detail.phone}>Chiama {detail.phone}</a>}
 {error&&<p className="form-error" role="alert">{error}</p>}
 <button type="button" className="secondary" disabled={busy} onClick={()=>setMoving(true)}>Sposta appuntamento</button>
 <button type="button" className="danger" disabled={busy} onClick={async()=>{
  if(busy||!confirm("Confermi la cancellazione dell’appuntamento?"))return;setBusy(true);setError("");
  try{await result(supabase.rpc("cancel_appointment",{p_id:detail.id}));setMoving(false);setDetail(null);setRevision(r=>r+1);}
  catch(e){setError(friendly(e));}finally{setBusy(false);}
 }}>Cancella appuntamento</button>
 {moving&&<RescheduleAppointment appointment={detail} close={()=>setMoving(false)} onSaved={start=>{setMoving(false);setDetail(null);setDay(romeDay(new Date(start)));setRevision(r=>r+1);}}/>}
 </Modal>}
 </section>;
}
