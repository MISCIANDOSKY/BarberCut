const KEY='barbercut-password-proof';
export function savePasswordProof(token:string){localStorage.setItem(KEY,JSON.stringify({token,expiresAt:Date.now()+15*60*1000}))}
export function getPasswordProof():string|null{try{const data=JSON.parse(localStorage.getItem(KEY)||'null');if(data&&typeof data.token==='string'&&data.expiresAt>Date.now())return data.token}catch{}localStorage.removeItem(KEY);return null}
export function clearPasswordProof(){localStorage.removeItem(KEY)}
