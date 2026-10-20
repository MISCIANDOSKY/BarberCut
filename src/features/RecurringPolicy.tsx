import { useEffect, useState } from "react";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";
export default function RecurringPolicy({
  settings,
  refresh,
}: {
  settings: Row;
  refresh: () => void;
}) {
  const [maximum, setMaximum] = useState(String(settings.recurring_max ?? 5));
  const [unlimited, setUnlimited] = useState(!!settings.recurring_unlimited);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState("");
  useEffect(() => {
    setMaximum(String(settings.recurring_max ?? 5));
    setUnlimited(!!settings.recurring_unlimited);
  }, [settings.recurring_max, settings.recurring_unlimited]);
  return (
    <section className="shop-address-editor content-stack">
      <h3>Prenotazioni periodiche</h3>
      <p className="muted">
        Imposta quanti appuntamenti periodici futuri può avere ogni cliente,
        oltre alla prima prenotazione. Le ricorrenze non hanno un limite di
        data. La scelta è condivisa tra admin e Barbiere Admin.
      </p>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (busy) return;
          setBusy(true);
          setError("");
          setMessage("");
          try {
            await result(
              supabase.rpc("set_recurring_policy", {
                p_max: Number(maximum),
                p_unlimited: unlimited,
              }),
            );
            setMessage("Impostazioni delle prenotazioni periodiche salvate.");
            refresh();
          } catch (err) {
            setError(friendly(err));
          } finally {
            setBusy(false);
          }
        }}
      >
        {!unlimited && (
          <label>
            Numero massimo di appuntamenti periodici futuri
            <input
              type="number"
              min="0"
              step="1"
              value={maximum}
              disabled={busy}
              required
              onChange={(e) => setMaximum(e.target.value)}
            />
          </label>
        )}
        <label className="check">
          <input
            type="checkbox"
            checked={unlimited}
            disabled={busy}
            onChange={(e) => setUnlimited(e.target.checked)}
          />
          Prenotazioni periodiche senza limite di numero
        </label>
        <p className="muted">
          Ogni pianificazione richiede comunque un numero di ripetizioni: non
          vengono aggiunti nuovi appuntamenti all’infinito.
          {!unlimited && " Con limite 0 le nuove ricorrenze sono disabilitate."}
        </p>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <button className="primary" disabled={busy}>
          {busy ? "Salvataggio…" : "Salva prenotazioni periodiche"}
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
