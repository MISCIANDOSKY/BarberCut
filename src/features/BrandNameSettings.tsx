import { useEffect, useState } from "react";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";
import { useBrandName } from "../lib/branding";
function activationLabel(value: string) {
  return new Date(value).toLocaleString("it-IT", {
    timeZone: "Europe/Rome",
    dateStyle: "short",
    timeStyle: "medium",
  });
}
export default function BrandNameSettings() {
  const currentName = useBrandName();
  const [status, setStatus] = useState<Row | null>(null);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [feedback, setFeedback] = useState("");
  useEffect(() => {
    let stopped = false;
    void result<Row>(supabase.rpc("branding_status"))
      .then((data) => {
        if (!stopped) {
          setStatus(data);
          setName(data.pending_name || data.name);
        }
      })
      .catch((e) => {
        if (!stopped) setError(friendly(e));
      });
    return () => {
      stopped = true;
    };
  }, [currentName]);
  return (
    <section className="content-stack">
      <h3>Nome dell’app e della barberia</h3>
      <p>
        Nome attuale: <strong>{currentName}</strong>
      </p>
      <p className="muted">
        Il nuovo nome entra in vigore 15 minuti dopo il salvataggio, rispettando
        le maiuscole e minuscole inserite. Durante l’attesa resta visibile il
        nome attuale.
      </p>
      {status?.pending_name && (
        <div className="notice" role="status">
          <p>
            Nome programmato: <strong>{status.pending_name}</strong>
          </p>
          <p>
            Attivazione prevista il {activationLabel(status.activates_at)}. Una
            nuova programmazione sostituisce questa e fa ripartire i 15 minuti.
          </p>
          <button
            type="button"
            className="secondary"
            disabled={busy}
            onClick={async () => {
              setBusy(true);
              setError("");
              setFeedback("");
              try {
                const data = await result<Row>(
                  supabase.rpc("cancel_brand_name"),
                );
                setStatus(data);
                setName(data.name);
                setFeedback("Cambio nome annullato.");
              } catch (e) {
                setError(friendly(e));
              } finally {
                setBusy(false);
              }
            }}
          >
            Annulla cambio nome
          </button>
        </div>
      )}
      {status?.setup_required && (
        <p className="notice" role="status">
          Per attivare il cambio nome completo manca il collegamento protetto
          alle impostazioni del mittente email. Il nome attuale resta invariato.
        </p>
      )}
      {status?.sync_error && (
        <p className="form-error" role="alert">
          La sincronizzazione non è riuscita. Il nome attuale è rimasto
          invariato; il sistema riproverà automaticamente.
        </p>
      )}
      <form
        onSubmit={async (event) => {
          event.preventDefault();
          if (busy) return;
          setBusy(true);
          setError("");
          setFeedback("");
          try {
            const data = await result<Row>(
              supabase.rpc("schedule_brand_name", { p_name: name }),
            );
            setStatus(data);
            setFeedback(
              "Cambio nome programmato. Verrà applicato il " +
                activationLabel(data.activates_at) +
                ".",
            );
          } catch (e) {
            const message = e instanceof Error ? e.message : "";
            setError(
              message.includes("INVALID_BRAND_NAME")
                ? "Inserisci un nome da 1 a 60 caratteri, senza simboli < o > o caratteri di controllo."
                : message.includes("BRAND_NAME_UNCHANGED")
                  ? "Il nome inserito è già quello attuale."
                  : friendly(e),
            );
          } finally {
            setBusy(false);
          }
        }}
      >
        <label>
          Nuovo nome
          <input
            value={name}
            onChange={(event) => setName(event.target.value)}
            maxLength={60}
            required
            autoCapitalize="off"
            autoCorrect="off"
            spellCheck={false}
            disabled={!status || busy || status.setup_required}
          />
        </label>
        <button
          className="primary"
          disabled={!status || busy || status.setup_required}
        >
          {busy ? "Salvataggio…" : "Programma cambio nome tra 15 minuti"}
        </button>
      </form>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {feedback && (
        <p className="notice" role="status">
          {feedback}
        </p>
      )}
      <p className="muted">
        Sui dispositivi offline o con l’app sospesa l’aggiornamento compare alla
        riconnessione o riapertura. Il nome delle installazioni già presenti
        dipende dai tempi del sistema operativo. Indirizzo del sito e icona non
        cambiano.
      </p>
    </section>
  );
}
