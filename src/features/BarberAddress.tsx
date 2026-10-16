import { useEffect, useState } from "react";
import { supabase, result } from "../lib/api";
import type { Row } from "../lib/api";

export default function BarberAddress({ address, revision, refresh }: { address: string; revision: number; refresh: () => void }) {
  const [value, setValue] = useState(address);
  const [current, setCurrent] = useState({ address, revision });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  useEffect(() => {
    setValue(address);
    setCurrent({ address, revision });
  }, [address, revision]);
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const cleaned = value.trim();
    setError(""); setMessage("");
    if (cleaned === current.address) { setMessage("L’indirizzo è già aggiornato."); return; }
    const confirmed = current.revision > 0;
    if (confirmed && !confirm("Sei sicuro che vuoi modificare l’indirizzo della barberia?")) return;
    setBusy(true);
    try {
      const saved = await result<Row>(supabase.rpc("update_shop_address", { p_address: cleaned, p_expected_revision: current.revision, p_confirm: confirmed }));
      setCurrent({ address: saved.address, revision: saved.revision });
      setValue(saved.address);
      setMessage("Indirizzo della barberia salvato.");
      refresh();
    } catch (e) {
      const code = e instanceof Error ? e.message : String(e);
      if (code.includes("ADDRESS_CHANGED")) {
        setError("L’indirizzo è stato aggiornato da un altro account. Controlla quello aggiornato e riprova.");
        refresh();
      } else if (code.includes("ACCESS_DENIED")) {
        setError("Solo l’admin e il barbiere con un’agenda attiva associata possono modificare l’indirizzo.");
      } else if (code.includes("INVALID_ADDRESS")) {
        setError("Inserisci un indirizzo completo, tra 3 e 500 caratteri.");
      } else {
        setError("Non riesco a salvare l’indirizzo. Riprova.");
      }
    } finally { setBusy(false); }
  }
  return <section className="shop-address-editor">
    <h3>Indirizzo della barberia</h3>
    <p className="muted">L’indirizzo è condiviso con i clienti nella sezione Informazioni. Dopo il primo salvataggio, ogni modifica richiede conferma.</p>
    <form onSubmit={save}>
      <label>Indirizzo completo<textarea required minLength={3} maxLength={500} rows={3} value={value} disabled={busy} onChange={(event) => { setValue(event.target.value); setMessage(""); setError(""); }} /></label>
      {error && <p className="form-error" role="alert">{error}</p>}
      <button className="primary" disabled={busy}>{busy ? "Salvataggio…" : "Salva indirizzo"}</button>
    </form>
    {message && <p className="notice" role="status">{message}</p>}
  </section>;
}
