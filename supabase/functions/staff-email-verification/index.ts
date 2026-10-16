
import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
const origin='https://misciandosky.github.io';
const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const reply=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers:cors});
Deno.serve(async(req:Request)=>{
if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
if(req.method!=='POST')return reply(405,'Metodo non consentito');
try{
const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');const body=await req.json();const original=body.password_token;
if(!token||typeof original!=='string')return reply(401,'Accesso richiesto');
const api=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false}});
const [{data:a,error:ae},{data:b,error:be}]=await Promise.all([api.auth.getUser(token),api.auth.getUser(original)]);
if(ae||be||!a.user||a.user.id!==b.user?.id)return reply(401,'Sessione non valida');
const decode=(t:string)=>JSON.parse(atob(t.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));
const claims=decode(token),old=decode(original),now=Date.now()/1000;
const recent=(c:any,m:string)=>Array.isArray(c.amr)&&c.amr.some((v:any)=>v.method===m&&v.timestamp>now-900&&v.timestamp<=now+30);
if(!recent(old,'password')||!recent(claims,'otp')&&!recent(claims,'magiclink'))return reply(403,'Completa password e verifica email entro 15 minuti');
if(!claims.session_id)return reply(403,'Sessione non valida');
const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
const {error}=await admin.rpc('staff_authorize_session',{p_user:a.user.id,p_session:claims.session_id});
if(error)return reply(403,'Accesso non consentito');
return reply(200,'Email verificata');
}catch{return reply(400,'Verifica non riuscita')}
});