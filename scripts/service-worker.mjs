import { pushWorkerSource } from "./push-worker.mjs";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
function walk(p) {
  return readdirSync(p, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(p + "/" + e.name) : [p + "/" + e.name],
  );
}
let all = walk("dist");
let ver = createHash("sha256")
  .update(all.map((f) => readFileSync(f)).join(""))
  .digest("hex")
  .slice(0, 12);
let paths = all.map((f) => "./" + f.slice(5));
writeFileSync(
  "dist/sw.js",
  `const NAME='barbercut-${ver}',SHELL=${JSON.stringify(paths)};self.addEventListener('install',e=>e.waitUntil(caches.open(NAME).then(c=>c.addAll(SHELL))));self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('barbercut-')&&k!==NAME).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));self.addEventListener('message',e=>{if(e.data==='ACTIVATE')self.skipWaiting()});self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==self.location.origin||!u.pathname.startsWith(new URL(self.registration.scope).pathname))return;if(e.request.mode==='navigate'){e.respondWith(fetch(e.request).catch(()=>caches.match(new URL('./index.html',self.registration.scope)).then(r=>r||Response.error())));return}if(SHELL.some(p=>new URL(p,self.registration.scope).href===u.href))e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request)))})${pushWorkerSource()}`,
);
