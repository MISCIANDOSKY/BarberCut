import { useEffect, useState } from "react";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";
export default function BookingHorizon({
  settings,
  refresh,
}: {
  settings: Row;
  refresh: () => void;
}) {
  const [months, setMonths] = useState(
    String(settings.booking_horizon_months ?? 6),
  );
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState("");
  useEffect(
    () => setMonths(String(settings.booking_horizon_months ?? 6)),
    [settings.booking_horizon_months],
  );
  return (
    <section className="shop-address-editor content-stack">
      <h3>Prenotazioni future</h3>
      <p className="muted">
        Scegli con quanti mesi di anticipo si può prenotare. Il limite vale
        anche per gli appuntamenti inseriti a mano e gli spostamenti, mentre le
        prenotazioni periodiche sono escluse. Gli appuntamenti già confermati
        restano validi. La scelta è condivisa tra Admin e Barbiere Admin.
      </p>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (busy) return;
          const value = Number(months);
          if (!Number.isInteger(value) || value < 1 || value > 120) {
            setError("Inserisci un numero intero di mesi da 1 a 120.");
            return;
          }
          setBusy(true);
          setError("");
          setMessage("");
          try {
            await result(
              supabase.rpc("set_booking_horizon", { p_months: value }),
            );
            setMessage("Limite delle prenotazioni future salvato.");
            refresh();
          } catch (err) {
            setError(friendly(err));
          } finally {
            setBusy(false);
          }
        }}
      >
        <label>
          Mesi massimi per le prenotazioni future
          <input
            type="number"
            min="1"
            max="120"
            step="1"
            required
            value={months}
            disabled={busy}
            onChange={(e) => {
              setMonths(e.target.value);
              setError("");
              setMessage("");
            }}
          />
        </label>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <button className="primary" disabled={busy}>
          {busy ? "Salvataggio…" : "Salva limite prenotazioni"}
        </button>
      </form>
      {message && (
        <p className="notice" role="status">
          {message}
        </p>
      )}
    </section>
  );
}
