# BarberAgenda PRO — Deploy GitHub → Netlify → Supabase

## Arquitetura

- **GitHub**: código, histórico, pull requests e CI.
- **GitHub Actions / CI**: valida TypeScript e bundle Vite em push/PR.
- **Netlify**: build e deploy automático do frontend React/Vite.
- **Supabase**: Auth, Postgres, RLS, Realtime, RPCs e Edge Functions.
- **Supabase Edge Functions**: deploy automático opcional via GitHub Actions.

## 1. Preparar o projeto local

```powershell
npm install
npm run typecheck
npm run build
```

O primeiro `npm install` deve gerar `package-lock.json`. Versione esse arquivo para permitir `npm ci` determinístico no CI e no ambiente de build.

## 2. Ambiente local

Use `.env.local` (ignorado pelo Git):

```env
VITE_SUPABASE_URL=https://SEU_PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_SUA_CHAVE_PUBLICA
```

Nunca coloque `SUPABASE_SERVICE_ROLE_KEY` em variáveis `VITE_*`.

## 3. GitHub

Crie um repositório vazio e rode:

```powershell
git init
git add .
git commit -m "feat: BarberAgenda PRO production"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/barberagenda.git
git push -u origin main
```

Se `origin` já existir:

```powershell
git remote -v
git remote set-url origin https://github.com/SEU_USUARIO/barberagenda.git
git push -u origin main
```

## 4. Netlify

Importe o repositório GitHub em **Add new project → Import an existing project**.

O `netlify.toml` já define:

- build: `npm run build:production`
- publish: `dist`
- Node 20
- fallback SPA para `index.html`
- headers de segurança
- cache longo para `/assets/*`
- HTML sem cache persistente

### Environment variables

No Netlify, configure para Production e Deploy Previews:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Após salvar, faça novo deploy.

## 5. Supabase Auth

Em **Authentication → URL Configuration**:

- **Site URL**: URL oficial de produção do Netlify ou domínio próprio.
- **Redirect URLs**:
  - `http://localhost:5173/**`
  - URL oficial de produção
  - URL de preview do Netlify, se usar Deploy Previews.

Exemplo de preview:

```text
https://**--SEU_SITE.netlify.app/**
```

Em produção, prefira URLs exatas para os fluxos críticos.

## 6. Edge Function do Admin Dev

O frontend no Netlify **não** deve receber a Service Role Key.

A função `supabase/functions/dev-user-admin` roda no Supabase. Para deploy manual:

```powershell
npx supabase login
npx supabase link --project-ref SEU_PROJECT_REF
npx supabase functions deploy dev-user-admin
```

Para deploy automático pelo GitHub, crie estes **Repository Secrets**:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`

O workflow `.github/workflows/deploy-supabase-functions.yml` publica as funções quando houver alteração em `supabase/functions/**` na `main`.

## 7. CI do GitHub

O workflow `.github/workflows/ci.yml` roda em pushes e pull requests para `main` e verifica:

1. instalação das dependências;
2. que `.env` não foi versionado;
3. TypeScript;
4. build Vite.

Recomendação: em **GitHub → Settings → Branches / Rulesets**, proteja `main` e exija o check de CI antes de merge.

## 8. Deploy Preview

Use Pull Requests para alterações maiores. O Netlify pode gerar uma URL de preview por PR. Configure as variáveis do Supabase também para o contexto de Deploy Preview e autorize o padrão de URL correspondente no Supabase Auth.

## 9. Domínio próprio

No Netlify:

1. Domain management;
2. Add a domain;
3. configure DNS;
4. aguarde HTTPS;
5. troque o **Site URL** do Supabase para o domínio oficial;
6. adicione o domínio às Redirect URLs.

## 10. Pós-deploy

Valide:

- `/`
- `/login`
- `/onboarding`
- `/painel/dashboard`
- `/painel/clientes`
- `/dev-admin/login`
- `/dev-admin`
- rota pública `/b/<slug>`
- refresh direto em rotas internas (não deve dar 404)
- criação de conta / login / reset de senha
- criação de empresa
- CRUD
- Realtime em duas abas
- Edge Function do Admin Dev
- console do navegador sem erros
- visual mobile e desktop

## 11. Fluxo diário

```powershell
git checkout -b feat/minha-alteracao
# alterar código
npm run typecheck
npm run build
git add .
git commit -m "feat: descrição"
git push -u origin feat/minha-alteracao
```

Abra PR → CI → Deploy Preview → revisar → merge em `main` → Netlify publica produção automaticamente.

## 12. Rollback

Se uma versão quebrar, use o histórico de Deploys do Netlify para publicar novamente um deploy anterior e reverta o commit no GitHub. Para mudanças de banco, use migrações reversíveis/planejadas; não dependa do rollback do frontend para desfazer schema.
