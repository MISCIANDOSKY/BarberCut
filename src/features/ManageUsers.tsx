import { useEffect, useRef, useState } from "react";
import { Empty } from "../components/UI";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";

export default function ManageUsers({ isAdmin = false }: { isAdmin?: boolean }) {
  const [status, setStatus] = useState("pending");
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const version = useRef(0);
  async function load() {
    const request = ++version.current;
    setLoading(true);
    setError("");
    try {
      const data = await result<Row[]>(
        supabase.rpc("list_registration_requests", { p_status: status }),
      );
      if (request === version.current) setRows(data);
    } catch (e) {
      if (request === version.current) setError(friendly(e));
    } finally {
      if (request === version.current) setLoading(false);
    }
  }
  useEffect(() => {
    void load();
    return () => {
      version.current++;
    };
  }, [status]);
  async function review(account: Row, decision: string) {
    const name =
      [account.first_name, account.last_name].filter(Boolean).join(" ") ||
      account.email;
    if (
      !confirm(
        decision === "approved"
          ? "Approvare " +
              name +
              "? Riceverà un’email per iniziare a prenotare."
          : "Rifiutare la richiesta di " + name + "? Non potrà prenotare.",
      )
    )
      return;
    setBusy(true);
    setError("");
    setMessage("");
    try {
      await result(
        supabase.rpc("review_registration", {
          p_user: account.user_id,
          p_decision: decision,
        }),
      );
      setMessage(
        decision === "approved"
          ? "Utente approvato. Email di conferma in invio."
          : "Richiesta rifiutata.",
      );
      await load();
    } catch (e) {
      setError(friendly(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <p className="muted">
        Approva o rifiuta le richieste di iscrizione alla barberia. I clienti
        approvati possono prenotare.
        {isAdmin && " La gestione dei ruoli rimane riservata all’admin."}
      </p>
      <div
        className="registration-tabs"
        role="group"
        aria-label="Stato richieste"
      >
        {[
          ["pending", "In attesa"],
          ["approved", "Approvati"],
          ["rejected", "Rifiutati"],
        ].map(([value, label]) => (
          <button
            key={value}
            className={"secondary " + (status === value ? "selected" : "")}
            disabled={busy}
            aria-pressed={status === value}
            onClick={() => {
              setStatus(value);
              setMessage("");
            }}
          >
            {label}
          </button>
        ))}
        <button className="text" disabled={busy || loading} onClick={load}>
          Aggiorna elenco
        </button>
      </div>
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
        <p role="status">Caricamento utenti…</p>
      ) : !rows.length ? (
        <Empty>
          {status === "pending"
            ? "Non ci sono richieste in attesa."
            : "Nessun utente in questo elenco."}
        </Empty>
      ) : (
        rows.map((account) => (
          <article className="table-row" key={account.user_id}>
            <span>
              <strong>
                {account.first_name} {account.last_name}
              </strong>
              <small>{account.email}</small>
              {account.phone && <small>{account.phone}</small>}
              <small>
                Registrato il{" "}
                {new Date(account.requested_at).toLocaleDateString("it-IT", {
                  timeZone: "Europe/Rome",
                })}
              </small>
              {account.status !== "pending" && (
                <small>
                  {account.status === "approved" ? "Approvato" : "Rifiutato"}
                  {account.reviewed_by_name
                    ? " da " + account.reviewed_by_name
                    : " · Autore non disponibile"}
                </small>
              )}
              {!account.email_verified && (
                <small>
                  Email ancora da verificare: l’approvazione sarà disponibile
                  dopo la verifica.
                </small>
              )}
            </span>
            {status === "pending" && (
              <div className="registration-actions">
                <button
                  className="primary"
                  disabled={busy || !account.email_verified}
                  onClick={() => review(account, "approved")}
                >
                  Approva
                </button>
                <button
                  className="danger"
                  disabled={busy}
                  onClick={() => review(account, "rejected")}
                >
                  Rifiuta
                </button>
              </div>
            )}
          </article>
        ))
      )}
    </>
  );
}
