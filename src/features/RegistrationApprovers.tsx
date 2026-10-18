import { useEffect, useState } from "react";
import { Empty, Modal } from "../components/UI";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";

export default function RegistrationApprovers({
  close, refresh,
}: { close: () => void; refresh: () => void }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  useEffect(() => {
    let stopped = false;
    result<Row[]>(supabase.rpc("list_registration_approvers"))
      .then((data) => { if (!stopped) setRows(data); })
      .catch((err) => { if (!stopped) setError(friendly(err)); })
      .finally(() => { if (!stopped) setLoading(false); });
    return () => { stopped = true; };
  }, []);
  return (
    <Modal wide title="Chi può approvare i nuovi utenti" close={() => { if (!busy) close(); }}>
      <p className="muted">
        Abilita i barbieri che possono approvare o rifiutare le iscrizioni.
        Soltanto chi ha la spunta vedrà Gestisci utenti. I nuovi barbieri
        vengono aggiunti senza questo permesso. Le modifiche si salvano subito.
      </p>
      {error && <p className="form-error" role="alert">{error}</p>}
      {message && <p className="notice" role="status">{message}</p>}
      {loading ? <p role="status">Caricamento barbieri…</p> :
        !rows.length && !error ? <Empty>Nessun barbiere attivo associato a un account.</Empty> :
        rows.map((barber) => (
          <label className="check" key={barber.barber_id}>
            <input type="checkbox" checked={barber.can_approve} disabled={busy}
              onChange={async (event) => {
                const enabled = event.currentTarget.checked;
                setBusy(true);
                setError("");
                setMessage("");
                try {
                  await result(supabase.rpc("set_registration_approver", {
                    p_barber: barber.barber_id, p_enabled: enabled,
                  }));
                  setRows((current) => current.map((row) =>
                    row.barber_id === barber.barber_id ? { ...row, can_approve: enabled } : row));
                  setMessage(enabled ? "Permesso di approvazione abilitato." : "Permesso di approvazione rimosso.");
                  refresh();
                } catch (err) {
                  setError(friendly(err));
                } finally {
                  setBusy(false);
                }
              }} />
            <span>
              <strong>{barber.account_name || barber.barber_name}</strong>
              <small>Agenda: {barber.barber_name}</small>
            </span>
          </label>
        ))
      }
    </Modal>
  );
}
