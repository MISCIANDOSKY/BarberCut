import { useEffect, useState } from "react";
import { Modal, Empty } from "../components/UI";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";
export default function AdminServiceManagement({
  service,
  close,
  onSaved,
}: {
  service: Row;
  close: () => void;
  onSaved: () => void;
}) {
  const [rows, setRows] = useState<Row[]>([]),
    [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState("");
  useEffect(() => {
    let stopped = false;
    setRows([]);
    setLoading(true);
    setError("");
    result<Row[]>(
      supabase.rpc("admin_service_barbers", { p_service: service.id }),
    )
      .then((data) => {
        if (!stopped) setRows(data);
      })
      .catch((err) => {
        if (!stopped) setError(friendly(err));
      })
      .finally(() => {
        if (!stopped) setLoading(false);
      });
    return () => {
      stopped = true;
    };
  }, [service.id]);
  return (
    <Modal
      title="Gestisci servizio"
      wide
      close={() => {
        if (!busy) close();
      }}
    >
      <h3>{service.name}</h3>
      <p className="muted">
        Spunta i barbieri che possono offrire questo servizio. Togli la spunta
        per disattivarlo nella loro agenda: il Barbiere normale dovrà chiedere
        al titolare di riabilitarlo. Le modifiche si salvano subito e gli
        appuntamenti già presenti restano invariati.
      </p>
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
      {loading ? (
        <p role="status">Caricamento barbieri…</p>
      ) : !rows.length && !error ? (
        <Empty>Nessun barbiere attivo associato a un account.</Empty>
      ) : (
        rows.map((row) => (
          <label className="check" key={row.barber_id}>
            <input
              type="checkbox"
              checked={row.enabled}
              disabled={busy}
              onChange={async (event) => {
                if (busy) return;
                const enabled = event.currentTarget.checked;
                setBusy(true);
                setError("");
                setMessage("");
                try {
                  await result(
                    supabase.rpc("admin_set_service_barber", {
                      p_service: service.id,
                      p_barber: row.barber_id,
                      p_enabled: enabled,
                    }),
                  );
                  setRows(
                    await result<Row[]>(
                      supabase.rpc("admin_service_barbers", {
                        p_service: service.id,
                      }),
                    ),
                  );
                  setMessage(
                    enabled
                      ? "Servizio abilitato per il barbiere."
                      : "Servizio disattivato per il barbiere.",
                  );
                  onSaved();
                } catch (err) {
                  setError(friendly(err));
                } finally {
                  setBusy(false);
                }
              }}
            />
            <span>
              {row.barber_name}
              {row.enabled && !row.personally_active && (
                <small>Disattivato personalmente dal barbiere</small>
              )}
            </span>
          </label>
        ))
      )}
    </Modal>
  );
}
