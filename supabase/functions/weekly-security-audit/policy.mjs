// Additional claims are checked only AFTER cryptographic JWT verification.
export function trustedWorkflow(p) {
  return p.repository === "MISCIANDOSKY/BarberUp" &&
    p.repository_id === "1421982593" &&
    p.repository_owner_id === "332405518" &&
    p.ref === "refs/heads/main" &&
    p.workflow_ref === "MISCIANDOSKY/BarberUp/.github/workflows/security-audit.yml@refs/heads/main" &&
    ["schedule", "workflow_dispatch", "push"].includes(p.event_name) &&
    p.runner_environment === "github-hosted";
}
export const CHECKS = [
  "tables_without_rls",
  "private_client_grants",
  "public_client_definers",
  "definers_without_fixed_search_path",
  "client_views_without_invoker",
  "unrestricted_sensitive_policies",
];
export function safeSnapshot(value) {
  if (value?.version !== 1 || !Number.isSafeInteger(value.tables_checked) || value.tables_checked < 1 ||
      CHECKS.some(k => !Number.isSafeInteger(value[k]) || value[k] < 0)) throw new Error("Invalid snapshot");
  return Object.fromEntries([["version", 1], ["tables_checked", value.tables_checked], ...CHECKS.map(k => [k, value[k]])]);
}
