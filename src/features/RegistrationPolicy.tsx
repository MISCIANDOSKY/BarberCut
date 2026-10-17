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
    <section className="shop-address-editor">
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
        <label className="check">
          <input
            type="radio"
            name="registration-policy"
            checked={!value}
            disabled={busy}
            onChange={() => {
              setValue(false);
              setMessage("");
              setError("");
            }}
          />
          Accetta automaticamente i nuovi utenti
        </label>
        <label className="check">
          <input
            type="radio"
            name="registration-policy"
            checked={value}
            disabled={busy}
            onChange={() => {
              setValue(true);
              setMessage("");
              setError("");
            }}
          />
          Richiedi approvazione
        </label>
        <p className="muted">
          La verifica dell’email resta necessaria in entrambi i casi. Con
          approvazione, abilita i clienti da Gestisci utenti prima che possano
          prenotare. La scelta riguarda le nuove iscrizioni: chi è già in attesa
          deve ancora essere approvato.
        </p>
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
