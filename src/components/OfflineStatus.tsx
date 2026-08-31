import { useCallback, useEffect, useState } from 'react'
import { CloudOff, RefreshCw, Wifi, WifiOff } from 'lucide-react'
import { getPendingOfflineCount, installOnlineSync, syncOfflineQueue } from '../lib/offline'

export function OfflineStatus() {
  const [online, setOnline] = useState(() => typeof navigator === 'undefined' ? true : navigator.onLine)
  const [pending, setPending] = useState(0)
  const [syncing, setSyncing] = useState(false)
  const [lastSync, setLastSync] = useState<number | null>(null)

  const refreshPending = useCallback(async () => setPending(await getPendingOfflineCount()), [])

  useEffect(() => {
    void refreshPending()
    const cleanupOnlineSync = installOnlineSync()
    const onOnline = () => { setOnline(true); void refreshPending() }
    const onOffline = () => setOnline(false)
    const onQueue = () => void refreshPending()
    const onSync = (event: Event) => {
      const detail = (event as CustomEvent<{ syncing: boolean; synced?: number }>).detail
      setSyncing(Boolean(detail?.syncing))
      if (!detail?.syncing && (detail?.synced || 0) > 0) setLastSync(Date.now())
      void refreshPending()
    }
    window.addEventListener('online', onOnline)
    window.addEventListener('offline', onOffline)
    window.addEventListener('barberagenda:offline-queue', onQueue)
    window.addEventListener('barberagenda:offline-sync', onSync)
    return () => {
      cleanupOnlineSync()
      window.removeEventListener('online', onOnline)
      window.removeEventListener('offline', onOffline)
      window.removeEventListener('barberagenda:offline-queue', onQueue)
      window.removeEventListener('barberagenda:offline-sync', onSync)
    }
  }, [refreshPending])

  async function syncNow() {
    if (!online || syncing) return
    setSyncing(true)
    await syncOfflineQueue()
    await refreshPending()
    setSyncing(false)
  }

  const title = !online
    ? `Sem internet${pending ? ` • ${pending} pendente${pending === 1 ? '' : 's'}` : ''}`
    : syncing
      ? 'Sincronizando...'
      : pending
        ? `${pending} alteração${pending === 1 ? '' : 'ões'} pendente${pending === 1 ? '' : 's'}`
        : 'Online e sincronizado'

  return (
    <button
      type="button"
      className={`offline-status ${online ? 'online' : 'offline'} ${pending ? 'has-pending' : ''}`}
      onClick={syncNow}
      disabled={!online || syncing}
      title={lastSync ? `${title}. Última sincronização ${new Date(lastSync).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}` : title}
    >
      <span className="offline-status-icon">
        {syncing ? <RefreshCw size={15} className="spin"/> : !online ? <WifiOff size={15}/> : pending ? <CloudOff size={15}/> : <Wifi size={15}/>} 
      </span>
      <span>{title}</span>
      {online && pending > 0 && !syncing && <small>Sincronizar</small>}
    </button>
  )
}
