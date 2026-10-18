import { useState } from "react";
import { supabase, result, friendly } from "../lib/api";

export default function HireBarber({
  refresh,
  notify,
}: {
  refresh: () => void;
  notify: (message: string) => void;
}) {
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [name, setName] = useState("");
  const [matched, setMatched] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  function reset() {
    setEmail("");
    setPhone("");
    setName("");
    setMatched(false);
    setError("");
  }
  return (
    <>
      <p>
        Prima di procedere, assicurati che il nuovo collaboratore sia già
        registrato a BarberCut come cliente. Inserisci l’email e il numero di
        telefono presenti nel suo profilo.
      </p>
      <form
        onSubmit={async (event) => {
          event.preventDefault();
          if (busy) return;
          setBusy(true);
          setError("");
          try {
            if (!matched) {
              await result(
                supabase.rpc("check_barber_hire_candidate", {
                  p_email: email.trim(),
                  p_phone: phone.trim(),
                }),
              );
              setMatched(true);
            } else {
              await result(
                supabase.rpc("hire_barber", {
                  p_email: email.trim(),
                  p_phone: phone.trim(),
                  p_name: name.trim(),
                }),
              );
              reset();
              notify(
                "Barbiere aggiunto. Il ruolo Barbiere e i servizi sono stati assegnati automaticamente.",
              );
              refresh();
            }
          } catch (err) {
            setError(friendly(err));
            if (matched) setMatched(false);
          } finally {
            setBusy(false);
          }
        }}
      >
        <label>
          Email del collaboratore
          <input
            type="email"
            autoComplete="off"
            required
            maxLength={320}
            value={email}
            disabled={busy || matched}
            onChange={(event) => {
              setEmail(event.target.value);
              setError("");
            }}
          />
        </label>
        <label>
          Numero di telefono
          <input
            type="tel"
            autoComplete="off"
            required
            maxLength={40}
            value={phone}
            disabled={busy || matched}
            onChange={(event) => {
              setPhone(event.target.value);
              setError("");
            }}
          />
        </label>
        {matched && (
          <>
            <p className="notice">
              Email e telefono corrispondono allo stesso account disponibile.
              Ora scegli il nome da mostrare in agenda.
            </p>
            <label>
              Nome da mostrare in agenda
              <input
                required
                maxLength={160}
                autoFocus
                value={name}
                disabled={busy}
                onChange={(event) => setName(event.target.value)}
              />
            </label>
            <p className="muted">
              Il nuovo collaboratore riceverà il ruolo Barbiere e i servizi
              attivi già presenti. Potrà disattivare o riattivare i servizi per
              la propria agenda. Solo l’admin può assegnare il ruolo Barbiere
              Admin.
            </p>
          </>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <button
          className="primary"
          disabled={busy || (matched && !name.trim())}
        >
          {busy
            ? "Attendi…"
            : matched
              ? "Conferma assunzione"
              : "Verifica email e telefono"}
        </button>
        {matched && (
          <button
            type="button"
            className="text"
            disabled={busy}
            onClick={() => {
              setMatched(false);
              setName("");
              setError("");
            }}
          >
            Modifica email o telefono
          </button>
        )}
      </form>
    </>
  );
}
