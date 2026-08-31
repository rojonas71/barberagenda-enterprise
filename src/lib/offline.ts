const DB_NAME = 'barberagenda-offline-v1'
const DB_VERSION = 1
const RESPONSE_STORE = 'responses'
const QUEUE_STORE = 'queue'

const isBrowser = typeof window !== 'undefined' && typeof indexedDB !== 'undefined'
const nativeFetch = typeof globalThis.fetch === 'function' ? globalThis.fetch.bind(globalThis) : fetch

type CachedResponse = {
  key: string
  status: number
  statusText: string
  headers: [string, string][]
  body: string
  savedAt: number
}

export type OfflineQueueItem = {
  id: string
  url: string
  method: string
  headers: [string, string][]
  body: string | null
  createdAt: number
  attempts: number
  lastError?: string | null
}

type AuthProvider = () => Promise<{ apikey?: string; authorization?: string }>
let authProvider: AuthProvider | null = null
let syncPromise: Promise<{ synced: number; failed: number }> | null = null

export function configureOfflineAuthProvider(provider: AuthProvider) {
  authProvider = provider
}

function openDb(): Promise<IDBDatabase> {
  if (!isBrowser) return Promise.reject(new Error('IndexedDB indisponível'))
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION)
    request.onupgradeneeded = () => {
      const db = request.result
      if (!db.objectStoreNames.contains(RESPONSE_STORE)) db.createObjectStore(RESPONSE_STORE, { keyPath: 'key' })
      if (!db.objectStoreNames.contains(QUEUE_STORE)) db.createObjectStore(QUEUE_STORE, { keyPath: 'id' })
    }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function idbPut(storeName: string, value: unknown) {
  const db = await openDb()
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite')
    tx.objectStore(storeName).put(value)
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
  db.close()
}

async function idbGet<T>(storeName: string, key: string): Promise<T | null> {
  const db = await openDb()
  const result = await new Promise<T | null>((resolve, reject) => {
    const tx = db.transaction(storeName, 'readonly')
    const request = tx.objectStore(storeName).get(key)
    request.onsuccess = () => resolve((request.result as T) || null)
    request.onerror = () => reject(request.error)
  })
  db.close()
  return result
}

async function idbGetAll<T>(storeName: string): Promise<T[]> {
  const db = await openDb()
  const result = await new Promise<T[]>((resolve, reject) => {
    const tx = db.transaction(storeName, 'readonly')
    const request = tx.objectStore(storeName).getAll()
    request.onsuccess = () => resolve((request.result as T[]) || [])
    request.onerror = () => reject(request.error)
  })
  db.close()
  return result
}

async function idbDelete(storeName: string, key: string) {
  const db = await openDb()
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite')
    tx.objectStore(storeName).delete(key)
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
  db.close()
}

function dispatchQueueEvent() {
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('barberagenda:offline-queue'))
}

function dispatchSyncEvent(detail: { syncing: boolean; synced?: number; failed?: number }) {
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('barberagenda:offline-sync', { detail }))
}

function base64UrlDecode(value: string) {
  try {
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
    const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4)
    return atob(padded)
  } catch {
    return ''
  }
}

function requestIdentity(request: Request) {
  const auth = request.headers.get('authorization') || ''
  const token = auth.replace(/^Bearer\s+/i, '')
  if (!token || token.startsWith('sb_')) return 'anon'
  const parts = token.split('.')
  if (parts.length !== 3) return 'anon'
  try {
    const payload = JSON.parse(base64UrlDecode(parts[1])) as { sub?: string; ref?: string }
    return payload.sub || payload.ref || 'anon'
  } catch {
    return 'anon'
  }
}

async function responseKey(request: Request) {
  const body = ['GET', 'HEAD'].includes(request.method) ? '' : await request.clone().text().catch(() => '')
  return `${requestIdentity(request)}|${request.method}|${request.url}|${body}`
}

function isSupabaseRest(url: URL) {
  return /\.supabase\.co$/i.test(url.hostname) && url.pathname.startsWith('/rest/v1/')
}

function isReadRpc(url: URL) {
  const marker = '/rest/v1/rpc/'
  if (!url.pathname.includes(marker)) return false
  const name = url.pathname.split(marker)[1] || ''
  return /^(get_|dev_list_|dev_admin_dashboard$|dev_health_summary$|dev_current_role$|dev_can$)/.test(name)
}

function isCacheableRead(request: Request, url: URL) {
  if (!isSupabaseRest(url)) return false
  return request.method === 'GET' || request.method === 'HEAD' || (request.method === 'POST' && isReadRpc(url))
}

function isQueueableMutation(request: Request, url: URL) {
  if (!isSupabaseRest(url) || isReadRpc(url)) return false
  return ['POST', 'PATCH', 'PUT', 'DELETE'].includes(request.method)
}

async function cacheResponse(request: Request, response: Response) {
  if (!isBrowser || !response.ok) return
  const key = await responseKey(request)
  const body = await response.clone().text()
  const item: CachedResponse = {
    key,
    status: response.status,
    statusText: response.statusText,
    headers: Array.from(response.headers.entries()),
    body,
    savedAt: Date.now(),
  }
  await idbPut(RESPONSE_STORE, item).catch(() => undefined)
}

