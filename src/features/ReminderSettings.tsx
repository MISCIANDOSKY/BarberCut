import { useEffect, useState } from "react";
import { AppSelect } from "../components/AppSelect";
import { supabase, result } from "../lib/api";
const standard = [
  { minutes: 2880, label: "48 ore prima" },
  { minutes: 1440, label: "24 ore prima" },
  { minutes: 60, label: "1 ora prima" },
  { minutes: 15, label: "15 minuti prima" },
];
function customLabel(minutes: number) {
  if (minutes % 1440 === 0) {
    const n = minutes / 1440;
    return n + (n === 1 ? " giorno prima" : " giorni prima");
  }
  const n = minutes / 60;
  return n + (n === 1 ? " ora prima" : " ore prima");
}
export default function ReminderSettings({ userId }: { userId: string }) {
  const [offsets, setOffsets] = useState<number[] | null>(null),
    [amount, setAmount] = useState(2),
    [unit, setUnit] = useState("hours");
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState("");
  useEffect(() => {
    let stopped = false;
    void result<{ offsets: number[] }>(supabase.rpc("reminder_settings"))
      .then((data) => {
        if (!stopped) setOffsets(data.offsets);
      })
      .catch(() => {
        if (!stopped)
          setError(
            "Non riesco a leggere i promemoria. Riapri questa schermata quando sei online.",
          );
      });
    return () => {
      stopped = true;
    };
  }, [userId]);
  const custom = (offsets || [])
    .filter((minutes) => !standard.some((s) => s.minutes === minutes))
    .sort((a, b) => a - b);
  async function save(next: number[]) {
    if (busy || !offsets) return;
    const cleaned = [...new Set(next)].sort((a, b) => a - b);
    setBusy(true);
    setError("");
    setMessage("");
    try {
      await result(
        supabase.rpc("save_reminder_settings", { p_offsets: cleaned }),
      );
      setOffsets(cleaned);
      setMessage("Preferenze promemoria salvate.");
    } catch {
      setError(
        "Non riesco a salvare i promemoria. Riprova fra qualche minuto.",
      );
    } finally {
      setBusy(false);
    }
  }
  const minutes = amount * (unit === "days" ? 1440 : 60);
  return (
    <section className="reminder-settings content-stack">
      <h3>Quando ricevere i promemoria</h3>
      <p className="muted">
        Scegli quali anticipi attivare. Le scelte valgono nel quadrifoglio e
        anche per le push, quando consentite dal dispositivo.
      </p>
      {!offsets && !error && <p role="status">Caricamento promemoria…</p>}
      <div className="reminder-standard">
        {standard.map((item) => (
          <label className="check" key={item.minutes}>
            <input
              type="checkbox"
              checked={!!offsets?.includes(item.minutes)}
              disabled={!offsets || busy}
              onChange={(e) =>
                void save(
                  e.target.checked
                    ? [...offsets!, item.minutes]
                    : offsets!.filter((n) => n !== item.minutes),
                )
              }
            />
            {item.label}
          </label>
        ))}
      </div>
      <h3>Promemoria personalizzati</h3>
      {custom.map((value) => (
        <div className="reminder-custom-row" key={value}>
          <span>{customLabel(value)}</span>
          <button
            type="button"
            className="text danger-text"
            disabled={busy}
            aria-label={"Elimina promemoria " + customLabel(value)}
            onClick={() => void save(offsets!.filter((n) => n !== value))}
          >
            Elimina
          </button>
        </div>
      ))}
      <div className="two">
        <label>
          Quanto prima
          <input
            type="number"
            inputMode="numeric"
            min="1"
            max={unit === "days" ? 365 : 8760}
            step="1"
            value={amount || ""}
            disabled={busy || !offsets}
            onChange={(e) => setAmount(Number(e.target.value))}
          />
        </label>
        <label>
          Unità
          <AppSelect
            value={unit}
            disabled={busy || !offsets}
            onChange={(e) => setUnit(e.target.value)}
          >
            <option value="hours">Ore prima</option>
            <option value="days">Giorni prima</option>
          </AppSelect>
        </label>
      </div>
      <button
        type="button"
        className="secondary"
        disabled={
          busy ||
          !offsets ||
          !Number.isInteger(amount) ||
          amount < 1 ||
          minutes > 525600 ||
          custom.length >= 12 ||
          !navigator.onLine
        }
        onClick={() => {
          if (offsets!.includes(minutes)) {
            setError("Questo promemoria è già attivo.");
            return;
          }
          void save([...offsets!, minutes]);
        }}
      >
        Aggiungi promemoria personalizzato
      </button>
      {custom.length >= 12 && (
        <p className="muted">
          Hai raggiunto il limite di 12 promemoria personalizzati. Elimina una
          voce per aggiungerne un’altra.
        </p>
      )}
      {offsets?.length === 0 && (
        <p className="notice">
          Tutti i promemoria degli appuntamenti sono disattivati.
        </p>
      )}
      {busy && <p role="status">Salvataggio…</p>}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {message && (
        <p className="notice" role="status">
          {message}
        </p>
      )}
    </section>
  );
}
