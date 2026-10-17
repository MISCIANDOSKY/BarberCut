import { useEffect, useState } from "react";
import { romeLocalToISO } from "../lib/dates.mjs";
import { Empty, Modal } from "../components/UI";
import { supabase, result, dateLabel, timeLabel, today } from "../lib/api";
import type { Row } from "../lib/api";
import Booking from "./Booking";
const weekdays = [
  "Domenica",
  "Lunedì",
  "Martedì",
  "Mercoledì",
  "Giovedì",
  "Venerdì",
  "Sabato",
];
type Props = {
  user: Row;
  barbers: Row[];
  services: Row[];
  settings: Row;
  notify: (s: string) => void;
  section: string;
  isAdmin?: boolean;
};
export default function Manage({
  user,
  barbers,
  services,
  settings,
  notify,
  section,
  isAdmin = false,
}: Props) {
  const scopedBarbers = barbers.filter(
    (item) => isAdmin || item.user_id === user.id,
  );
  const [selectedBarber, setB] = useState(
      barbers.find((x) => x.user_id === user.id)?.id || barbers[0]?.id || "",
    ),
    [day, setDay] = useState(today()),
    [rows, setRows] = useState<Row[]>([]),
    [detail, setDetail] = useState<Row | null>(null),
    [client, setClient] = useState<Row | null>(null),
    [hours, setHours] = useState<Row[]>([]),
    [hoursBarber, setHoursBarber] = useState(""),
    [weekday, setWeekday] = useState(1),
    [closed, setClosed] = useState(false),
    [exceptionClosed, setExceptionClosed] = useState(false),
    [exceptions, setExceptions] = useState<Row[]>([]),
    [busy, setBusy] = useState(false);
  const b = scopedBarbers.some((item) => item.id === selectedBarber)
    ? selectedBarber
    : scopedBarbers[0]?.id || "";
  async function load() {
    if (!b) return;
    try {
      if (section === "Appuntamenti") {
        const data = await result(
          supabase
            .from("calendar_entries")
            .select("*,profiles!calendar_entries_client_id_fkey(*)")
            .eq("barber_id", b)
            .eq("status", "confirmed")
            .order("start_at"),
        );
        setRows(
          (data as Row[]).filter(
            (x) =>
              new Intl.DateTimeFormat("en-CA", {
                timeZone: "Europe/Rome",
                year: "numeric",
                month: "2-digit",
                day: "2-digit",
              }).format(new Date(x.start_at)) === day,
          ),
        );
      }
      if (section === "Orari di lavoro") {
        setHoursBarber("");
        setHours(
          (await result(
            supabase
              .from("working_hours")
              .select("*")
              .eq("barber_id", b)
              .order("weekday"),
          )) as Row[],
        );
        setHoursBarber(b);
        setExceptions(
          (await result(
            supabase
              .from("schedule_exceptions")
              .select("*")
              .eq("barber_id", b)
              .gte("day", today())
              .order("day"),
          )) as Row[],
        );
      }
    } catch {
      notify("Impossibile caricare l’agenda.");
    }
  }
  useEffect(() => {
    load();
  }, [b, day, section]);
  useEffect(() => {
    setClosed(!hours.some((h) => h.weekday === weekday));
  }, [b, weekday, hours]);
  async function save(table: string, obj: Row) {
    setBusy(true);
    try {
      await result(supabase.from(table).insert(obj));
      notify("Salvato.");
      load();
    } catch (e) {
      notify((await import("../lib/api")).friendly(e));
    } finally {
      setBusy(false);
    }
  }
  if (!scopedBarbers.length)
    return (
      <Empty>
        Nessuna agenda associata al tuo account. Contatta l’amministratore.
      </Empty>
    );
  return (
    <>
      {scopedBarbers.length > 1 && (
        <label>
          Agenda
          <select
            value={b}
            onChange={(e) => {
              setB(e.target.value);
              setClient(null);
            }}
          >
            {scopedBarbers.map((x) => (
              <option key={x.id} value={x.id}>
                {x.name}
              </option>
            ))}
          </select>
        </label>
      )}
      {section === "Appuntamenti" && (
        <>
          <label>
            Giorno
            <input
              type="date"
              value={day}
              onChange={(e) => setDay(e.target.value)}
            />
          </label>
          <div className="agenda">
            {rows.map((e) => (
              <button
                className="agenda-row"
                key={e.id}
                onClick={() => setDetail(e)}
              >
                <strong>{timeLabel(e.start_at)}</strong>
                <span>
                  {e.kind === "block"
                    ? "Orario bloccato"
                    : (e.guest_first_name || e.profiles?.first_name || "") +
                      " " +
                      (e.guest_last_name || e.profiles?.last_name || "")}
                  <small>{e.service_name || e.notes}</small>
                </span>
                <span>↗</span>
              </button>
            ))}
          </div>
          {!rows.length && (
            <Empty>Nessun appuntamento per questo giorno.</Empty>
          )}
        </>
      )}
      {section === "Nuova prenotazione" && (
        <>
          {!client ? (
            <form
              onSubmit={(event) => {
                event.preventDefault();
                const values = new FormData(event.currentTarget);
                const first_name = String(
                  values.get("first_name") || "",
                ).trim();
                const last_name = String(values.get("last_name") || "").trim();
                if (!first_name || !last_name) {
                  notify("Inserisci nome e cognome del cliente.");
                  return;
                }
                setClient({
                  first_name,
                  last_name,
                  phone: String(values.get("phone") || "").trim(),
                });
              }}
            >
              <div className="two">
                <label>
                  Nome
                  <input
                    name="first_name"
                    autoComplete="given-name"
                    maxLength={120}
                    required
                  />
                </label>
                <label>
                  Cognome
                  <input
                    name="last_name"
                    autoComplete="family-name"
                    maxLength={120}
                    required
                  />
                </label>
              </div>
              <label>
                Telefono (facoltativo)
                <input
                  name="phone"
                  type="tel"
                  autoComplete="tel"
                  maxLength={40}
                />
              </label>
              <button className="primary">Scegli servizio e orario</button>
            </form>
          ) : (
            <>
              <p>
                Prenotazione per{" "}
                <strong>
                  {client.first_name} {client.last_name}
                </strong>{" "}
                <button className="text" onClick={() => setClient(null)}>
                  Cambia
                </button>
              </p>
              <Booking
                key={b}
                user={user}
                guest={client}
                services={services}
                barbers={scopedBarbers.filter((x) => x.id === b)}
                settings={settings}
                notify={notify}
                login={() => {}}
                onBooked={load}
              />
            </>
          )}
        </>
      )}
      {section === "Blocca orario" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            const v = new FormData(e.currentTarget);
            save("calendar_entries", {
              barber_id: b,
              kind: "block",
              start_at: romeLocalToISO(String(v.get("start"))),
              end_at: romeLocalToISO(String(v.get("end"))),
              notes: v.get("notes"),
              created_by: user.id,
            });
          }}
        >
          <p>
            Per ferie o intere giornate usa anche le eccezioni negli Orari di
            lavoro.
          </p>
          <p className="muted">Tutti gli orari sono nel fuso Europe/Rome.</p>
          <label>
            Da
            <input name="start" type="datetime-local" required />
          </label>
          <label>
            A<input name="end" type="datetime-local" required />
          </label>
          <label>
            Nota
            <input name="notes" />
          </label>
          <button className="primary" disabled={busy}>
            Blocca intervallo
          </button>
        </form>
      )}
      {section === "Orari di lavoro" && (
        <>
          <h3>Settimana abituale</h3>
          <p className="muted">
            Scegli un giorno e spunta Chiuso oppure aggiungi gli orari. Puoi
            aggiungere più intervalli per separare mattina e pomeriggio.
          </p>
          {hoursBarber !== b ? (
            <Empty>Caricamento orari…</Empty>
          ) : (
            [1, 2, 3, 4, 5, 6, 0].map((dayIndex) => {
              const intervals = hours.filter((h) => h.weekday === dayIndex);
              return (
                <div key={dayIndex}>
                  <h4>{weekdays[dayIndex]}</h4>
                  {!intervals.length && <p className="muted">Chiuso</p>}
                  {intervals.map((h) => (
                    <div className="table-row" key={h.id}>
                      <span>
                        {h.opens.slice(0, 5)}–{h.closes.slice(0, 5)}
                      </span>
                      <button
                        className="text"
                        disabled={busy}
                        onClick={async () => {
                          setBusy(true);
                          try {
                            await result(
                              supabase
                                .from("working_hours")
                                .delete()
                                .eq("id", h.id)
                                .eq("barber_id", b),
                            );
                            await load();
                          } catch (error) {
                            notify(
                              (await import("../lib/api")).friendly(error),
                            );
                          } finally {
                            setBusy(false);
                          }
                        }}
                      >
                        Rimuovi
                      </button>
                    </div>
                  ))}
                </div>
              );
            })
          )}
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              const form = e.currentTarget;
              const values = new FormData(form);
              setBusy(true);
              try {
                if (closed) {
                  await result(
                    supabase
                      .from("working_hours")
                      .delete()
                      .eq("barber_id", b)
                      .eq("weekday", weekday),
                  );
                  notify(weekdays[weekday] + ": chiuso.");
                } else {
                  const opens = String(values.get("opens") || "");
                  const closes = String(values.get("closes") || "");
                  if (!opens || !closes || opens >= closes) {
                    notify(
                      "Inserisci un orario di chiusura successivo all’apertura.",
                    );
                    return;
                  }
                  await result(
                    supabase.from("working_hours").insert({
                      barber_id: b,
                      weekday,
                      opens,
                      closes,
                    }),
                  );
                  notify("Intervallo salvato.");
                }
                await load();
              } catch (error) {
                notify((await import("../lib/api")).friendly(error));
              } finally {
                setBusy(false);
              }
            }}
          >
            <label>
              Giorno
              <select
                name="weekday"
                value={weekday}
                disabled={busy || hoursBarber !== b}
                onChange={(e) => setWeekday(Number(e.target.value))}
              >
                {[1, 2, 3, 4, 5, 6, 0].map((i) => (
                  <option value={i} key={i}>
                    {weekdays[i]}
                  </option>
                ))}
              </select>
            </label>
            <label className="check">
              <input
                type="checkbox"
                name="closed"
                checked={closed}
                disabled={busy || hoursBarber !== b}
                onChange={(e) => setClosed(e.target.checked)}
              />
              Chiuso
            </label>
            {closed && (
              <p className="muted">
                Salvando, il giorno sarà chiuso ogni settimana. Eventuali
                intervalli di questo giorno verranno rimossi. Le eccezioni per
                singole date restano separate.
              </p>
            )}
            <div className="two">
              <label>
                Apertura
                <input
                  type="time"
                  name="opens"
                  required={!closed}
                  disabled={closed || busy || hoursBarber !== b}
                  step="900"
                />
              </label>
              <label>
                Chiusura
                <input
                  type="time"
                  name="closes"
                  required={!closed}
                  disabled={closed || busy || hoursBarber !== b}
                  step="900"
                />
              </label>
            </div>
            <button className="secondary" disabled={busy || hoursBarber !== b}>
              {closed ? "Salva giorno di chiusura" : "Aggiungi intervallo"}
            </button>
          </form>
          <h3>Eccezioni e ferie</h3>
          <p className="muted">
            Le festività italiane sono chiuse. Le eccezioni di una data hanno
            priorità sulla settimana abituale; una chiusura prevale sugli
            intervalli di apertura.
          </p>
          {exceptions.map((x) => (
            <div className="table-row" key={x.id}>
              <span>
                {x.day} · {x.closed ? "Chiuso" : x.opens + "–" + x.closes}
              </span>
              <button
                className="text"
                onClick={async () => {
                  await result(
                    supabase
                      .from("schedule_exceptions")
                      .delete()
                      .eq("id", x.id),
                  );
                  load();
                }}
              >
                Rimuovi
              </button>
            </div>
          ))}
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const v = new FormData(e.currentTarget);
              const closed = v.get("closed") === "on";
              save("schedule_exceptions", {
                barber_id: b,
                day: v.get("day"),
                closed,
                opens: closed ? null : v.get("opens"),
                closes: closed ? null : v.get("closes"),
              });
            }}
          >
            <label>
              Data
              <input type="date" name="day" required />
            </label>
            <label className="check">
              <input
                type="checkbox"
                name="closed"
                checked={exceptionClosed}
                onChange={(e) => setExceptionClosed(e.target.checked)}
              />
              Chiuso tutto il giorno
            </label>
            <div className="two">
              <label>
                Apertura
                <input
                  type="time"
                  name="opens"
                  disabled={exceptionClosed}
                  required={!exceptionClosed}
                  step="900"
                />
              </label>
              <label>
                Chiusura
                <input
                  type="time"
                  name="closes"
                  disabled={exceptionClosed}
                  required={!exceptionClosed}
                  step="900"
                />
              </label>
            </div>
            <button className="secondary" disabled={busy}>
              Salva eccezione
            </button>
          </form>
        </>
      )}
      {detail && (
        <Modal
          title={
            detail.kind === "block"
              ? "Orario bloccato"
              : "Dettaglio appuntamento"
          }
          close={() => setDetail(null)}
        >
          <h3>
            {detail.guest_first_name || detail.profiles?.first_name}{" "}
            {detail.guest_last_name || detail.profiles?.last_name}
          </h3>
          <p>
            {detail.service_name || detail.notes}
            <br />
            {dateLabel(detail.start_at)} · {timeLabel(detail.start_at)}
          </p>
          {(detail.guest_phone || detail.profiles?.phone) && (
            <a
              className="primary"
              href={"tel:" + (detail.guest_phone || detail.profiles.phone)}
            >
              Chiama {detail.guest_phone || detail.profiles.phone}
            </a>
          )}
          {detail.kind === "appointment" && (
            <form
              onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                try {
                  const v = new FormData(e.currentTarget);
                  await result(
                    supabase.rpc("reschedule_appointment", {
                      p_id: detail.id,
                      p_start: romeLocalToISO(String(v.get("start"))),
                    }),
                  );
                  notify("Appuntamento modificato.");
                  setDetail(null);
                  load();
                } catch (e) {
                  notify((await import("../lib/api")).friendly(e));
                } finally {
                  setBusy(false);
                }
              }}
            >
              <label>
                Nuova data e ora (Europe/Rome)
                <input type="datetime-local" step="900" name="start" required />
              </label>
              <button className="secondary" disabled={busy}>
                Sposta appuntamento
              </button>
            </form>
          )}
          <button
            className="danger"
            disabled={busy}
            onClick={async () => {
              if (!confirm("Confermi la cancellazione?")) return;
              setBusy(true);
              try {
                await result(
                  supabase.rpc("cancel_appointment", { p_id: detail.id }),
                );
                setDetail(null);
                load();
              } catch (e) {
                notify((await import("../lib/api")).friendly(e));
              } finally {
                setBusy(false);
              }
            }}
          >
            Cancella {detail.kind === "block" ? "blocco" : "appuntamento"}
          </button>
        </Modal>
      )}
    </>
  );
}
