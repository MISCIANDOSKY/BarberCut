import { useCallback, useEffect, useRef, useState } from "react";
import { supabase, result } from "./api";
import type { Row } from "./api";
import { createLatestRequest } from "./latestRequest.mjs";
type ConsentStatus = { terms: Row | null; accepted: boolean };
type Snapshot = ConsentStatus & {
  owner: string | null;
  ready: boolean;
  error: string;
};
export function useTermsConsent(userId: string | null) {
  const [snapshot, setSnapshot] = useState<Snapshot>({
    owner: null,
    terms: null,
    accepted: false,
    ready: false,
    error: "",
  });
  const reloadRef = useRef<() => Promise<void>>(async () => {});
  const reload = useCallback(() => reloadRef.current(), []);
  useEffect(() => {
    if (!userId) {
      setSnapshot({
        owner: null,
        terms: null,
        accepted: false,
        ready: false,
        error: "",
      });
      return;
    }
    const request = createLatestRequest<ConsentStatus>({
      load: () => result(supabase.rpc("current_terms_status")),
      onData: (value) =>
        setSnapshot({
          owner: userId,
          terms: value.terms,
          accepted: value.accepted,
          ready: true,
          error: "",
        }),
      onError: () =>
        setSnapshot((previous) =>
          previous.owner === userId
            ? {
                ...previous,
                error:
                  "Non riesco a verificare i termini. Collegati a internet e riprova.",
              }
            : {
                owner: userId,
                terms: null,
                accepted: false,
                ready: false,
                error:
                  "Non riesco a verificare i termini. Collegati a internet e riprova.",
              },
        ),
    });
    reloadRef.current = request.refresh;
    const update = () => {
      if (!document.hidden && navigator.onLine) void request.refresh();
    };
    void request.refresh();
    const channel = supabase
      .channel("published-terms-" + userId)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "terms_versions" },
        update,
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") update();
      });
    const timer = window.setInterval(update, 30000);
    window.addEventListener("focus", update);
    window.addEventListener("online", update);
    document.addEventListener("visibilitychange", update);
    return () => {
      request.stop();
      reloadRef.current = async () => {};
      window.clearInterval(timer);
      window.removeEventListener("focus", update);
      window.removeEventListener("online", update);
      document.removeEventListener("visibilitychange", update);
      void supabase.removeChannel(channel);
    };
  }, [userId]);
  const sameAccount = snapshot.owner === userId;
  return {
    ready: sameAccount && snapshot.ready,
    terms: sameAccount ? snapshot.terms : null,
    accepted: sameAccount && snapshot.accepted,
    error: sameAccount ? snapshot.error : "",
    reload,
  };
}
