import { supabase } from './supabase'

let installed = false
export function installAppMonitoring() {
  if (installed || typeof window === 'undefined') return
  installed = true
  async function report(message: string, stack?: string, metadata: Record<string, unknown> = {}) {
    try {
      const { data } = await supabase.auth.getUser()
      if (!data.user) return
      const { data: membership } = await supabase.from('business_members').select('business_id').eq('user_id', data.user.id).limit(1).maybeSingle()
      await supabase.from('app_error_logs').insert({ business_id: membership?.business_id || null, user_id: data.user.id, level: 'error', source: 'web', message: message.slice(0, 2000), stack: stack?.slice(0, 8000) || null, metadata })
    } catch { /* monitoramento nunca deve quebrar a aplicação */ }
  }
  window.addEventListener('error', e => { void report(e.message || 'window.error', e.error?.stack, { filename: e.filename, line: e.lineno, column: e.colno }) })
  window.addEventListener('unhandledrejection', e => { const err = e.reason instanceof Error ? e.reason : new Error(String(e.reason)); void report(err.message, err.stack, { kind: 'unhandledrejection' }) })
}
