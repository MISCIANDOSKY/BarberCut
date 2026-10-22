import { createClient } from "npm:@supabase/supabase-js@2.57.4";
Deno.serve(async (req: Request) => {
  if(req.method!=="POST")return new Response("Method not allowed",{status:405});
  let version="",token="",claimed=false,success=false;
  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
  try {
    const body=await req.text();
    if(body.length>1024)return new Response("Invalid request",{status:400});
    const input=JSON.parse(body);version=input.version;token=input.token;
    if(typeof version!=="string"||typeof token!=="string"||!/^[0-9a-f-]{36}$/.test(version)||!/^[0-9a-f-]{72}$/.test(token))return new Response("Access denied",{status:401});
    // Only a server-created, expiring, single-use queue token can claim a due change.
    // The request never supplies the name, project, recipient or management credential.
    const {data,error}=await admin.rpc("claim_brand_activation",{p_version:version,p_token:token});
    if(error||!data)return new Response("Unavailable",{status:503});
    claimed=true;
    const response=await fetch("https://api.supabase.com/v1/projects/wrpwitehcikplsauiwmg/config/auth",{
      method:"PATCH",headers:{"Authorization":"Bearer "+data.access_token,"Content-Type":"application/json"},
      body:JSON.stringify({smtp_sender_name:data.name}),signal:AbortSignal.timeout(15000),
    });
    if(!response.ok)return new Response("Configuration unavailable",{status:503});
    const {data:finished,error:finishError}=await admin.rpc("finish_brand_activation",{p_version:version,p_token:token,p_success:true});
    success=!finishError&&finished===true;
    return success?Response.json({activated:true}):new Response("Retry required",{status:503});
  }catch{return new Response("Unavailable",{status:503});}
  finally{
    if(claimed&&!success)await admin.rpc("finish_brand_activation",{p_version:version,p_token:token,p_success:false});
  }
});
