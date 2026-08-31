import { FormEvent, useEffect, useMemo, useState } from 'react'
import { ArrowLeft, KeyRound, LockKeyhole, Scissors, UserPlus } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

type AuthMode = 'login' | 'register' | 'forgot' | 'new-password'

function translateAuthError(message: string) {
  const normalized = message.toLowerCase()

  if (normalized.includes('invalid login credentials')) {
    return 'E-mail ou senha inválidos. Se você ainda não criou sua conta, use “Criar primeiro acesso”. Se esqueceu a senha, use “Esqueci minha senha”.'
  }

  if (normalized.includes('email not confirmed')) {
    return 'Seu e-mail ainda não foi confirmado. Abra a mensagem enviada pelo Supabase e confirme a conta antes de entrar.'
  }

  if (normalized.includes('user already registered')) {
    return 'Este e-mail já possui uma conta. Entre com a senha cadastrada ou use “Esqueci minha senha”.'
  }

  if (normalized.includes('password should be at least')) {
    return 'A senha é muito curta. Use pelo menos 8 caracteres.'
  }

  if (normalized.includes('too many requests') || normalized.includes('rate limit')) {
    return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.'
  }

  return message
}

async function goToWorkspace(navigate: ReturnType<typeof useNavigate>, redirectPath?: string | null) {
  const { data: userData } = await supabase.auth.getUser()
  const user = userData.user
  if (!user) {
    navigate('/login', { replace: true })
    return
  }

  if (redirectPath && redirectPath.startsWith('/convite/')) {
    navigate(redirectPath, { replace: true })
    return
  }

  const { data: membership } = await supabase
    .from('business_members')
    .select('business_id')
    .eq('user_id', user.id)
    .limit(1)
    .maybeSingle()

  navigate(membership ? '/painel/dashboard' : '/onboarding', { replace: true })
}

