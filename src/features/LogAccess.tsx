import { useEffect, useState } from "react";
import { Modal, Empty } from "../components/UI";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";
const roles: Record<string, string> = { admin: "Admin", barber: "Barbiere", barber_admin: "Barbiere Admin", shop: "Barberia" };
export default function LogAccess({ refresh }: { refresh: () => void }) {
  const [open, setOpen] = useState(false);
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState<string | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    if (!open) return;
    let stopped = false;
    setLoading(true); setError(""); setRows([]);
    result<Row[]>(supabase.rpc("appointment_log_access_users"))
      .then(data => { if (!stopped) setRows(data); })
      .catch(e => { if (!stopped) setError(friendly(e)); })
      .finally(() => { if (!stopped) setLoading(false); });
    return () => { stopped = true; };
  }, [open]);
  return <section className="content-stack">
    <h3>Accesso ai log</h3>
    <p className="muted">Scegli quali account dello staff possono consultare lo storico delle operazioni sulle agende. I clienti sono esclusi. L’Admin mantiene sempre l’accesso.</p>
    <button type="button" className="secondary" onClick={() => setOpen(true)}>Gestisci accesso ai log</button>
    {open && <Modal wide title="Accesso ai log" close={() => { if (!saving) setOpen(false); }}>
      <p className="muted">La spunta abilita il tasto Log e la consultazione di tutte le agende della barberia. Ogni modifica viene salvata subito.</p>
      {error && <p className="form-error" role="alert">{error}</p>}
      {loading && <Empty>Caricamento account…</Empty>}
      {rows.map(account => <label className="check log-access-choice" key={account.user_id}>
        <input type="checkbox" checked={account.enabled} disabled={saving !== null || account.role === "admin"} onChange={async event => {
          const enabled = event.target.checked;
          setSaving(account.user_id); setError("");
          try {
            await result(supabase.rpc("set_appointment_log_access", { p_user: account.user_id, p_enabled: enabled }));
            setRows(previous => previous.map(row => row.user_id === account.user_id ? { ...row, enabled } : row));
            refresh();
          } catch (e) { setError(friendly(e)); }
          finally { setSaving(null); }
        }} />
        <span>{account.first_name || "Account"} {account.last_name}<small>{roles[account.role]}{account.role === "admin" ? " · Sempre abilitato" : ""}{saving === account.user_id ? " · Salvataggio…" : ""}</small></span>
      </label>)}
    </Modal>}
  </section>;
}
