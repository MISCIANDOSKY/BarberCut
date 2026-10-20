import { useEffect, useRef, useState } from "react";
import { Empty } from "../components/UI";
import { supabase, result, friendly } from "../lib/api";
import type { Row } from "../lib/api";
type ClientPage = { items: Row[]; has_more: boolean; letters: string[] };
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("").concat("#");

export default function ManageUsers({
  isAdmin = false,
}: {
  isAdmin?: boolean;
}) {
  const [status, setStatus] = useState(isAdmin ? "pending" : "all"),
    [rows, setRows] = useState<Row[]>([]);
  const [fromLetter, setFromLetter] = useState<string | null>(null),
    [selectedLetter, setSelectedLetter] = useState("");
  const [letters, setLetters] = useState<string[]>([]),
    [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState("");
  const version = useRef(0),
    anchors = useRef<Record<string, HTMLElement | null>>({}),
    jump = useRef<string | null>(null);
  const listStart = useRef<HTMLDivElement>(null);
  const groups = new Map<string, Row[]>();
  for (const row of rows) {
    const letter = row.letter || "#";
    if (!groups.has(letter)) groups.set(letter, []);
    groups.get(letter)!.push(row);
  }
  async function load(append = false) {
    const request = ++version.current;
    setLoading(true);
    setError("");
    try {
      const data = await result<ClientPage>(
        supabase.rpc("list_clients", {
          p_status: status,
          p_offset: append ? rows.length : 0,
          p_from_letter: fromLetter,
        }),
      );
      if (request !== version.current) return;
      setRows((old) =>
        append
          ? [
              ...old,
              ...data.items.filter(
                (item) =>
                  !old.some((current) => current.user_id === item.user_id),
              ),
            ]
          : data.items,
      );
      setHasMore(data.has_more);
      setLetters(data.letters);
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
  }, [status, fromLetter]);
  useEffect(() => {
    if (!loading && jump.current) {
      const target = anchors.current[jump.current];
      if (target) {
        target.scrollIntoView({ behavior: "smooth", block: "start" });
        jump.current = null;
      }
    }
  }, [rows, loading]);
  function goToLetter(letter: string) {
    setSelectedLetter(letter);
    const target = anchors.current[letter];
    if (target) {
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    jump.current = letter;
    setRows([]);
    setHasMore(false);
    setLoading(true);
    setFromLetter(letter);
  }
  function chooseStatus(next: string) {
    setRows([]);
    setHasMore(false);
    setLoading(true);
    setMessage("");
    setSelectedLetter("");
    jump.current = null;
    if (next === status && fromLetter === null) {
      void load();
      listStart.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    } else {
      setFromLetter(null);
      setStatus(next);
    }
  }
  async function review(account: Row, decision: string) {
    const name =
      [account.first_name, account.last_name].filter(Boolean).join(" ") ||
      account.phone ||
      "questo cliente";
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
        {isAdmin
          ? "Approva o rifiuta le richieste di iscrizione alla barberia."
          : "Visualizza tutti i clienti della barberia e gestisci le richieste di iscrizione."}{" "}
        I clienti approvati possono prenotare.
        {isAdmin && " La gestione dei ruoli rimane riservata all’admin."}
      </p>
      <div
        className="registration-tabs"
        role="group"
        aria-label="Stato clienti"
      >
        {[
          ...(!isAdmin ? [["all", "Tutti"]] : []),
          ["pending", "In attesa"],
          ...(isAdmin ? [["approved", "Approvati"]] : []),
          ["rejected", "Rifiutati"],
        ].map(([value, label]) => (
          <button
            key={value}
            className={"secondary " + (status === value ? "selected" : "")}
            disabled={busy}
            aria-pressed={status === value}
            onClick={() => chooseStatus(value)}
          >
            {label}
          </button>
        ))}
        <button
          className="text"
          disabled={busy || loading}
          onClick={() => void load()}
        >
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
      {fromLetter && (
        <button
          className="text"
          disabled={busy || loading}
          onClick={() => {
            setRows([]);
            setLoading(true);
            setSelectedLetter("");
            jump.current = null;
            setFromLetter(null);
            listStart.current?.scrollIntoView({
              behavior: "smooth",
              block: "start",
            });
          }}
        >
          Torna all’inizio dell’elenco
        </button>
      )}
      <div className="clients-directory" ref={listStart}>
        <div className="clients-records content-stack">
          {loading && !rows.length ? (
            <p role="status">Caricamento utenti…</p>
          ) : !rows.length ? (
            <Empty>
              {status === "pending"
                ? "Non ci sono richieste in attesa."
                : "Nessun cliente in questo elenco."}
            </Empty>
          ) : (
            [...groups].map(([letter, accounts]) => (
              <section
                key={letter}
                className="client-letter-group"
                ref={(element) => {
                  anchors.current[letter] = element;
                }}
              >
                <h3>{letter}</h3>
                {accounts.map((account) => (
                  <article className="table-row" key={account.user_id}>
                    <span>
                      <strong>
                        {account.first_name} {account.last_name}
                      </strong>
                      {account.phone && (
                        <small>
                          <a
                            href={
                              "tel:" +
                              String(account.phone).replace(/[^+0-9]/g, "")
                            }
                            aria-label={
                              "Chiama " +
                              account.first_name +
                              " " +
                              account.last_name +
                              " al " +
                              account.phone
                            }
                          >
                            {account.phone}
                          </a>
                        </small>
                      )}
                      <small>
                        Registrato il{" "}
                        {new Date(account.requested_at).toLocaleDateString(
                          "it-IT",
                          { timeZone: "Europe/Rome" },
                        )}
                      </small>
                      {account.status === "pending" ? (
                        <small>In attesa di approvazione</small>
                      ) : account.status === "rejected" ? (
                        <small>
                          Rifiutato
                          {account.reviewed_by_name
                            ? " da " + account.reviewed_by_name
                            : " · Autore non disponibile"}
                        </small>
                      ) : account.status === "approved" ? (
                        <small>
                          {!account.reviewed_at
                            ? "Entrato senza approvazione"
                            : "Approvato" +
                              (account.reviewed_by_name
                                ? " da " + account.reviewed_by_name
                                : " · Autore non disponibile")}
                        </small>
                      ) : null}
                      {!account.email_verified && (
                        <small>
                          Email ancora da verificare: l’approvazione sarà
                          disponibile dopo la verifica.
                        </small>
                      )}
                    </span>
                    {account.status === "pending" && (
                      <div className="registration-actions">
                        <button
                          className="primary"
                          disabled={busy || loading || !account.email_verified}
                          onClick={() => void review(account, "approved")}
                        >
                          Approva
                        </button>
                        <button
                          className="danger"
                          disabled={busy || loading}
                          onClick={() => void review(account, "rejected")}
                        >
                          Rifiuta
                        </button>
                      </div>
                    )}
                  </article>
                ))}
              </section>
            ))
          )}
          {hasMore && (
            <button
              className="secondary"
              disabled={busy || loading}
              onClick={() => void load(true)}
            >
              {loading ? "Caricamento…" : "Carica altri clienti"}
            </button>
          )}
        </div>
        <nav
          className="clients-alphabet"
          aria-label="Indice alfabetico dei clienti"
        >
          {alphabet.map((letter) => (
            <button
              type="button"
              key={letter}
              className={selectedLetter === letter ? "selected" : ""}
              aria-label={
                letter === "#"
                  ? "Vai ai nomi con numeri o altri caratteri"
                  : "Vai alla lettera " + letter
              }
              aria-pressed={selectedLetter === letter}
              disabled={busy || loading || !letters.includes(letter)}
              onClick={() => goToLetter(letter)}
            >
              {letter}
            </button>
          ))}
        </nav>
      </div>
    </>
  );
}
