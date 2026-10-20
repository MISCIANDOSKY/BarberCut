import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { Modal, Empty } from "../components/UI";
import { supabase,result,friendly,dateLabel,timeLabel,today } from "../lib/api";
import type { Row } from "../lib/api";
import { romeDay } from "../lib/dates.mjs";
import { createLatestRequest } from "../lib/latestRequest.mjs";

export default function RecurringBooking({booking,done}:{booking:Row;done:()=>void}) {
 const [stage,setStage]=useState<"ask"|"configure"|"review">("ask");
 const [allowance,setAllowance]=useState<Row|null>(null),[every,setEvery]=useState(7),[count,setCount]=useState(5);
 const [plan,setPlan]=useState(""),[offset,setOffset]=useState(0),[rows,setRows]=useState<Row[]>([]);
 const [choices,setChoices]=useState<Record<number,string|null>>({});
 const [moving,setMoving]=useState<Row|null>(null),[error,setError]=useState(""),[busy,setBusy]=useState(false),[loaded,setLoaded]=useState(false);
 const saving=useRef(false);
 useEffect(()=>{let active=true;result<Row>(supabase.rpc("recurring_allowance")).then(a=>{if(!active)return;setAllowance(a);setCount(a.unlimited?5:Math.min(5,Math.max(0,a.maximum-a.used)));}).catch(e=>{if(active)setError(friendly(e));});return()=>{active=false;};},[]);
 const remaining=allowance?.unlimited?undefined:Math.max(0,(allowance?.maximum??0)-(allowance?.used??0));
 async function loadPage(id:string,page:number) {
  setLoaded(false);
  const next=await result<Row[]>(supabase.rpc("list_recurring_dates",{p_plan:id,p_offset:page}));
  setRows(next);setChoices(Object.fromEntries(next.filter(r=>r.state==="pending"&&r.available).map(r=>[r.ordinal,r.expected_start])));setOffset(page);setLoaded(true);
 }
 async function prepare(e:FormEvent) {
  e.preventDefault();if(saving.current)return;saving.current=true;setBusy(true);setError("");
  try{const id=await result<string>(supabase.rpc("create_recurring_plan",{p_anchor:booking.id,p_every:every,p_count:count}));setPlan(id);await loadPage(id,0);setStage("review");}catch(e){setError(friendly(e));}finally{saving.current=false;setBusy(false);}
 }
 async function savePage() {
  if(saving.current||!navigator.onLine)return;saving.current=true;setBusy(true);setError("");
  const next=rows.map(r=>({...r}));let failure=false;
  try {
   for(const row of next) {
    if(row.state!=="pending")continue;
    if(choices[row.ordinal]===undefined){failure=true;continue;}
    try {
     const id=await result<string|null>(supabase.rpc("save_recurring_date",{p_plan:plan,p_ordinal:row.ordinal,p_start:choices[row.ordinal]}));
     row.state=id?"booked":"skipped";row.booked_start=choices[row.ordinal];row.entry_id=id;
    } catch(e) {row.available=false;row.error=friendly(e);failure=true;}
   }
   setRows(next);
   if(failure) {setChoices(old=>Object.fromEntries(Object.entries(old).filter(([key])=>!next.some(r=>r.ordinal===Number(key)&&r.error))));setError("Le date confermate sono state salvate. Controlla le date rimaste: puoi saltarle o scegliere un altro giorno e orario.");return;}
   if(offset+rows.length<count)await loadPage(plan,offset+rows.length);
   else done();
  } catch(e){setError(friendly(e));}finally{saving.current=false;setBusy(false);}
 }
 const close=()=>{if(!saving.current)done();};
 if(stage==="ask")return <Modal title="Vuoi prenotare periodicamente altri appuntamenti?" close={close}>
 <p className="notice">La tua prenotazione è confermata.</p>
 <p>Puoi programmare i tuoi prossimi appuntamenti con lo stesso barbiere e servizio. Ricorda che puoi sempre cancellare un singolo appuntamento da Le mie prenotazioni.</p>
 <div className="two"><button className="secondary" onClick={done}>No</button><button className="primary" onClick={()=>setStage("configure")}>Sì</button></div>
 </Modal>;
 return <Modal title="Prenotazioni periodiche" close={close} wide>
 <p><strong>{booking.service_name}</strong><br/>Prima prenotazione: {dateLabel(booking.start_at)} alle {timeLabel(booking.start_at)}</p>
 {error&&<p className="form-error" role="alert">{error}</p>}
 {stage==="configure"?<form onSubmit={prepare}>
 <p className="muted">Stesso giorno della settimana e stessa ora locale. Gli appuntamenti aggiuntivi possono superare i 6 mesi; quelli non disponibili potranno essere saltati o spostati.</p>
 <label>Ripeti ogni<select value={every} disabled={busy} onChange={e=>setEvery(Number(e.target.value))}>{[7,14,21,28].map(n=><option key={n} value={n}>{n} giorni</option>)}</select></label>
 <label>Numero di appuntamenti aggiuntivi<input type="number" min="1" step="1" max={remaining} value={count||""} disabled={busy||!allowance} required onChange={e=>setCount(Number(e.target.value))}/></label>
 {allowance&&<p className="muted">{allowance.unlimited?"Nessun limite di numero impostato.":`Puoi aggiungere ancora ${remaining} appuntamenti periodici futuri.`}</p>}
 {!allowance&&!error&&<p role="status">Caricamento impostazioni…</p>}
 <button className="primary" disabled={busy||!allowance||count<1||remaining===0||!navigator.onLine}>{busy?"Preparazione…":"Verifica le date"}</button>
 </form>:<>
 <p className="muted">Date {offset+1}–{Math.min(offset+25,count)} di {count}. Le date successive mantengono la frequenza originale anche quando ne sposti una.</p>
 {!loaded&&<p role="status">Caricamento date…</p>}
 {rows.map(row=><article className="recurring-date content-stack" key={row.ordinal}>
 <strong>{row.ordinal}. {dateLabel(row.expected_start)} · {timeLabel(row.expected_start)}</strong>
 {row.state==="booked"?<p className="notice">Confermato{row.booked_start?": "+dateLabel(row.booked_start)+" alle "+timeLabel(row.booked_start):""}.</p>:row.state==="skipped"?<p className="muted">Data saltata.</p>:<>
 {row.error&&<p className="form-error" role="alert">{row.error}</p>}
 {!row.available&&choices[row.ordinal]===undefined&&<p className="notice">Questa data o fascia oraria non è disponibile. Vuoi annullare questa ripetizione oppure spostarla?</p>}
 {choices[row.ordinal]===null?<p className="muted">Questa ripetizione sarà saltata.</p>:choices[row.ordinal]&&<p>{dateLabel(choices[row.ordinal]!)} alle {timeLabel(choices[row.ordinal]!)}</p>}
 <div className="two"><button className="secondary" disabled={busy} onClick={()=>setChoices(old=>({...old,[row.ordinal]:null}))}>Salta questa data</button><button className="secondary" disabled={busy} onClick={()=>setMoving(row)}>Sposta</button></div>
 </>}
 </article>)}
 <button className="primary" disabled={busy||!loaded||!navigator.onLine||rows.some(r=>r.state==="pending"&&choices[r.ordinal]===undefined)} onClick={()=>void savePage()}>{busy?"Conferma in corso…":offset+rows.length<count?"Conferma queste date e continua":"Conferma prenotazioni periodiche"}</button>
 <button className="text" disabled={busy} onClick={done}>Termina e vai alle mie prenotazioni</button>
 </>}
 {moving&&<RecurringTime plan={plan} initial={romeDay(new Date(moving.expected_start))} close={()=>setMoving(null)} choose={start=>{setChoices(old=>({...old,[moving.ordinal]:start}));setMoving(null);}}/>}
 </Modal>;
}