export function LoginPage() {
  const navigate = useNavigate()
  const initialMode = useMemo<AuthMode>(() => {
    const params = new URLSearchParams(window.location.search)
    if (params.get('reset') === '1') return 'new-password'
    if (params.get('mode') === 'register') return 'register'
    return 'login'
  }, [])

  const redirectPath = useMemo(() => new URLSearchParams(window.location.search).get('redirect'), [])
  const [mode, setMode] = useState<AuthMode>(initialMode)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [message, setMessage] = useState('')
  const [success, setSuccess] = useState(false)
  const [loading, setLoading] = useState(false)
  const [allowSignup, setAllowSignup] = useState(true)

  useEffect(() => {
    void (async () => {
      const { data } = await supabase.from('system_settings').select('allow_new_signups').eq('id', 1).maybeSingle()
      if (data?.allow_new_signups === false) {
        setAllowSignup(false)
        if (mode === 'register') setMode('login')
      }
    })()

    const { data: authListener } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY') {
        setMode('new-password')
        setMessage('Crie uma nova senha para sua conta.')
        setSuccess(true)
      }
    })

    return () => authListener.subscription.unsubscribe()
  }, [])

  function changeMode(next: AuthMode) {
    setMode(next)
    setMessage('')
    setSuccess(false)
    setPassword('')
    setConfirmPassword('')
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    setLoading(true)
    setMessage('')
    setSuccess(false)

    const normalizedEmail = email.trim().toLowerCase()

    try {
      if (mode === 'login') {
        const { error } = await supabase.auth.signInWithPassword({
          email: normalizedEmail,
          password
        })

        if (error) throw error
        await goToWorkspace(navigate, redirectPath)
        return
      }

      if (mode === 'register') {
        if (!allowSignup) {
          setMessage('Novos cadastros estão temporariamente desativados pela administração da plataforma.')
          return
        }
        if (password.length < 8) {
          setMessage('Use uma senha com pelo menos 8 caracteres.')
          return
        }
        if (password !== confirmPassword) {
          setMessage('As duas senhas não são iguais.')
          return
        }

        const { data, error } = await supabase.auth.signUp({
          email: normalizedEmail,
          password,
          options: {
            emailRedirectTo: `${window.location.origin}/login${redirectPath ? `?redirect=${encodeURIComponent(redirectPath)}` : ''}`
          }
        })

        if (error) throw error

        if (data.session) {
          await goToWorkspace(navigate, redirectPath)
          return
        }

        setSuccess(true)
        setMessage('Conta criada. Confirme seu e-mail e depois entre no painel. Se a confirmação de e-mail estiver desativada no Supabase, tente entrar agora.')
        return
      }

      if (mode === 'forgot') {
        const { error } = await supabase.auth.resetPasswordForEmail(normalizedEmail, {
          redirectTo: `${window.location.origin}/login?reset=1${redirectPath ? `&redirect=${encodeURIComponent(redirectPath)}` : ''}`
        })
        if (error) throw error

        setSuccess(true)
        setMessage('Se esse e-mail estiver cadastrado, você receberá um link para criar uma nova senha.')
        return
      }

      if (mode === 'new-password') {
        if (password.length < 8) {
          setMessage('Use uma senha com pelo menos 8 caracteres.')
          return
        }
        if (password !== confirmPassword) {
          setMessage('As duas senhas não são iguais.')
          return
        }

        const { error } = await supabase.auth.updateUser({ password })
        if (error) throw error

        setSuccess(true)
        setMessage('Senha atualizada com sucesso. Abrindo sua conta...')
        setTimeout(() => { void goToWorkspace(navigate, redirectPath) }, 700)
      }
    } catch (error) {
      const authError = error as { message?: string }
      setMessage(translateAuthError(authError.message || 'Não foi possível concluir a autenticação.'))
    } finally {
      setLoading(false)
    }
  }

  const title = mode === 'login'
    ? 'Entrar no painel'
    : mode === 'register'
      ? 'Criar primeiro acesso'
      : mode === 'forgot'
        ? 'Recuperar senha'
        : 'Criar nova senha'

  const subtitle = mode === 'login'
    ? 'Gerencie sua agenda, clientes e atendimentos.'
    : mode === 'register'
      ? 'Crie sua conta administrativa. Depois você cadastra sua empresa real.'
      : mode === 'forgot'
        ? 'Enviaremos um link de recuperação para o seu e-mail.'
        : 'Escolha uma nova senha segura para sua conta.'

  return (
    <main className="auth-page">
      <form className="auth-card" onSubmit={submit}>
        <div className="brand centered"><span className="brand-icon"><Scissors size={20}/></span> BarberAgenda</div>
        <div className="auth-icon">
          {mode === 'register' ? <UserPlus size={26}/> : mode === 'forgot' || mode === 'new-password' ? <KeyRound size={26}/> : <LockKeyhole size={26}/>}
        </div>
        <h1>{title}</h1>
        <p>{subtitle}</p>

        {mode !== 'new-password' && (
          <label>
            E-mail
            <input
              className="input"
              type="email"
              autoComplete="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              required
            />
          </label>
        )}

        {(mode === 'login' || mode === 'register' || mode === 'new-password') && (
          <label>
            {mode === 'new-password' ? 'Nova senha' : 'Senha'}
            <input
              className="input"
              type="password"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              value={password}
              onChange={e => setPassword(e.target.value)}
              minLength={mode === 'login' ? undefined : 8}
              required
            />
          </label>
        )}

        {(mode === 'register' || mode === 'new-password') && (
          <label>
            Confirmar senha
            <input
              className="input"
              type="password"
              autoComplete="new-password"
              value={confirmPassword}
              onChange={e => setConfirmPassword(e.target.value)}
              minLength={8}
              required
            />
          </label>
        )}

        <button className="button button-primary full" disabled={loading}>
          {loading
            ? 'Processando...'
            : mode === 'login'
              ? 'Entrar'
              : mode === 'register'
                ? 'Criar conta'
                : mode === 'forgot'
                  ? 'Enviar recuperação'
                  : 'Salvar nova senha'}
        </button>

        {message && <div className={`notice ${success ? 'success' : ''}`}>{message}</div>}

        <div className="auth-links">
          {mode === 'login' ? (
            <>
              {allowSignup && <button type="button" onClick={() => changeMode('register')}>Criar primeiro acesso</button>}
              <button type="button" onClick={() => changeMode('forgot')}>Esqueci minha senha</button>
            </>
          ) : (
            <button type="button" onClick={() => changeMode('login')}><ArrowLeft size={15}/> Voltar para o login</button>
          )}
        </div>
      </form>
    </main>
  )
}
