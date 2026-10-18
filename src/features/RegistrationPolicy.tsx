import { useEffect, useState } from "react";
import { supabase, result, friendly } from "../lib/api";

export default function RegistrationPolicy({
  required,
  refresh,
}: {
  required: boolean;
  refresh: () => void;
}) {
  const [value, setValue] = useState(required);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  useEffect(() => {
    setValue(required);
  }, [required]);
  return (
    <section className="shop-address-editor content-stack">
      <h3>Iscrizione nuovi clienti</h3>
      <p className="muted">
        Scegli come accogliere i nuovi iscritti. La scelta vale per tutta la
        barberia ed è condivisa con l’admin.
      </p>
      <form
        onSubmit={async (event) => {
          event.preventDefault();
          if (busy) return;
          setBusy(true);
          setError("");
          setMessage("");
          try {
            await result(
              supabase.rpc("set_registration_policy", { p_required: value }),
            );
            setMessage("Modalità di iscrizione salvata.");
            refresh();
          } catch (e) {
            setError(friendly(e));
          } finally {
            setBusy(false);
          }
        }}
      >
        <RegistrationChoice
          required={value}
          disabled={busy}
          onChange={(next) => {
            setValue(next);
            setMessage("");
            setError("");
          }}
        />
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <button className="primary" disabled={busy}>
          {busy ? "Salvataggio…" : "Salva modalità di iscrizione"}
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

export function RegistrationChoice({
  required,
  disabled,
  onChange,
}: {
  required: boolean;
  disabled?: boolean;
  onChange: (required: boolean) => void;
}) {
  return (
    <>
      <label className="check">
        <input
          type="checkbox"
          checked={!required}
          disabled={disabled}
          onChange={(event) => onChange(!event.target.checked)}
        />
        Accetta i nuovi clienti senza approvazione
      </label>
      <p className="muted">
        Spunta attiva: i nuovi clienti sono accettati automaticamente dopo la
        verifica email. Spunta disattiva: devono essere approvati da Gestisci
        utenti. La scelta vale per tutta la barberia; gli utenti già in attesa
        mantengono il proprio stato.
      </p>
    </>
  );
}
