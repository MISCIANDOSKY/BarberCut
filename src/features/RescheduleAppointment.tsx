import { useEffect, useRef, useState } from "react";
import { Modal, Empty } from "../components/UI";
import { createLatestRequest } from "../lib/latestRequest.mjs";
import { maxBookingDate, romeDay } from "../lib/dates.mjs";
import {
  supabase,
  result,
  friendly,
  today,
  dateLabel,
  timeLabel,
  euro,
} from "../lib/api";
import type { Row } from "../lib/api";

export default function RescheduleAppointment({
  appointment,
  close,
  onSaved,
}: {
  appointment: Row;
  close: () => void;
  onSaved: (start: string) => void;
}) {
  const [day, setDay] = useState(() => {
    const bookedDay = romeDay(new Date(appointment.start_at));
    return bookedDay >= today()
      ? bookedDay
      : today();
  });
  const [recurring, setRecurring] = useState(false);
  useEffect(() => {let active=true;result<boolean>(supabase.rpc("appointment_is_recurring",{p_id:appointment.id})).then(value=>{if(active)setRecurring(value);}).catch(()=>{});return()=>{active=false;};},[appointment.id]);
  const [slots, setSlots] = useState<Row[]>([]);
  const [selected, setSelected] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [confirmation, setConfirmation] = useState(false);
  const [error, setError] = useState("");
  const selection = useRef("");
  const saving = useRef(false);
  const reloadSlots = useRef<() => Promise<void>>(async () => {});
  const duration = Math.round(
    (new Date(appointment.end_at).getTime() -
      new Date(appointment.start_at).getTime()) /
      60000,
  );
  useEffect(() => {
    selection.current = "";
    setSelected("");
    setSlots([]);
    setLoading(true);
    setError("");
    setConfirmation(false);
    let failed = false;
    const request = createLatestRequest<Row[]>({
      load: () =>
        result(
          supabase.rpc("get_reschedule_slots", {
            p_id: appointment.id,
            p_day: day,
          }),
        ),
      onData: (next) => {
        if (saving.current) return;
        if (failed) setError("");
        failed = false;
        setSlots(next);
        setLoading(false);
        if (
          selection.current &&
          !next.some((slot) => slot.start_at === selection.current)
        ) {
          selection.current = "";
          setSelected("");
          setConfirmation(false);
          setError(
            "L’orario selezionato non è più disponibile. Scegline un altro.",
          );
        }
      },
      onError: (err) => {
        if (saving.current) return;
        failed = true;
        selection.current = "";
        setSelected("");
        setSlots([]);
        setLoading(false);
        setConfirmation(false);
        setError(friendly(err));
      },
    });
    reloadSlots.current = request.refresh;
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
      reloadSlots.current = async () => {};
      window.clearInterval(timer);
      window.removeEventListener("focus", update);
      window.removeEventListener("online", update);
      document.removeEventListener("visibilitychange", update);
    };
  }, [appointment.id, day]);

  async function save(confirmClosed = false) {
    if (saving.current || !selected) return;
    if (!navigator.onLine) {
      setError("Collegati a internet per spostare l’appuntamento.");
      return;
    }
    saving.current = true;
    setBusy(true);
    setError("");
    try {
      await result(
        supabase.rpc("reschedule_appointment", {
          p_id: appointment.id,
          p_start: selected,
          p_confirm_closed: confirmClosed,
        }),
      );
      onSaved(selected);
    } catch (err) {
      if (
        err instanceof Error &&
        err.message.includes("CLOSED_DAY_CONFIRM_REQUIRED")
      ) {
        setConfirmation(true);
      } else {
        setError(friendly(err));
        selection.current = "";
        setSelected("");
        saving.current = false;
        await reloadSlots.current();
      }
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }
  return (
    <Modal
      wide
      className="booking-dialog"
      title="Sposta appuntamento"
      close={() => {
        if (!saving.current) close();
      }}
    >
      <div className="booking-schedule">
        <div className="booking-controls">
          <p className="booking-service-summary">
            <strong>{appointment.service_name}</strong>
            <br />
            {duration} minuti · {euro(appointment.price)}
            <br />
            Attuale: {dateLabel(appointment.start_at)} alle{" "}
            {timeLabel(appointment.start_at)}
          </p>
          <label className="booking-date-field">
            Nuovo giorno
            <span className="booking-date-control">
              <input
                type="date"
                min={today()}
                max={recurring ? undefined : maxBookingDate()}
                value={day}
                disabled={busy}
                onChange={(event) => {
                  selection.current = "";
                  setSelected("");
                  setDay(event.target.value);
                }}
              />
            </span>
          </label>
        </div>
        <section
          className="booking-times"
          aria-label="Orari disponibili per lo spostamento"
          tabIndex={0}
        >
          <span className="step-label">SCEGLI IL NUOVO ORARIO</span>
          {loading ? (
            <p role="status">Aggiornamento disponibilità…</p>
          ) : (
            <>
              <div className="slots">
                {slots.map((slot) => (
                  <button
                    key={slot.start_at}
                    type="button"
                    disabled={busy}
                    className={selected === slot.start_at ? "selected" : ""}
                    aria-pressed={selected === slot.start_at}
                    onClick={() => {
                      selection.current = slot.start_at;
                      setSelected(slot.start_at);
                      setError("");
                    }}
                  >
                    {timeLabel(slot.start_at)}
                  </button>
                ))}
              </div>
              {!slots.length && (
                <Empty>Nessun orario disponibile. Prova un’altra data.</Empty>
              )}
            </>
          )}
        </section>
        <div className="booking-footer">
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          {selected ? (
            <p>
              Nuovo appuntamento:
              <br />
              <strong>
                {dateLabel(selected)} alle {timeLabel(selected)}
              </strong>
            </p>
          ) : (
            <p className="muted">
              Seleziona giorno e orario tra le disponibilità dell’agenda.
            </p>
          )}
          <button
            type="button"
            className="primary"
            disabled={busy || loading || !selected}
            onClick={() => {
              if (
                slots.some(
                  (slot) =>
                    slot.start_at === selected && slot.requires_confirmation,
                )
              )
                setConfirmation(true);
              else void save();
            }}
          >
            {busy ? "Spostamento in corso…" : "Conferma spostamento"}
          </button>
        </div>
      </div>
      {confirmation && (
        <Modal
          title="Conferma spostamento"
          close={() => setConfirmation(false)}
        >
          <p>
            In questo giorno o in questa fascia oraria risulti chiuso. Sei
            sicuro di voler spostare qui l’appuntamento?
          </p>
          <div className="two">
            <button
              type="button"
              className="secondary"
              disabled={busy}
              onClick={() => setConfirmation(false)}
            >
              No
            </button>
            <button
              type="button"
              className="primary"
              disabled={busy || !selected}
              onClick={() => {
                setConfirmation(false);
                void save(true);
              }}
            >
              Sì
            </button>
          </div>
        </Modal>
      )}
    </Modal>
  );
}
