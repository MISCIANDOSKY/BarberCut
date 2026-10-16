import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
const origin='https://misciandosky.github.io';
const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const reply=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers:cors});
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return reply(405,'Metodo non consentito');
  try{
    const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');
    if(!token)return reply(401,'Accesso richiesto');
    const api=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false}});
    // Validate with Auth before reading any claims; browser-supplied claims are never trusted.
    const {data,error:authError}=await api.auth.getUser(token);
    if(authError||!data.user)return reply(401,'Sessione non valida');
    const payload=token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');
    const claims=JSON.parse(atob(payload.padEnd(Math.ceil(payload.length/4)*4,'=')));
    const now=Date.now()/1000;
    const recentEmail=Array.isArray(claims.amr)&&claims.amr.some((v:{method?:string;timestamp?:number})=>
      (v.method==='otp'||v.method==='magiclink')&&typeof v.timestamp==='number'&&v.timestamp>now-900&&v.timestamp<=now+30);
    if(!recentEmail)return reply(403,'Verifica il codice ricevuto via email entro 15 minuti');
    if(claims.sub!==data.user.id||typeof claims.session_id!=='string')return reply(403,'Sessione non valida');
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
    // The database verifies the staff role and binds authorization to this exact active session.
    const {error}=await admin.rpc('staff_authorize_session',{p_user:data.user.id,p_session:claims.session_id});
    if(error)return reply(403,'Accesso non consentito');
    return reply(200,'Email verificata');
  }catch{return reply(400,'Verifica non riuscita')}
});