async function cachedResponse(request: Request) {
  if (!isBrowser) return null
  const key = await responseKey(request)
  const item = await idbGet<CachedResponse>(RESPONSE_STORE, key).catch(() => null)
  if (!item) return null
  const headers = new Headers(item.headers)
  headers.set('x-barberagenda-cache', 'offline')
  headers.set('x-barberagenda-cached-at', String(item.savedAt))
  return new Response(item.body, { status: item.status, statusText: item.statusText, headers })
}

async function queueRequest(request: Request) {
  const body = await request.clone().text().catch(() => '')
  const headers = Array.from(request.headers.entries()).filter(([name]) => !['authorization', 'apikey', 'content-length'].includes(name.toLowerCase()))
  const item: OfflineQueueItem = {
    id: crypto.randomUUID(),
    url: request.url,
    method: request.method,
    headers,
    body: body || null,
    createdAt: Date.now(),
    attempts: 0,
    lastError: null,
  }
  await idbPut(QUEUE_STORE, item)
  dispatchQueueEvent()
  return item
}

function queuedResponse(request: Request, item: OfflineQueueItem) {
  const prefer = request.headers.get('prefer') || ''
  let payload = '[]'
  if (prefer.includes('return=representation') && item.body) {
    try {
      const parsed = JSON.parse(item.body)
      const rows = Array.isArray(parsed) ? parsed : [parsed]
      payload = JSON.stringify(rows.map((row) => ({ ...row, _offline_pending: true, _offline_queue_id: item.id })))
    } catch {
      payload = '[]'
    }
  }
  return new Response(payload, {
    status: 202,
    statusText: 'Accepted Offline',
    headers: {
      'content-type': 'application/json',
      'x-barberagenda-offline': 'queued',
      'x-barberagenda-queue-id': item.id,
      'content-range': '0-0/*',
    },
  })
}

export async function resilientSupabaseFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const request = new Request(input, init)
  const url = new URL(request.url)
  if (!isBrowser || !isSupabaseRest(url)) return nativeFetch(request)

  if (isCacheableRead(request, url)) {
    if (!navigator.onLine) {
      const cached = await cachedResponse(request)
      if (cached) return cached
    }
    try {
      const response = await nativeFetch(request)
      if (response.ok) void cacheResponse(request, response.clone())
      return response
    } catch (error) {
      const cached = await cachedResponse(request)
      if (cached) return cached
      throw error
    }
  }

  if (isQueueableMutation(request, url)) {
    if (!navigator.onLine) {
      const item = await queueRequest(request)
      return queuedResponse(request, item)
    }
    try {
      return await nativeFetch(request)
    } catch {
      const item = await queueRequest(request)
      return queuedResponse(request, item)
    }
  }

  return nativeFetch(request)
}

export async function getPendingOfflineCount() {
  if (!isBrowser) return 0
  const items = await idbGetAll<OfflineQueueItem>(QUEUE_STORE).catch(() => [])
  return items.length
}

export async function getOfflineQueue() {
  if (!isBrowser) return [] as OfflineQueueItem[]
  const items = await idbGetAll<OfflineQueueItem>(QUEUE_STORE).catch(() => [])
  return items.sort((a, b) => a.createdAt - b.createdAt)
}

export async function syncOfflineQueue() {
  if (!isBrowser || !navigator.onLine) return { synced: 0, failed: 0 }
  if (syncPromise) return syncPromise

  syncPromise = (async () => {
    dispatchSyncEvent({ syncing: true })
    let synced = 0
    let failed = 0
    const auth: { apikey?: string; authorization?: string } = authProvider ? await authProvider().catch(() => ({})) : {}
    const items = await getOfflineQueue()

    for (const item of items) {
      const headers = new Headers(item.headers)
      if (auth.apikey) headers.set('apikey', auth.apikey)
      if (auth.authorization) headers.set('authorization', auth.authorization)
      try {
        const response = await nativeFetch(item.url, {
          method: item.method,
          headers,
          body: item.body,
        })
        if (response.ok) {
          await idbDelete(QUEUE_STORE, item.id)
          synced += 1
          continue
        }
        const detail = await response.text().catch(() => '')
        item.attempts += 1
        item.lastError = `${response.status} ${detail || response.statusText}`.slice(0, 500)
        await idbPut(QUEUE_STORE, item)
        failed += 1
      } catch (error) {
        item.attempts += 1
        item.lastError = error instanceof Error ? error.message : 'Falha de rede'
        await idbPut(QUEUE_STORE, item)
        failed += 1
        break
      }
    }

    dispatchQueueEvent()
    dispatchSyncEvent({ syncing: false, synced, failed })
    return { synced, failed }
  })().finally(() => {
    syncPromise = null
  })

  return syncPromise
}

export function installOnlineSync() {
  if (!isBrowser) return () => undefined
  const handler = () => void syncOfflineQueue()
  window.addEventListener('online', handler)
  if (navigator.onLine) void syncOfflineQueue()
  return () => window.removeEventListener('online', handler)
}
