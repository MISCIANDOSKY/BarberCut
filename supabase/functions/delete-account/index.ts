
import{createClient}from'npm:@supabase/supabase-js@2.57.4';
const headers={'Access-Control-Allow-Origin':'https://misciandosky.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const response=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers});
Deno.serve(async(req:Request)=>{
if(req.method==='OPTIONS')return new Response('ok',{headers});
if(req.method!=='POST')return response(405,'Metodo non consentito');
try{
const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');if(!token)return response(401,'Accesso richiesto');
const body=await req.json();if(body.confirm!==true)return response(400,'Conferma richiesta');
const api=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false}});
const {data,error}=await api.auth.getUser(token);if(error||!data.user)return response(401,'Sessione non valida');
const c=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))),now=Date.now()/1000;
if(!Array.isArray(c.amr)||!c.amr.some((v:any)=>['otp','magiclink'].includes(v.method)&&v.timestamp>now-600&&v.timestamp<=now+30))return response(403,'Conferma prima la tua email con un nuovo codice o link');
const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
const prepared=await admin.rpc('prepare_account_deletion',{p_user:data.user.id});if(prepared.error)return response(409,prepared.error.message.includes('LAST_ADMIN')?'Prima assegna il ruolo a un altro amministratore':'Eliminazione non ancora configurata dal titolare');
await admin.auth.admin.signOut(token,'global');
const removed=await admin.auth.admin.deleteUser(data.user.id);
if(removed.error)return response(500,'Dati anonimizzati. La rimozione dell’account deve essere completata dall’amministratore');
return response(200,'Account eliminato');
}catch{return response(400,'Richiesta non valida')}
});