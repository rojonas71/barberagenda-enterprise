# BarberAgenda — Admin Dev / Super Admin

O Admin Dev é um painel global separado do painel de cada barbearia/salão.

## Rotas

- `/dev-admin/login` — login exclusivo do Dev Console
- `/dev-admin` — dashboard global
- `/dev-admin/empresas` — tenants, suspensão/ativação, plano e métricas
- `/dev-admin/usuarios` — usuários Auth, bloqueio, desbloqueio e recuperação de senha
- `/dev-admin/planos` — catálogo de planos
- `/dev-admin/suporte` — tickets globais
- `/dev-admin/saude` — erros, incidentes e observabilidade
- `/dev-admin/auditoria` — trilhas de auditoria
- `/dev-admin/configuracoes` — manutenção, novos cadastros e equipe Dev

## 1. Banco

Em um banco que já possui a versão PRO Advanced, execute:

```sql
supabase/dev-admin-upgrade.sql
```

Em uma instalação nova, `supabase/schema.sql` já contém o Admin Dev.

## 2. Criar o primeiro Super Admin

Crie a conta normalmente em Supabase > Authentication > Users e depois execute `supabase/setup-dev-admin.sql`, trocando o e-mail placeholder pelo e-mail real.

O navegador nunca recebe `SUPABASE_SERVICE_ROLE_KEY`.

## 3. Edge Function de administração do Auth

As operações de bloquear/desbloquear usuário e enviar recuperação de senha usam:

```text
supabase/functions/dev-user-admin/index.ts
```

Com Supabase CLI:

```bash
npx supabase login
npx supabase link --project-ref SEU_PROJECT_REF
npx supabase functions deploy dev-user-admin
```

Opcionalmente configure a origem permitida:

```bash
npx supabase secrets set APP_ORIGIN=https://seu-dominio.com
```

As secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidas ao ambiente das Edge Functions pelo Supabase. Não coloque a service role no Vite/React.

## 4. Perfis do Admin Dev

- `super_admin`: acesso global completo.
- `support`: suporte + ações de Auth permitidas, exceto contas Dev.
- `billing`: planos e assinaturas.
- `ops`: empresas, suspensão, saúde e incidentes.
- `read_only`: leitura global sem mutações administrativas.

## 5. Segurança

- RLS ativado nas tabelas administrativas.
- `developer_admins` separado de `business_members`.
- campos `platform_status`, `suspended_at` e `suspended_reason` protegidos por trigger.
- empresas suspensas não aparecem no agendamento público.
- ações globais são registradas em `developer_audit_logs`.
- ações em Supabase Auth passam por Edge Function server-side.
- Admin de suporte não consegue alterar o Auth de outro Admin Dev.
- a própria conta não pode se bloquear pelo console.

## 6. Modo manutenção

Em `/dev-admin/configuracoes`, ative `maintenance_mode` para interromper temporariamente o app público e os painéis de empresas. O Dev Console continua acessível para recuperação operacional.

## 7. Controle de cadastros

`allow_new_signups=false` remove o botão de primeiro acesso e bloqueia novas contas pelo fluxo do BarberAgenda.

## 8. Central de Suporte da empresa

Os clientes da plataforma possuem `/painel/suporte` para abrir e acompanhar chamados. Os tickets aparecem em tempo real em `/dev-admin/suporte`.
