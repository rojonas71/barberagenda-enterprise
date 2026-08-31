import { createClient } from 'npm:@supabase/supabase-js@2'

export function env(name: string, required = true) {
  const value = Deno.env.get(name) || ''
  if (required && !value) throw new Error(`missing_env_${name}`)
  return value
}

export function supabaseEnv() {
  const url = env('SUPABASE_URL')
  let anon = Deno.env.get('SUPABASE_ANON_KEY') || ''
  let secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
  if (!anon) {
    try { anon = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') || '{}').default || '' } catch { /* noop */ }
  }
  if (!secret) {
    try { secret = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default || '' } catch { /* noop */ }
  }
  if (!anon || !secret) throw new Error('supabase_keys_missing')
  return { url, anon, secret }
}

export function adminClient() {
  const { url, secret } = supabaseEnv()
  return createClient(url, secret, { auth: { autoRefreshToken: false, persistSession: false } })
}

export function userClient(authorization: string) {
  const { url, anon } = supabaseEnv()
  return createClient(url, anon, { global: { headers: { Authorization: authorization } } })
}

export function cors(req: Request) {
  const configured = Deno.env.get('APP_ORIGIN') || ''
  const origin = configured || req.headers.get('Origin') || '*'
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-worker-secret, x-hub-signature-256',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Content-Type': 'application/json',
    'Vary': 'Origin',
  }
}

export function normalizePhone(value: string) {
  let digits = String(value || '').replace(/\D/g, '')
  if (digits.length === 10 || digits.length === 11) digits = `55${digits}`
  return digits
}

export async function getBusinessToken(supabase: ReturnType<typeof adminClient>, businessId: string) {
  const { data, error } = await supabase.rpc('whatsapp_get_access_token', { p_business_id: businessId })
  if (error) throw new Error(`token_lookup_failed:${error.message}`)
  if (!data) throw new Error('whatsapp_access_token_not_configured')
  return String(data)
}

export async function graphSend(args: {
  token: string
  graphVersion: string
  phoneNumberId: string
  to: string
  type: 'text' | 'template'
  text?: string | null
  templateName?: string | null
  templateLanguage?: string | null
  components?: unknown[] | null
}) {
  const version = args.graphVersion.trim().replace(/^\/+/, '')
  const endpoint = `https://graph.facebook.com/${version}/${encodeURIComponent(args.phoneNumberId)}/messages`
  const body: Record<string, unknown> = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to: normalizePhone(args.to),
    type: args.type,
  }
  if (args.type === 'text') {
    body.text = { preview_url: false, body: String(args.text || '') }
  } else {
    body.template = {
      name: String(args.templateName || ''),
      language: { code: String(args.templateLanguage || 'pt_BR') },
      components: Array.isArray(args.components) ? args.components : [],
    }
  }

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { Authorization: `Bearer ${args.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    const message = payload?.error?.message || payload?.error?.error_user_msg || `graph_http_${response.status}`
    const error = new Error(String(message)) as Error & { payload?: unknown; status?: number }
    error.payload = payload
    error.status = response.status
    throw error
  }
  return payload
}

export async function verifyMetaSignature(rawBody: string, signatureHeader: string | null) {
  const appSecret = Deno.env.get('WHATSAPP_APP_SECRET') || ''
  if (!appSecret) throw new Error('WHATSAPP_APP_SECRET_not_configured')
  if (!signatureHeader?.startsWith('sha256=')) return false
  const encoder = new TextEncoder()
  const key = await crypto.subtle.importKey('raw', encoder.encode(appSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(rawBody))
  const expected = `sha256=${Array.from(new Uint8Array(signature)).map(b => b.toString(16).padStart(2, '0')).join('')}`
  if (expected.length !== signatureHeader.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signatureHeader.charCodeAt(i)
  return diff === 0
}
