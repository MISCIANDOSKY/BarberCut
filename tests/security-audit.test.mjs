import test from "node:test";
import assert from "node:assert/strict";
import { trustedWorkflow, safeSnapshot, CHECKS } from "../supabase/functions/weekly-security-audit/policy.mjs";
import { summarizeAudit, databaseSnapshot } from "../scripts/security-audit.mjs";
const trusted = {repository:"MISCIANDOSKY/BarberUp",repository_id:"1421982593",repository_owner_id:"332405518",ref:"refs/heads/main",workflow_ref:"MISCIANDOSKY/BarberUp/.github/workflows/security-audit.yml@refs/heads/main",event_name:"schedule",runner_environment:"github-hosted"};
const snapshot = {version:1,tables_checked:33,...Object.fromEntries(CHECKS.map(k=>[k,0]))};
test("OIDC policy denies forks, other repositories, owners, workflows, branches and PRs",()=>{
  assert.equal(trustedWorkflow(trusted),true);
  for (const key of Object.keys(trusted)) assert.equal(trustedWorkflow({...trusted,[key]:"untrusted"}),false,key);
  assert.equal(trustedWorkflow({...trusted,event_name:"pull_request_target"}),false);
  for(const event_name of ["push","workflow_dispatch"]) assert.equal(trustedWorkflow({...trusted,event_name}),true);
});
test("only approved aggregate integers leave the endpoint",()=>{
  assert.deepEqual(safeSnapshot({...snapshot,customer_email:"private@example.invalid",token:"hidden"}),snapshot);
  for(const value of [null,{}, {...snapshot,tables_checked:0},{...snapshot,tables_without_rls:-1},{...snapshot,public_client_definers:"0"}]) assert.throws(()=>safeSnapshot(value));
});
test("incomplete npm responses cannot report success",()=>{
  assert.throws(()=>summarizeAudit({error:{}}));
  assert.throws(()=>summarizeAudit({metadata:{vulnerabilities:{low:0}}}));
  assert.deepEqual(summarizeAudit({metadata:{vulnerabilities:{low:0,moderate:1,high:2,critical:0}}}),[["low",0],["moderate",1],["high",2],["critical",0]]);
});
test("OIDC token is scoped and never included in the report",async()=>{
  const requests=[];
  const fetcher=async(url,options)=>{
    requests.push({url:String(url),options});
    return requests.length===1?{ok:true,json:async()=>({value:"temporary-identity"})}:{ok:true,json:async()=>({...snapshot,secret:"excluded"})};
  };
  const data=await databaseSnapshot(fetcher,{ACTIONS_ID_TOKEN_REQUEST_URL:"https://example.invalid/token",ACTIONS_ID_TOKEN_REQUEST_TOKEN:"request-only"});
  assert.deepEqual(data,snapshot);
  assert.equal(new URL(requests[0].url).searchParams.get("audience"),"barberup-weekly-security");
  assert.equal(requests[1].options.headers.Authorization,"Bearer temporary-identity");
  assert.equal(JSON.stringify(data).includes("temporary-identity"),false);
});
test("missing identity and rejected backend fail closed",async()=>{
  await assert.rejects(databaseSnapshot(async()=>{throw Error("must not call")},{}));
  await assert.rejects(databaseSnapshot(async()=>({ok:false}),{ACTIONS_ID_TOKEN_REQUEST_URL:"https://example.invalid/token",ACTIONS_ID_TOKEN_REQUEST_TOKEN:"request-only"}));
});
