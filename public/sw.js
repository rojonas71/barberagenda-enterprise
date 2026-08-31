const CACHE='barberagenda-v4-static'
const APP_SHELL=['/','/manifest.webmanifest','/icon.svg']
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(APP_SHELL)).then(()=>self.skipWaiting()))})
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))})
self.addEventListener('fetch',event=>{
 const req=event.request
 if(req.method!=='GET'||new URL(req.url).origin!==self.location.origin)return
 if(req.mode==='navigate'){
   event.respondWith(fetch(req).catch(()=>caches.match('/')))
   return
 }
 event.respondWith(caches.match(req).then(hit=>hit||fetch(req).then(res=>{if(res.ok&&['script','style','image','font'].includes(req.destination)){const clone=res.clone();caches.open(CACHE).then(c=>c.put(req,clone))}return res})))
})
