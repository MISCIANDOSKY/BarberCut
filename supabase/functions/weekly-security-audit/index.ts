import { createRemoteJWKSet, jwtVerify } from "jsr:@panva/jose@6.2.13";
import { trustedWorkflow, safeSnapshot } from "./policy.mjs";

const keys = createRemoteJWKSet(new URL("https://token.actions.githubusercontent.com/.well-known/jwks"), {timeoutDuration:5000, cooldownDuration:30000});
const headers = {"Content-Type":"application/json", "Cache-Control":"no-store"};
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response('{"error":"METHOD_NOT_ALLOWED"}', {status:405, headers});
  const token = req.headers.get("Authorization")?.match(/^Bearer ([A-Za-z0-9_.-]+)$/)?.[1];
  if (!token || token.length > 16000) return new Response('{"error":"UNAUTHORIZED"}', {status:401, headers});
  try {
    const {payload} = await jwtVerify(token, keys, {
      issuer:"https://token.actions.githubusercontent.com",
      audience:"barberup-weekly-security",
      algorithms:["RS256"],
      requiredClaims:["exp","iat","nbf","repository_id","repository_owner_id","workflow_ref"],
      maxTokenAge:"10 minutes",
      clockTolerance:5,
    });
    if (!trustedWorkflow(payload)) return new Response('{"error":"FORBIDDEN"}', {status:403, headers});
  } catch {
    return new Response('{"error":"UNAUTHORIZED"}', {status:401, headers});
  }
  try {
    // Fixed read-only RPC: no arbitrary query, customer row, request body or dynamic URL.
    const response = await fetch(Deno.env.get("SUPABASE_URL") + "/rest/v1/rpc/weekly_security_snapshot", {
      method:"POST",
      headers:{
        apikey:Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        Authorization:"Bearer " + Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        "Content-Type":"application/json",
      },
      body:"{}",
      signal:AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error("Snapshot unavailable");
    return new Response(JSON.stringify(safeSnapshot(await response.json())), {headers});
  } catch {
    return new Response('{"error":"AUDIT_UNAVAILABLE"}', {status:503, headers});
  }
});
