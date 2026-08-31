import { createClient } from '@supabase/supabase-js'
import { configureOfflineAuthProvider, resilientSupabaseFetch } from './offline'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('Configure VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY no arquivo .env')
}

export const supabase = createClient(
  supabaseUrl || 'https://example.supabase.co',
  supabaseAnonKey || 'public-anon-key',
  {
    global: { fetch: resilientSupabaseFetch },
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  },
)

configureOfflineAuthProvider(async () => {
  const { data } = await supabase.auth.getSession()
  return {
    apikey: supabaseAnonKey || 'public-anon-key',
    authorization: `Bearer ${data.session?.access_token || supabaseAnonKey || 'public-anon-key'}`,
  }
})

// getUser() valida no servidor. Sem conexão, usamos somente a sessão local já existente
// para liberar a interface offline; o Supabase/RLS continua sendo a autoridade ao sincronizar.
const onlineGetUser = supabase.auth.getUser.bind(supabase.auth)
supabase.auth.getUser = (async (...args: Parameters<typeof onlineGetUser>) => {
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    const { data } = await supabase.auth.getSession()
    return { data: { user: data.session?.user ?? null }, error: null } as Awaited<ReturnType<typeof onlineGetUser>>
  }
  try {
    return await onlineGetUser(...args)
  } catch (error) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      const { data } = await supabase.auth.getSession()
      return { data: { user: data.session?.user ?? null }, error: null } as Awaited<ReturnType<typeof onlineGetUser>>
    }
    throw error
  }
}) as typeof supabase.auth.getUser
