import { PropsWithChildren, useEffect, useState } from 'react'
import { Wrench } from 'lucide-react'
import { useLocation } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export function MaintenanceGate({ children }: PropsWithChildren) {
  const location = useLocation()
  const [maintenance, setMaintenance] = useState(false)
  const [announcement, setAnnouncement] = useState<string | null>(null)
  const [loaded, setLoaded] = useState(false)
  useEffect(() => { void (async () => {
    const { data, error } = await supabase.from('system_settings').select('maintenance_mode,announcement').eq('id', 1).maybeSingle()
    if (!error && data) { setMaintenance(Boolean(data.maintenance_mode)); setAnnouncement(data.announcement || null) }
    setLoaded(true)
  })() }, [location.pathname])
  if (!loaded || location.pathname.startsWith('/dev-admin')) return <>{children}</>
  if (!maintenance) return <>{children}</>
  return <main className="maintenance-page"><div><Wrench size={42}/><h1>Manutenção programada</h1><p>{announcement || 'Estamos realizando melhorias. Tente novamente em alguns instantes.'}</p><small>BarberAgenda</small></div></main>
}
