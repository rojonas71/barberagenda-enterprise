import { adminClient, cors, getBusinessToken, graphSend, normalizePhone, userClient } from '../_shared/whatsapp.ts'

Deno.serve(async (req) => {
  const headers = cors(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers })
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers })
  try {
    const authorization = req.headers.get('Authorization') || ''
    if (!authorization) throw new Error('unauthorized')
    const caller = userClient(authorization)
    const admin = adminClient()
    const { data: authData, error: authError } = await caller.auth.getUser()
    if (authError || !authData.user) throw new Error('unauthorized')
    const body = await req.json()
    const businessId = String(body.business_id || '')
    if (!businessId) throw new Error('business_id_required')
    const { data: member } = await caller.from('business_members').select('role,active').eq('business_id', businessId).eq('user_id', authData.user.id).maybeSingle()
    if (!member?.active || !['owner','manager'].includes(member.role)) throw new Error('permission_denied')

    const action = String(body.action || '')
    if (action === 'save_access_token') {
      const token = String(body.access_token || '')
      const { error } = await caller.rpc('whatsapp_set_access_token', { p_business_id: businessId, p_access_token: token })
      if (error) throw error
      return new Response(JSON.stringify({ ok: true }), { headers })
    }

    if (action === 'test') {
      const { data: settings, error: settingsError } = await admin.from('whatsapp_settings').select('*').eq('business_id', businessId).single()
      if (settingsError) throw settingsError
      if (!settings.meta_phone_number_id) throw new Error('meta_phone_number_id_missing')
      const token = await getBusinessToken(admin, businessId)
      const to = normalizePhone(String(body.to_phone || ''))
      if (to.length < 12) throw new Error('invalid_test_phone')
      try {
        const result = await graphSend({
          token,
          graphVersion: settings.graph_version,
          phoneNumberId: settings.meta_phone_number_id,
          to,
          type: 'text',
          text: 'Teste de integração do BarberAgenda. ✅',
        })
        await admin.from('whatsapp_settings').update({ last_test_at: new Date().toISOString(), last_test_ok: true, last_test_error: null }).eq('business_id', businessId)
        return new Response(JSON.stringify({ ok: true, result }), { headers })
      } catch (error) {
        const msg = error instanceof Error ? error.message : 'test_failed'
        await admin.from('whatsapp_settings').update({ last_test_at: new Date().toISOString(), last_test_ok: false, last_test_error: msg }).eq('business_id', businessId)
        throw error
      }
    }

    if (action === 'queue_manual') {
      const to = normalizePhone(String(body.to_phone || ''))
      const text = String(body.text || '').trim()
      if (to.length < 12 || !text) throw new Error('phone_and_text_required')
      const { data, error } = await admin.from('whatsapp_message_queue').insert({
        business_id: businessId, to_phone: to, kind: 'manual', message_type: 'text', text_body: text,
      }).select('id').single()
      if (error) throw error
      return new Response(JSON.stringify({ ok: true, queue_id: data.id }), { headers })
    }

    if (action === 'retry') {
      const id = String(body.message_id || '')
      const { error } = await admin.from('whatsapp_message_queue').update({ status: 'queued', scheduled_at: new Date().toISOString(), last_error: null, failed_at: null }).eq('id', id).eq('business_id', businessId)
      if (error) throw error
      return new Response(JSON.stringify({ ok: true }), { headers })
    }

    if (action === 'cancel') {
      const id = String(body.message_id || '')
      const { error } = await admin.from('whatsapp_message_queue').update({ status: 'cancelled' }).eq('id', id).eq('business_id', businessId).in('status', ['queued','failed'])
      if (error) throw error
      return new Response(JSON.stringify({ ok: true }), { headers })
    }

    throw new Error('invalid_action')
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'unknown_error' }), { status: 400, headers })
  }
})
