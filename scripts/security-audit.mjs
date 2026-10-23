import { appendFileSync, readFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import {
  safeSnapshot,
  CHECKS,
} from "../supabase/functions/weekly-security-audit/policy.mjs";

export const endpoint =
  "https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/weekly-security-audit";
export function summarizeAudit(value) {
  if (!value?.metadata?.vulnerabilities || value.error)
    throw new Error("Audit dipendenze incompleto");
  const counts = value.metadata.vulnerabilities;
  const names = ["low", "moderate", "high", "critical"];
  if (names.some((k) => !Number.isSafeInteger(counts[k]) || counts[k] < 0))
    throw new Error("Audit dipendenze non valido");
  return names.map((k) => [k, counts[k]]);
}
export async function databaseSnapshot(fetcher = fetch, env = process.env) {
  if (!env.ACTIONS_ID_TOKEN_REQUEST_URL || !env.ACTIONS_ID_TOKEN_REQUEST_TOKEN)
    throw new Error("Identità GitHub non disponibile");
  const url = new URL(env.ACTIONS_ID_TOKEN_REQUEST_URL);
  url.searchParams.set("audience", "barberup-weekly-security");
  const identity = await fetcher(url, {
    headers: { Authorization: "Bearer " + env.ACTIONS_ID_TOKEN_REQUEST_TOKEN },
    signal: AbortSignal.timeout(20000),
  });
  if (!identity.ok) throw new Error("Identità GitHub non disponibile");
  const token = (await identity.json()).value;
  if (typeof token !== "string" || !token)
    throw new Error("Identità GitHub non valida");
  const r = await fetcher(endpoint, {
    method: "POST",
    headers: { Authorization: "Bearer " + token },
    signal: AbortSignal.timeout(25000),
  });
  if (!r.ok) throw new Error("Controllo Supabase incompleto");
  return safeSnapshot(await r.json());
}
async function main() {
  const rows = [
    "# Controllo sicurezza BarberUp",
    "",
    new Date().toISOString(),
    "",
  ];
  let failed = false;
  const add = (s) => rows.push(s);
  // Never print raw subprocess output, raw scanner JSON, tokens or HTTP bodies.
  const leak = spawnSync(
    process.env.RUNNER_TEMP + "/gitleaks",
    [
      "git",
      "--redact",
      "--no-banner",
      "--exit-code",
      "2",
      "--report-format",
      "json",
      "--report-path",
      process.env.RUNNER_TEMP + "/security-leaks.json",
      "--log-opts=--all",
      ".",
    ],
    { encoding: "utf8", maxBuffer: 10 * 1024 * 1024, timeout: 180000 },
  );
  const report = process.env.RUNNER_TEMP + "/security-leaks.json";
  if ([0, 2].includes(leak.status) && existsSync(report)) {
    try {
      const findings = JSON.parse(readFileSync(report, "utf8"));
      if (
        !Array.isArray(findings) ||
        (leak.status === 2 && !findings.length) ||
        (leak.status === 0 && findings.length)
      )
        throw new Error();
      add(
        "- Credenziali potenzialmente esposte nella cronologia: " +
          findings.length +
          ".",
      );
      if (findings.length) {
        failed = true;
        console.log("Posizioni tecniche da verificare (nessun valore):", JSON.stringify(findings.map(f => ({rule: /^[a-z0-9-]{1,80}$/.test(f.RuleID) ? f.RuleID : "other", file: /^(src|scripts|tests|supabase|\\.github)\\/[a-zA-Z0-9_./-]+$/.test(f.File) ? f.File : "other", line: Number.isSafeInteger(f.StartLine) ? f.StartLine : 0, commit: /^[a-f0-9]{40}$/.test(f.Commit) ? f.Commit : "unknown"}))));
        add(
          "  Occorre una revisione riservata; eventuali credenziali reali vanno revocate o ruotate. Dettagli e valori esclusi dai log pubblici.",
        );
      }
    } catch {
      failed = true;
      add("- Scansione credenziali: INCOMPLETA.");
    }
  } else {
    failed = true;
    add("- Scansione credenziali: INCOMPLETA.");
  }
  const audit = spawnSync(
    "npm",
    ["audit", "--package-lock-only", "--json", "--ignore-scripts"],
    { encoding: "utf8", maxBuffer: 10 * 1024 * 1024, timeout: 120000 },
  );
  try {
    if (![0, 1].includes(audit.status)) throw new Error();
    const auditResult = JSON.parse(audit.stdout);
    const counts = summarizeAudit(auditResult);
    console.log("Pacchetti segnalati:", JSON.stringify(Object.entries(auditResult.vulnerabilities || {}).map(([name, v]) => ({name: /^[@a-zA-Z0-9_./-]+$/.test(name) ? name : "other", advisories: (v.via || []).filter(x => typeof x === "object").map(x => { const id = String(x.url).split("/").at(-1); return /^GHSA-[a-z0-9-]+$/.test(id) ? id : "review"; })}))));
    add(
      "- Vulnerabilità dipendenze (incluse quelle di sviluppo): " +
        counts.map(([k, n]) => k + " " + n).join(", ") +
        ".",
    );
    if (counts.some(([, n]) => n > 0)) failed = true;
  } catch {
    failed = true;
    add("- Controllo dipendenze: INCOMPLETO.");
  }
  try {
    const snapshot = await databaseSnapshot();
    add("- Tabelle Supabase controllate: " + snapshot.tables_checked + ".");
    for (const key of CHECKS) {
      add("  - " + key + ": " + snapshot[key] + ".");
      if (snapshot[key] > 0) failed = true;
    }
  } catch {
    failed = true;
    add(
      "- Controllo Supabase: INCOMPLETO (autenticazione, rete o risposta non verificata).",
    );
  }
  // Verify that the audit endpoint itself rejects anonymous and forged requests.
  for (const token of ["", "invalid.signature.token"]) {
    try {
      const r = await fetch(endpoint, {
        method: "POST",
        headers: token ? { Authorization: "Bearer " + token } : {},
        signal: AbortSignal.timeout(20000),
      });
      if (r.status !== 401) throw new Error();
    } catch {
      failed = true;
      add("- Protezione endpoint audit: verifica NEGATIVA o INCOMPLETA.");
    }
  }
  add("");
  add(
    failed
      ? "**ATTENZIONE: rilievi o verifiche incomplete; aprire questa esecuzione.**"
      : "**Nessuna anomalia rilevata nei controlli automatici eseguiti.**",
  );
  add("");
  add(
    "Ambito: scansione Gitleaks della cronologia Git raggiungibile; npm audit del lockfile; controlli aggregati RLS, grant privati, funzioni privilegiate pubbliche, search_path, viste e policy palesemente permissive. Nessun dato o account cliente modificato.",
  );
  add(
    "Limiti: non è una certificazione né una verifica completa di ogni autorizzazione applicativa. MFA, SMTP, impostazioni Auth/rate limit, advisor completi, Storage e autorizzazioni di tutte le Edge Functions richiedono una revisione aggiuntiva. La protezione password compromesse risultava disattivata alla configurazione iniziale; non è verificata da questo job.",
  );
  add(
    "GitHub può ritardare le esecuzioni o disattivare la pianificazione dopo 60 giorni senza attività. Gli avvisi dipendono dalle preferenze personali GitHub Actions: https://github.com/settings/notifications .",
  );
  const text = rows.join("\n") + "\n";
  if (process.env.GITHUB_STEP_SUMMARY)
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, text);
  console.log(text);
  if (failed) process.exitCode = 1;
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  main().catch(() => {
    console.error(
      "Controllo sicurezza incompleto. Nessun dettaglio sensibile pubblicato.",
    );
    process.exitCode = 1;
  });
}