function RecurringTime({plan,initial,close,choose}:{plan:string;initial:string;close:()=>void;choose:(start:string)=>void}) {
 const [day,setDay]=useState(initial),[slots,setSlots]=useState<Row[]>([]),[selected,setSelected]=useState(""),[loading,setLoading]=useState(true),[error,setError]=useState("");
 useEffect(()=>{
  setSelected("");setSlots([]);setLoading(true);setError("");
  const request=createLatestRequest<Row[]>({load:()=>result(supabase.rpc("get_recurring_slots",{p_plan:plan,p_day:day})),onData:next=>{setSlots(next);setLoading(false);setError("");setSelected(current=>next.some(s=>s.start_at===current)?current:"");},onError:e=>{setSlots([]);setSelected("");setLoading(false);setError(friendly(e));}});
  const update=()=>{if(!document.hidden&&navigator.onLine)void request.refresh();};void request.refresh();
  const timer=window.setInterval(update,30000);window.addEventListener("focus",update);window.addEventListener("online",update);
  return()=>{request.stop();window.clearInterval(timer);window.removeEventListener("focus",update);window.removeEventListener("online",update);};
 },[plan,day]);
 return <Modal title="Sposta la ripetizione" close={close} wide className="booking-dialog"><div className="booking-schedule">
 <div className="booking-controls"><label className="booking-date-field">Giorno<span className="booking-date-control"><input type="date" min={today()} value={day} onChange={e=>setDay(e.target.value)}/></span></label></div>
 <section className="booking-times" aria-label="Orari disponibili" tabIndex={0}>{loading?<p role="status">Aggiornamento disponibilità…</p>:<><div className="slots">{slots.map(s=><button key={s.start_at} className={selected===s.start_at?"selected":""} onClick={()=>setSelected(s.start_at)}>{timeLabel(s.start_at)}</button>)}</div>{!slots.length&&<Empty>Nessun orario disponibile. Scegli un’altra data.</Empty>}</>}</section>
 <div className="booking-footer">{error&&<p className="form-error" role="alert">{error}</p>}<button className="primary" disabled={!selected||loading||!navigator.onLine} onClick={()=>choose(selected)}>Usa questo giorno e orario</button></div>
 </div></Modal>;
}
