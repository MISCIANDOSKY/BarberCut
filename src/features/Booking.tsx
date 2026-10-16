import { useEffect, useRef, useState } from "react";
import { createLatestRequest } from "../lib/latestRequest.mjs";
import { maxBookingDate } from "../lib/dates.mjs";
import { Empty } from "../components/UI";
import {
  supabase,
  result,
  euro,
  today,
  dateLabel,
  timeLabel,
} from "../lib/api";
import type { Row } from "../lib/api";
export default function Booking({
  user,
  services,
  barbers,
  settings,
  notify,
  login,
  onBooked,
  clientId,
  guest,
}: {
  user: Row | null;
  services: Row[];
  barbers: Row[];
  settings: Row;
  notify: (s: string) => void;
  login: () => void;
  onBooked: () => void;
  clientId?: string;
  guest?: Row;
}) {
  const [service, setService] = useState(""),
    [barber, setBarber] = useState(""),
    [day, setDay] = useState(today()),
    [slots, setSlots] = useState<Row[]>([]),
    [selected, setSelected] = useState(""),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(false),
    [confirmed, setConfirmed] = useState<Row | null>(null),
    [links, setLinks] = useState<Row[]>([]);
  const selection = useRef("");
  const saving = useRef(false);
  const activeServices = services.filter(
    (s) =>
      s.active &&
      links.some(
        (link) =>
          link.service_id === s.id &&
          barbers.some((item) => item.id === link.barber_id && item.active),
      ),
  );
  const eligibleBarbers = barbers.filter(
    (b) =>
      b.active &&
      links.some(
        (link) => link.barber_id === b.id && link.service_id === service,
      ),
  );
  const chosenBarber = eligibleBarbers.some((b) => b.id === barber)
    ? barber
    : eligibleBarbers.length === 1
      ? eligibleBarbers[0].id
      : "";
  useEffect(() => {
    selection.current = selected;
  }, [selected]);
  const svc = services.find((s) => s.id === service);
  const maxDate = maxBookingDate();
  useEffect(() => {
    result(supabase.from("barber_services").select("*"))
      .then(setLinks)
      .catch(() => notify("Impossibile caricare i servizi."));
  }, []);
  useEffect(() => {
    selection.current = "";
    setSelected("");
    setSlots([]);
    setLoading(false);
    if (!service || !chosenBarber || !day || confirmed) return;
    let failed = false;
    setLoading(true);
    const request = createLatestRequest<Row[]>({
      load: () =>
        result(
          supabase.rpc("get_available_slots", {
            p_barber: chosenBarber,
            p_service: service,
            p_day: day,
          }),
        ),
      onData: (next) => {
        if (saving.current) return;
        failed = false;
        setSlots(next);
        setLoading(false);
        if (
          selection.current &&
          !next.some((s) => s.start_at === selection.current)
        ) {
          selection.current = "";
          setSelected("");
          notify(
            "L’orario selezionato non è più disponibile. Scegline un altro.",
          );
        }
      },
      onError: () => {
        if (saving.current) return;
        setSlots([]);
        selection.current = "";
        setSelected("");
        setLoading(false);
        if (!failed)
          notify(
            "Non riesco ad aggiornare gli orari. Riprova quando sei online.",
          );
        failed = true;
      },
    });
    const update = () => {
      if (!saving.current && !document.hidden && navigator.onLine)
        void request.refresh();
    };
    void request.refresh();
    const timer = window.setInterval(update, 30000);
    window.addEventListener("focus", update);
    window.addEventListener("online", update);
    document.addEventListener("visibilitychange", update);
    return () => {
      request.stop();
      window.clearInterval(timer);
      window.removeEventListener("focus", update);
      window.removeEventListener("online", update);
      document.removeEventListener("visibilitychange", update);
    };
  }, [service, chosenBarber, day, confirmed, notify]);
  async function book() {
    if (saving.current || !selected || !svc) return;
    if (!navigator.onLine) {
      notify("Collegati a internet per confermare la prenotazione.");
      return;
    }
    if (!user) {
      login();
      return;
    }
    saving.current = true;
    setBusy(true);
    try {
      await result(
        guest
          ? supabase.rpc("book_guest_appointment", {
              p_barber: chosenBarber,
              p_service: service,
              p_start: selected,
              p_first_name: guest.first_name,
              p_last_name: guest.last_name,
              p_phone: guest.phone || "",
            })
          : supabase.rpc("book_appointment", {
              p_barber: chosenBarber,
              p_service: service,
              p_start: selected,
              ...(clientId ? { p_client: clientId } : {}),
            }),
      );
      setConfirmed({
        start_at: selected,
        end_at: new Date(
          new Date(selected).getTime() + svc!.duration_minutes * 60000,
        ).toISOString(),
        service_name: svc!.name,
      });
      onBooked();
    } catch (e) {
      notify((await import("../lib/api")).friendly(e));
      setSelected("");
      try {
        setSlots(
          (await result(
            supabase.rpc("get_available_slots", {
              p_barber: chosenBarber,
              p_service: service,
              p_day: day,
            }),
          )) as Row[],
        );
      } catch {
        setSlots([]);
      }
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }
  if (confirmed)
    return (
      <div className="success">
        <span className="success-mark">✓</span>
        <h3>Prenotazione confermata!</h3>
        <p>
          {confirmed.service_name}
          <br />
          {dateLabel(confirmed.start_at)} · {timeLabel(confirmed.start_at)}
        </p>
        <p>Vuoi aggiungerla al tuo calendario?</p>
        <button className="primary" onClick={() => downloadCalendar(confirmed)}>
          Sì, aggiungi al calendario
        </button>
        <button
          className="text"
          onClick={() => {
            setConfirmed(null);
            setSelected("");
          }}
        >
          No, grazie
        </button>
      </div>
    );
  if (!settings.bookings_enabled && !clientId && !guest)
    return (
      <Empty>
        Stiamo preparando la nuova agenda. Le prenotazioni apriranno a breve.
      </Empty>
    );
  return (
    <>
      {!user && (
        <p className="notice">
          Per confermare la prenotazione devi{" "}
          <button className="text" onClick={login}>
            accedere o registrarti
          </button>
          .
        </p>
      )}
      <span className="step-label">01 / SCEGLI IL SERVIZIO</span>
      <div className="service-list">
        {activeServices.map((s) => (
          <button
            key={s.id}
            disabled={busy}
            className={"service " + (service === s.id ? "selected" : "")}
            onClick={() => {
              setService(s.id);
              setBarber("");
            }}
          >
            <span>
              <strong>{s.name}</strong>
              <small>{s.duration_minutes} minuti</small>
            </span>
            <strong>{euro(s.price)}</strong>
          </button>
        ))}
      </div>
      {!activeServices.length && <Empty>Nessun servizio disponibile.</Empty>}
      {service && (
        <>
          <span className="step-label">02 / SCEGLI IL GIORNO</span>
          {eligibleBarbers.length > 1 && (
            <label>
              Barbiere
              <select
                value={chosenBarber}
                disabled={busy}
                onChange={(e) => setBarber(e.target.value)}
              >
                <option value="">Scegli il barbiere</option>
                {eligibleBarbers.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          <label>
            Giorno
            <input
              type="date"
              disabled={busy}
              min={today()}
              max={maxDate}
              value={day}
              onChange={(e) => setDay(e.target.value)}
            />
          </label>
          <span className="step-label">03 / TROVA IL TUO ORARIO</span>
          {loading ? (
            <p role="status">Aggiornamento disponibilità…</p>
          ) : (
            <>
              <div className="slots">
                {slots.map((s) => (
                  <button
                    className={selected === s.start_at ? "selected" : ""}
                    key={s.start_at}
                    disabled={busy}
                    onClick={() => setSelected(s.start_at)}
                  >
                    {timeLabel(s.start_at)}
                  </button>
                ))}
              </div>
              {chosenBarber && !slots.length && (
                <Empty>
                  Nessun orario disponibile per questo giorno. Prova un’altra
                  data.
                </Empty>
              )}
            </>
          )}
          {selected && (
            <div className="confirmation">
              <p>
                <strong>{svc?.name}</strong>
                <br />
                {dateLabel(selected)} alle {timeLabel(selected)}
                <br />
                {svc && euro(svc.price)}
              </p>
              <button
                className="primary"
                disabled={busy || !navigator.onLine}
                onClick={book}
              >
                {busy ? "Conferma in corso…" : "Conferma prenotazione →"}
              </button>
            </div>
          )}
        </>
      )}
    </>
  );
}
export function downloadCalendar(e: Row) {
  const stamp = (s: string) =>
    new Date(s)
      .toISOString()
      .replace(/[-:]/g, "")
      .replace(/\.\d{3}/, "");
  const escape = (s: string) =>
    s
      .replace(/\\/g, "\\\\")
      .replace(/\n/g, "\\n")
      .replace(/,/g, "\\,")
      .replace(/;/g, "\\;");
  const text = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//BarberCut//Appuntamenti//IT",
    "BEGIN:VEVENT",
    "UID:" + crypto.randomUUID() + "@barbercut",
    "DTSTAMP:" + stamp(new Date().toISOString()),
    "DTSTART:" + stamp(e.start_at),
    "DTEND:" + stamp(e.end_at),
    "SUMMARY:Appuntamento Barbiere",
    "DESCRIPTION:" + escape(e.service_name || ""),
    "BEGIN:VALARM",
    "TRIGGER:-PT1H",
    "ACTION:DISPLAY",
    "DESCRIPTION:Appuntamento Barbiere",
    "END:VALARM",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");
  const u = URL.createObjectURL(
      new Blob([text], { type: "text/calendar;charset=utf-8" }),
    ),
    a = document.createElement("a");
  a.href = u;
  a.download = "BarberCut.ics";
  a.click();
  setTimeout(() => URL.revokeObjectURL(u), 1000);
}
