const required = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY']
const missing = required.filter((key) => !process.env[key]?.trim())

if (missing.length) {
  console.error(`\n❌ Variáveis obrigatórias ausentes: ${missing.join(', ')}`)
  console.error('Configure-as no Netlify ou em .env.local antes do build de produção.\n')
  process.exit(1)
}

const url = process.env.VITE_SUPABASE_URL
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url)) {
  console.error('\n❌ VITE_SUPABASE_URL não parece uma URL válida do Supabase.\n')
  process.exit(1)
}

if (!process.env.VITE_SUPABASE_ANON_KEY.startsWith('sb_publishable_')) {
  console.warn('\n⚠️ VITE_SUPABASE_ANON_KEY não usa o prefixo sb_publishable_. Confirme se é a chave pública correta.\n')
}

console.log('✅ Ambiente de produção validado.')
