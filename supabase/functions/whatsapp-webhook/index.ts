import { adminClient, cors, verifyMetaSignature } from '../_shared/whatsapp.ts'

async function sha256(value: string) {
  const data = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(data)).map(b => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  const headers = cors(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers })

  const url = new URL(req.url)
  if (req.method === 'GET') {
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge') || ''
    const expected = Deno.env.get('WHATSAPP_VERIFY_TOKEN') || ''
    if (mode === 'subscribe' && expected && token === expected) return new Response(challenge, { status: 200 })
    return new Response('Forbidden', { status: 403 })
  }

  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 })
  const rawBody = await req.text()
  try {
    const valid = await verifyMetaSignature(rawBody, req.headers.get('x-hub-signature-256'))
    if (!valid) return new Response(JSON.stringify({ error: 'invalid_signature' }), { status: 401, headers })
    const supabase = adminClient()
    const payload = JSON.parse(rawBody)
    const eventKey = await sha256(rawBody)
    const { data: existing } = await supabase.from('whatsapp_webhook_events').select('id').eq('event_key', eventKey).maybeSingle()
    if (existing) return new Response(JSON.stringify({ ok: true, duplicate: true }), { headers })
    const { data: event } = await supabase.from('whatsapp_webhook_events').insert({ event_key: eventKey, event_type: payload?.object || 'whatsapp', raw_payload: payload }).select('id').single()

    try {
      for (const entry of payload?.entry || []) {
        for (const change of entry?.changes || []) {
          const value = change?.value || {}
          const phoneNumberId = value?.metadata?.phone_number_id ? String(value.metadata.phone_number_id) : ''
          let businessId: string | null = null
          let inboundEnabled = false
          if (phoneNumberId) {
            const { data: settings } = await supabase.from('whatsapp_settings').select('business_id,inbound_enabled').eq('meta_phone_number_id', phoneNumberId).maybeSingle()
            businessId = settings?.business_id || null
            inboundEnabled = Boolean(settings?.inbound_enabled)
          }

          for (const status of value?.statuses || []) {
            const providerId = String(status?.id || '')
            if (!providerId) continue
            const mapped = ['sent','delivered','read','failed'].includes(status.status) ? status.status : 'sent'
            const stamp = status?.timestamp ? new Date(Number(status.timestamp) * 1000).toISOString() : new Date().toISOString()
            const patch: Record<string, unknown> = { status: mapped }
            if (mapped === 'delivered') patch.delivered_at = stamp
            if (mapped === 'read') patch.read_at = stamp
            if (mapped === 'failed') { patch.failed_at = stamp; patch.last_error = JSON.stringify(status?.errors || []) }
            await supabase.from('whatsapp_message_queue').update(patch).eq('provider_message_id', providerId)
          }

          const contactsByWa = new Map<string,string>()
          for (const contact of value?.contacts || []) contactsByWa.set(String(contact?.wa_id || ''), String(contact?.profile?.name || ''))
          if (!inboundEnabled) continue
          for (const message of value?.messages || []) {
            const providerId = String(message?.id || '')
            if (!providerId) continue
            const from = String(message?.from || '')
            let textBody: string | null = null
            if (message?.type === 'text') textBody = String(message?.text?.body || '')
            else if (message?.type === 'button') textBody = String(message?.button?.text || '')
            else if (message?.type === 'interactive') textBody = String(message?.interactive?.button_reply?.title || message?.interactive?.list_reply?.title || '')
            await supabase.from('whatsapp_inbound_messages').upsert({
              business_id: businessId,
              provider_message_id: providerId,
              from_phone: from,
              contact_name: contactsByWa.get(from) || null,
              message_type: String(message?.type || 'unknown'),
              text_body: textBody,
              raw_payload: message,
              received_at: message?.timestamp ? new Date(Number(message.timestamp) * 1000).toISOString() : new Date().toISOString(),
            }, { onConflict: 'provider_message_id' })
          }
        }
      }
      if (event?.id) await supabase.from('whatsapp_webhook_events').update({ processed: true }).eq('id', event.id)
    } catch (processingError) {
      if (event?.id) await supabase.from('whatsapp_webhook_events').update({ processing_error: processingError instanceof Error ? processingError.message : 'processing_error' }).eq('id', event.id)
      throw processingError
    }
    return new Response(JSON.stringify({ ok: true }), { headers })
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'unknown_error' }), { status: 400, headers })
  }
})
