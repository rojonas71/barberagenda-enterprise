import { createClient } from 'npm:@supabase/supabase-js@2'

const allowedOrigin = Deno.env.get('APP_ORIGIN') || '*'
const corsHeaders = {
  'Access-Control-Allow-Origin': allowedOrigin,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const authorization = req.headers.get('Authorization') || ''
    if (!authorization) throw new Error('unauthorized')

    const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } })
    const { data: callerUser } = await caller.auth.getUser()
    const { data: role, error: roleError } = await caller.rpc('dev_current_role')
    if (roleError || !['super_admin', 'support'].includes(String(role || ''))) throw new Error('developer_permission_denied')

    const admin = createClient(url, serviceRole, { auth: { autoRefreshToken: false, persistSession: false } })
    const body = await req.json()
    const action = String(body.action || '')
    const userId = String(body.user_id || '')
    if (!userId) throw new Error('user_id_required')
    if (callerUser.user?.id === userId && ['ban', 'unban'].includes(action)) throw new Error('cannot_manage_your_own_auth_state')
    const { data: targetDev } = await caller.from('developer_admins').select('role,active').eq('user_id', userId).maybeSingle()
    if (targetDev?.active && role !== 'super_admin') throw new Error('super_admin_required_for_dev_account')

    if (action === 'ban') {
      const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: String(body.duration || '876000h') })
      if (error) throw error
    } else if (action === 'unban') {
      const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: 'none' })
      if (error) throw error
    } else if (action === 'send_password_reset') {
      const { data: userData, error: userError } = await admin.auth.admin.getUserById(userId)
      if (userError) throw userError
      const email = userData.user?.email
      if (!email) throw new Error('email_not_found')
      const publicClient = createClient(url, anonKey)
      const redirectTo = String(body.redirect_to || '')
      const { error } = await publicClient.auth.resetPasswordForEmail(email, redirectTo ? { redirectTo } : undefined)
      if (error) throw error
    } else {
      throw new Error('invalid_action')
    }

    await caller.rpc('dev_write_audit', {
      p_action: `auth.${action}`,
      p_target_type: 'user',
      p_target_id: userId,
      p_metadata: {},
    })

    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'unknown_error' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
