import { useEffect, useState } from "react";
import { Empty } from "../components/UI";
import { supabase, result, dateLabel } from "../lib/api";
import type { Row } from "../lib/api";

export default function ProfileTerms({
  userId,
  refresh,
}: {
  userId: string;
  refresh: () => void;
}) {
  const [versions, setVersions] = useState<Row[]>([]),
    [acceptances, setAcceptances] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(""),
    [error, setError] = useState("");
  useEffect(() => {
    let stopped = false;
    const load = async () => {
      setLoading(true);
      try {
        const own = await result<Row[]>(
          supabase
            .from("terms_acceptances")
            .select("terms_id,accepted_at")
            .eq("user_id", userId),
        );
        const ids = own.map((a) => a.terms_id);
        const [current, previous] = await Promise.all([
          result<Row[]>(
            supabase.from("terms_versions").select("*").eq("published", true),
          ),
          ids.length
            ? result<Row[]>(
                supabase.from("terms_versions").select("*").in("id", ids),
              )
            : Promise.resolve([] as Row[]),
        ]);
        if (stopped) return;
        setAcceptances(own);
        setVersions(
          [
            ...new Map(
              [...current, ...previous].map((v) => [v.id, v]),
            ).values(),
          ].sort(
            (a, b) =>
              Number(b.published) - Number(a.published) ||
              Date.parse(b.created_at) - Date.parse(a.created_at),
          ),
        );
        setError("");
      } catch {
        if (!stopped)
          setError(
            "Non riesco a caricare i termini. Riprova quando sei online.",
          );
      } finally {
        if (!stopped) setLoading(false);
      }
    };
    void load();
    return () => {
      stopped = true;
    };
  }, [userId]);
  async function accept(version: Row) {
    if (busy) return;
    setBusy(version.id);
    setError("");
    try {
      const { error } = await supabase
        .from("terms_acceptances")
        .insert({ user_id: userId, terms_id: version.id });
      if (error && error.code !== "23505") throw error;
      const own = await result<Row[]>(
        supabase
          .from("terms_acceptances")
          .select("terms_id,accepted_at")
          .eq("user_id", userId),
      );
      setAcceptances(own);
      refresh();
    } catch {
      setError(
        "Accettazione non riuscita. I termini potrebbero essere stati aggiornati: riapri questa schermata e riprova.",
      );
    } finally {
      setBusy("");
    }
  }
  return (
    <>
      <p>
        Qui trovi i termini attuali della barberia e le versioni che hai già
        accettato.
      </p>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {loading ? (
        <p role="status">Caricamento termini…</p>
      ) : !versions.length ? (
        <Empty>
          La barberia non ha ancora pubblicato termini e condizioni. Non
          risultano testi già accettati dal tuo account.
        </Empty>
      ) : (
        versions.map((version) => {
          const acceptance = acceptances.find((a) => a.terms_id === version.id);
          return (
            <section
              key={version.id}
              className="profile-terms-version content-stack"
            >
              <h3>
                {version.published
                  ? "Termini attuali"
                  : "Termini già accettati"}{" "}
                · {version.version}
              </h3>
              {acceptance ? (
                <p className="notice">
                  Accettati il {dateLabel(acceptance.accepted_at)}.
                </p>
              ) : (
                <p className="notice">
                  Questa versione non è ancora stata accettata.
                </p>
              )}
              <p className="legal">{version.body}</p>
              {version.published && !acceptance && (
                <button
                  type="button"
                  className="primary"
                  disabled={!!busy || !navigator.onLine}
                  onClick={() => void accept(version)}
                >
                  {busy === version.id
                    ? "Salvataggio…"
                    : "Ho letto e accetto i termini e condizioni"}
                </button>
              )}
            </section>
          );
        })
      )}
    </>
  );
}
