const STATIC_CACHE='barberagenda-v5-offline-static'
const RUNTIME_CACHE='barberagenda-v5-offline-runtime'
const APP_SHELL=['/','/manifest.webmanifest','/icon.svg']

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(STATIC_CACHE).then(cache=>cache.addAll(APP_SHELL)).then(()=>self.skipWaiting()))
})

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(k=>![STATIC_CACHE,RUNTIME_CACHE].includes(k)).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
  )
})

self.addEventListener('fetch',event=>{
  const req=event.request
  if(req.method!=='GET') return
  const url=new URL(req.url)

  if(url.origin!==self.location.origin) return

  if(req.mode==='navigate'){
    event.respondWith(
      fetch(req)
        .then(res=>{ const clone=res.clone(); caches.open(RUNTIME_CACHE).then(c=>c.put('/',clone)); return res })
        .catch(()=>caches.match(req).then(hit=>hit||caches.match('/')))
    )
    return
  }

  if(['script','style','image','font'].includes(req.destination)){
    event.respondWith(
      caches.match(req).then(hit=>hit||fetch(req).then(res=>{
        if(res.ok){ const clone=res.clone(); caches.open(RUNTIME_CACHE).then(c=>c.put(req,clone)) }
        return res
      }))
    )
    return
  }

  event.respondWith(
    fetch(req).then(res=>{
      if(res.ok){ const clone=res.clone(); caches.open(RUNTIME_CACHE).then(c=>c.put(req,clone)) }
      return res
    }).catch(()=>caches.match(req))
  )
})

self.addEventListener('message',event=>{
  if(event.data?.type==='SKIP_WAITING') self.skipWaiting()
})
