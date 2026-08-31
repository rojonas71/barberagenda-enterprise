import { adminClient, cors, env, getBusinessToken, graphSend } from '../_shared/whatsapp.ts'

Deno.serve(async (req) => {
  const headers = cors(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers })
  try {
    const expected = env('WHATSAPP_WORKER_SECRET')
    if (req.headers.get('x-worker-secret') !== expected) return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers })
    const supabase = adminClient()

    await supabase.rpc('queue_due_whatsapp_reminders')
    const { data: claimed, error: claimError } = await supabase.rpc('claim_whatsapp_messages', { p_limit: 30 })
    if (claimError) throw claimError

    const results: Array<Record<string, unknown>> = []
    for (const message of claimed || []) {
      try {
        const { data: settings, error: settingsError } = await supabase.from('whatsapp_settings').select('*').eq('business_id', message.business_id).single()
        if (settingsError || !settings?.enabled) throw new Error(settingsError?.message || 'whatsapp_disabled')
        if (!settings.meta_phone_number_id) throw new Error('meta_phone_number_id_missing')
        const token = await getBusinessToken(supabase, message.business_id)
        const payload = await graphSend({
          token,
          graphVersion: settings.graph_version,
          phoneNumberId: settings.meta_phone_number_id,
          to: message.to_phone,
          type: message.message_type,
          text: message.text_body,
          templateName: message.template_name,
          templateLanguage: message.template_language || settings.template_language,
          components: message.template_components,
        })
        const providerMessageId = payload?.messages?.[0]?.id || null
        await supabase.from('whatsapp_message_queue').update({
          status: 'sent', provider_message_id: providerMessageId, sent_at: new Date().toISOString(), last_error: null,
        }).eq('id', message.id)
        results.push({ id: message.id, ok: true, provider_message_id: providerMessageId })
      } catch (error) {
        const attempts = Number(message.attempts || 1)
        const terminal = attempts >= Number(message.max_attempts || 5)
        const delaySeconds = Math.min(900, Math.max(30, Math.pow(2, attempts) * 30))
        const retryAt = new Date(Date.now() + delaySeconds * 1000).toISOString()
        const errorMessage = error instanceof Error ? error.message : 'unknown_error'
        await supabase.from('whatsapp_message_queue').update({
          status: terminal ? 'failed' : 'queued', last_error: errorMessage, failed_at: terminal ? new Date().toISOString() : null,
          scheduled_at: terminal ? message.scheduled_at : retryAt,
        }).eq('id', message.id)
        results.push({ id: message.id, ok: false, error: errorMessage, terminal })
      }
    }
    return new Response(JSON.stringify({ ok: true, processed: results.length, results }), { headers })
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'unknown_error' }), { status: 500, headers })
  }
})
