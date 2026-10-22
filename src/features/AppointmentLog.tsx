import { useEffect, useRef, useState } from "react";
import { AppPicker } from "../components/AppPicker";
import { Empty } from "../components/UI";
import { supabase, result, friendly, today, dateLabel, timeLabel, euro } from "../lib/api";
import type { Row } from "../lib/api";

const roleNames: Record<string, string> = {
  barber: "Barbiere", barber_admin: "Barbiere Admin", shop: "Barberia",
};
const fieldNames: Record<string, string> = {
  barber_id: "agenda", kind: "tipo", client_id: "cliente", service_id: "servizio",
  start_at: "inizio", end_at: "fine", status: "stato", service_name: "servizio",
  price: "prezzo", notes: "note", guest_first_name: "nome cliente",
  guest_last_name: "cognome cliente", guest_phone: "telefono cliente",
};
function actionLabel(entry: Row) {
  const block = (entry.after_state || entry.before_state)?.kind === "block";
  const labels: Record<string, string> = {
    created: block ? "Ha bloccato un orario" : "Ha inserito un appuntamento",
    cancelled: block ? "Ha cancellato un blocco" : "Ha cancellato un appuntamento",
    deleted: block ? "Ha eliminato un blocco" : "Ha eliminato un appuntamento",
    rescheduled: block ? "Ha spostato un blocco" : "Ha spostato un appuntamento",
    restored: block ? "Ha ripristinato un blocco" : "Ha ripristinato un appuntamento",
    updated: block ? "Ha modificato un blocco" : "Ha modificato un appuntamento",
  };
  return labels[entry.action] || "Ha modificato l’agenda";
}
function Snapshot({ value, label }: { value: Row; label: string }) {
  return <div className="log-snapshot">
    <strong>{label}</strong>
    <span>{dateLabel(value.start_at)} · {timeLabel(value.start_at)}–{timeLabel(value.end_at)}</span>
    {value.service_name && <span>{value.service_name}{value.price != null ? " · " + euro(Number(value.price)) : ""}</span>}
    {value.notes && <span className="log-notes">{value.notes}</span>}
  </div>;
}
export default function AppointmentLog() {
  const [day, setDay] = useState(today);
  const [rows, setRows] = useState<Row[]>([]);
  const [more, setMore] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [draft, setDraft] = useState("");
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const revision = useRef(0);
  async function load(append = false) {
    const request = ++revision.current;
    setBusy(true); setError("");
    if (!append) { setRows([]); setMore(false); }
    try {
      const cursor = append ? rows.at(-1)?.id : null;
      const data = await result<Row>(search
        ? supabase.rpc("search_appointment_activity_log", { p_search: search, p_before: cursor })
        : supabase.rpc("appointment_activity_log", { p_day: day, p_before: cursor }));
      if (request !== revision.current) return;
      setRows(previous => append ? [...previous, ...data.entries] : data.entries);
      setMore(data.has_more === true);
    } catch (e) {
      if (request !== revision.current) return;
      setRows([]); setMore(false); setError(friendly(e));
    } finally { if (request === revision.current) setBusy(false); }
  }
  useEffect(() => {
    void load();
    return () => { revision.current++; };
  }, [day, search]);
  function shift(offset: number) {
    revision.current++; setRows([]); setMore(false);
    setDay(current => {
      const next = new Date((current || today()) + "T12:00:00Z");
      next.setUTCDate(next.getUTCDate() + offset);
      return next.toISOString().slice(0, 10);
    });
  }
  return <section className="content-stack">
    <button type="button" className="secondary" onClick={() => setSearchOpen(true)}>Cerca</button>
    {searchOpen && <form role="search" onSubmit={event => {
      event.preventDefault();
      const value = draft.trim();
      if (value.length < 2) { setError("Scrivi almeno due caratteri per cercare."); return; }
      event.currentTarget.querySelector("input")?.blur();
      revision.current++; setRows([]); setMore(false);
      if (search === value) void load(); else setSearch(value);
    }}>
      <label>Cerca in tutte le date
        <input type="search" inputMode="search" enterKeyHint="search" autoFocus maxLength={120} placeholder="Nome cliente o evento, es. spostato" value={draft} onChange={event => setDraft(event.target.value)} />
      </label>
      <button type="submit" className="primary" disabled={busy}>Cerca nei log</button>
      <button type="button" className="secondary" onClick={() => { setSearch(""); setDraft(""); setSearchOpen(false); setError(""); }}>Chiudi ricerca</button>
    </form>}
    {search && <p role="status">Risultati in tutte le date per «{search}».</p>}
    <p className="muted">Operazioni sugli appuntamenti e sui blocchi, effettuate da Barbieri, Barbieri Admin e account Barberia. La data si riferisce all’operazione, nel fuso orario italiano. Lo storico parte dall’attivazione dei log.</p>
    {!search && <div className="agenda-day-navigation">
      <button type="button" className="secondary" aria-label="Giorno precedente" onClick={() => shift(-1)}>←</button>
      <label className="booking-date-field">Giorno
        <span className="booking-date-control"><AppPicker type="date" value={day} onChange={event => { const value = event.target.value || today(); if (value !== day) { revision.current++; setRows([]); setMore(false); setDay(value); } }} /></span>
      </label>
      <button type="button" className="secondary" aria-label="Giorno successivo" onClick={() => shift(1)}>→</button>
    </div>}
    <button type="button" className="secondary" disabled={busy} onClick={() => void load()}>Aggiorna log</button>
    {error && <p className="form-error" role="alert">{error}</p>}
    {busy && <p role="status">Caricamento log…</p>}
    {!busy && !error && !rows.length && <Empty>{search ? "Nessun log trovato per questa ricerca." : "Nessuna operazione registrata in questo giorno."}</Empty>}
    <div className="content-stack">
      {rows.map(entry => {
        const before = entry.before_state, after = entry.after_state;
        const customer = entry.client_name || after?.guest_name || before?.guest_name;
        return <article key={entry.id} className="appointment-log-entry content-stack">
          <div className="log-heading"><strong>{entry.actor_name || "Account non più disponibile"}</strong><time dateTime={entry.occurred_at}>{timeLabel(entry.occurred_at)}</time></div>
          <p className="muted">{dateLabel(entry.occurred_at)} · {roleNames[entry.actor_role] || entry.actor_role} · Agenda {entry.barber_name}</p>
          <h3>{actionLabel(entry)}</h3>
          {(after || before)?.kind === "appointment" && <p>Cliente: {customer || "Profilo non più disponibile"}</p>}
          {before && <Snapshot value={before} label={after ? "Prima" : "Appuntamento eliminato"} />}
          {after && <Snapshot value={after} label={before ? "Dopo" : "Dettagli"} />}
          {entry.changed_fields?.length > 0 && <p className="muted">Dati modificati: {[...new Set<string>(entry.changed_fields.map((field: string) => fieldNames[field] || field))].join(", ")}.</p>}
        </article>;
      })}
    </div>
    {more && <button type="button" className="secondary" disabled={busy} onClick={() => void load(true)}>Carica altri log</button>}
  </section>;
}
