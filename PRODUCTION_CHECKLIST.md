# Checklist de produção — BarberAgenda PRO

## Git/GitHub
- [ ] `.env` não está versionado
- [ ] `package-lock.json` foi gerado e commitado
- [ ] branch `main` protegida
- [ ] CI obrigatório antes de merge
- [ ] Dependabot habilitado

## Netlify
- [ ] GitHub conectado
- [ ] Production branch = `main`
- [ ] Build = `npm run build:production`
- [ ] Publish = `dist`
- [ ] `VITE_SUPABASE_URL` configurada
- [ ] `VITE_SUPABASE_ANON_KEY` configurada
- [ ] variáveis também disponíveis em Deploy Previews, se usados
- [ ] HTTPS ativo
- [ ] SPA refresh sem 404

## Supabase
- [ ] Site URL aponta para produção
- [ ] Redirect URLs de produção configuradas
- [ ] localhost autorizado para desenvolvimento
- [ ] preview Netlify autorizado se necessário
- [ ] RLS habilitado nas tabelas sensíveis
- [ ] RPCs e hotfixes aplicados
- [ ] Realtime configurado
- [ ] Admin Dev funcionando
- [ ] Edge Function `dev-user-admin` publicada
- [ ] Service Role não está no frontend

## Aplicação
- [ ] cadastro/login/reset testados
- [ ] onboarding testado
- [ ] agenda pública testada
- [ ] CRUD testado
- [ ] clientes/CRM testados
- [ ] financeiro/relatórios testados
- [ ] mobile testado
- [ ] desktop testado
- [ ] Dev Admin testado
- [ ] sem erros críticos no console


## Enterprise 4.0

- [ ] Em banco existente, executar `supabase/MASTER_PRODUCTION_UPGRADE.sql`.
- [ ] Abrir `/painel/diagnostico` e confirmar todos os itens como `OK`.
- [ ] Testar lista de espera pública quando uma data estiver sem horários.
- [ ] Testar CRUD e ajuste de estoque em `/painel/estoque`.
- [ ] Testar `booking_enabled`, `auto_confirm_bookings` e `allow_waitlist` em Configurações.
- [ ] Confirmar que `/manifest.webmanifest`, `/icon.svg` e `/sw.js` respondem em produção.
- [ ] Confirmar que o projeto não contém integração WhatsApp.
