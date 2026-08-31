# BarberAgenda Enterprise 4.0

Sistema profissional de gestão para barbearias e salões, com agenda em tempo real, CRM, financeiro, equipe, permissões, lista de espera, estoque, diagnóstico técnico e Admin Dev.

## Stack

- React 18 + TypeScript + Vite
- Supabase Auth
- PostgreSQL
- Row Level Security (RLS)
- Supabase Realtime
- React Router
- Lucide Icons

## Atualização Enterprise 4.0

Além dos módulos Advanced, esta versão inclui:

- lista de espera pública e administrativa;
- estoque de produtos e consumíveis;
- alertas de estoque mínimo;
- políticas de agendamento configuráveis;
- agendamento automático ou pendente;
- pausa da agenda pública;
- mensagem personalizada na página de agendamento;
- diagnóstico de tabelas, colunas e RPCs;
- `MASTER_PRODUCTION_UPGRADE.sql` para bancos existentes;
- PWA instalável no celular;
- suporte completo a mobile e PC;
- sem integração WhatsApp.

### Atualizar um banco existente

Em vez de executar vários hotfixes separadamente, abra **Supabase → SQL Editor** e execute:

```text
supabase/MASTER_PRODUCTION_UPGRADE.sql
```

Depois acesse:

```text
/painel/diagnostico
```

para validar a estrutura esperada pelo frontend.

## Principais módulos

### Dashboard executivo

Rota:

```text
/painel/dashboard
```

Mostra:

- faturamento do mês;
- resultado estimado;
- despesas;
- comissões estimadas;
- total de agendamentos;
- taxa de conclusão;
- no-show;
- base de clientes;
- próximos atendimentos;
- serviços que mais faturam;
- performance por profissional.

### Agenda

Rota:

```text
/painel
```

Inclui CRUD completo:

- criar agendamento manual;
- editar cliente, serviço, profissional, data e horário;
- concluir atendimento;
- cancelar;
- marcar `no_show`;
- excluir;
- desconto;
- valor final;
- status do pagamento;
- forma de pagamento;
- prevenção de sobreposição;
- validação de jornada;
- validação de bloqueios;
- atualização em tempo real.

### CRM de clientes

Rota:

```text
/painel/clientes
```

Inclui:

- cadastro automático via agendamento;
- CRUD manual;
- busca e filtros;
- tags;
- aniversários;
- VIP;
- recorrentes;
- inativos;
- no-show;
- total gasto;
- ticket médio;
- histórico;
- profissional favorito;
- serviço favorito;
- notas internas;
- bloqueio de cliente;
- consentimento de marketing;
- exportação CSV.

### Serviços

```text
/painel/servicos
```

- criar;
- editar;
- ativar/desativar;
- excluir quando não houver dependências;
- preço;
- duração;
- descrição;
- Realtime.

### Profissionais

```text
/painel/profissionais
```

- CRUD;
- foto;
- bio;
- status ativo/inativo;
- comissão padrão em percentual;
- integração com agenda e relatórios.

### Disponibilidade avançada

```text
/painel/disponibilidade
```

- horário semanal da empresa;
- jornada específica por profissional;
- dias fechados;
- férias;
- feriados;
- bloqueios de dia inteiro;
- bloqueios por intervalo;
- bloqueios de toda a equipe;
- bloqueios por profissional;
- sincronização em tempo real.

A página pública `/b/:slug` respeita automaticamente:

- horário da empresa;
- jornada do profissional;
- bloqueios;
- duração do serviço;
- horários já ocupados;
- antecedência mínima;
- limite de dias futuros.

### Financeiro

```text
/painel/financeiro
```

- faturamento de atendimentos concluídos;
- entradas extras;
- despesas;
- comissões estimadas;
- resultado estimado;
- meios de pagamento;
- CRUD de lançamentos financeiros;
- Realtime.

### Relatórios

```text
/painel/relatorios
```

- período personalizado;
- faturamento;
- ticket médio;
- taxa de conclusão;
- cancelamentos;
- no-show;
- ranking de serviços;
- ranking de profissionais;
- resumo por status;
- exportação CSV.

### Equipe e RBAC

```text
/painel/equipe
```

Papéis disponíveis:

- `owner` — proprietário;
- `manager` — gerente;
- `receptionist` — recepção;
- `professional` — profissional.

Recursos:

- convite por e-mail/link;
- token temporário;
- validade de 7 dias;
- alteração de função;
- ativar/desativar membro;
- vincular usuário do tipo `professional` a um profissional do cadastro;
- proteção do papel `owner`;
- RLS por função.

Convites são aceitos em:

```text
/convite/:token
```

### Auditoria

```text
/painel/auditoria
```

Registra operações importantes em:

- agenda;
- clientes;
- serviços;
- profissionais;
- financeiro;
- bloqueios;
- equipe.

O histórico registra:

- operação (`INSERT`, `UPDATE`, `DELETE`);
- usuário;
- tabela;
- registro;
- data/hora;
- dados anteriores e posteriores no banco.

### Configurações

```text
/painel/configuracoes
```

- nome;
- telefone;
- endereço;
- logo;
- slug público;
- horário padrão;
- intervalo da agenda;
- timezone;
- quantos dias no futuro podem ser agendados;
- antecedência mínima;
- prazo de cancelamento;
- exclusão permanente da empresa pelo proprietário.

## Segurança

A versão Advanced adiciona regras importantes no banco:

- RLS por empresa;
- RBAC por função;
- profissional vinculado acessa somente os agendamentos vinculados a ele;
- recepção não altera serviços/profissionais;
- financeiro restrito a proprietário/gerente;
- auditoria restrita a proprietário/gerente;
- owner não pode ser removido ou rebaixado acidentalmente;
- preço enviado pelo cliente na agenda pública não é confiado pelo backend;
- o banco recalcula o preço público a partir do serviço;
- bloqueios públicos usam um espelho seguro, sem expor o motivo interno;
- disponibilidade pública não expõe nome, telefone ou observações de clientes.

Nunca use uma chave `service_role` no frontend.

## Variáveis de ambiente

Crie `.env`:

```env
VITE_SUPABASE_URL=https://SEU-PROJETO.supabase.co
VITE_SUPABASE_ANON_KEY=SUA_CHAVE_PUBLICAVEL
```

O arquivo `.env` está no `.gitignore`.

## Instalação nova

No Supabase → SQL Editor, execute:

```text
supabase/schema.sql
```

Depois:

```bash
npm install
npm run dev
```

Abra:

```text
http://localhost:5173/login
```

Crie sua conta e finalize `/onboarding`.

Nenhum dado fictício é criado.

## Atualizando o banco existente

Para quem já está usando a versão CRUD anterior, mantenha as migrações anteriores aplicadas e execute por último:

```text
supabase/advanced-professional-upgrade.sql
```

A atualização cria:

- `business_hours`;
- `professional_hours`;
- `schedule_blocks`;
- `availability_blocks`;
- `financial_transactions`;
- `business_invites`;
- `audit_logs`;
- novas colunas financeiras de `appointments`;
- comissão de `professionals`;
- novas configurações de `businesses`;
- novos campos de `business_members`;
- funções e políticas RLS avançadas.

## Ordem completa para uma instalação antiga

Se a base começou nas primeiras versões deste projeto, a ordem recomendada é:

```text
supabase/realtime-upgrade.sql
supabase/clients-upgrade.sql
supabase/clients-pro-upgrade.sql
supabase/production-no-demo-upgrade.sql
supabase/crud-upgrade.sql
supabase/advanced-professional-upgrade.sql
```

Em uma instalação nova, não rode as migrações individualmente: use apenas `schema.sql`.

## Build de produção

```bash
npm install
npm run build
```

A saída será gerada em:

```text
dist/
```

## Netlify

O projeto já inclui:

```text
netlify.toml
public/_redirects
```

Configure no Netlify:

- Build command: `npm run build`
- Publish directory: `dist`
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

## Vercel

O projeto inclui `vercel.json` para manter as rotas SPA funcionando.

Configure as mesmas variáveis de ambiente no projeto Vercel.

## Realtime

O sistema utiliza Realtime em:

- agendamentos;
- disponibilidade pública;
- bloqueios públicos seguros;
- clientes;
- notas internas;
- serviços;
- profissionais;
- empresa;
- horários semanais;
- financeiro;
- convites.

## Estrutura principal

```text
src/
  components/
    AdminSidebar.tsx
  lib/
    supabase.ts
  pages/
    AdminPage.tsx
    AuditPage.tsx
    AvailabilityPage.tsx
    BookingPage.tsx
    ClientsPage.tsx
    DashboardPage.tsx
    FinancePage.tsx
    HomePage.tsx
    InvitePage.tsx
    LoginPage.tsx
    OnboardingPage.tsx
    ProfessionalsPage.tsx
    ReportsPage.tsx
    ServicesPage.tsx
    SettingsPage.tsx
    TeamPage.tsx
  App.tsx
  main.tsx
  styles.css
supabase/
  schema.sql
  advanced-professional-upgrade.sql
```

## Observação sobre validação neste ambiente

A sintaxe dos arquivos TypeScript/TSX foi validada localmente. A instalação das dependências via registro npm não concluiu neste ambiente, portanto execute `npm install && npm run build` na sua máquina para a validação final com as dependências reais.

---

# Admin Dev / Super Admin

Esta versão inclui um **Dev Console global** separado do painel das empresas.

Principais recursos:

- visão global de empresas, usuários, agendamentos e GMV;
- status de tenant: ativo, suspenso e arquivado;
- catálogo de planos e assinaturas;
- usuários Supabase Auth com bloqueio/desbloqueio e recuperação por e-mail;
- central de suporte em tempo real;
- observabilidade com logs de erro e incidentes;
- auditoria global;
- modo manutenção;
- controle de novos cadastros;
- múltiplos papéis de Admin Dev;
- Edge Function para operações privilegiadas de Auth;
- nenhuma `service_role` exposta no frontend.

Para ativar, execute `supabase/dev-admin-upgrade.sql`, crie o primeiro Super Admin com `supabase/setup-dev-admin.sql` e consulte `ADMIN_DEV.md` para a implantação completa.

## Hotfix: erro `create_business_for_current_user` / schema cache

Se o onboarding exibir `Could not find the function public.create_business_for_current_user(...) in the schema cache`, execute no **Supabase → SQL Editor**:

```text
supabase/fix-onboarding-rpc.sql
```

O script recria exatamente a assinatura RPC usada pelo frontend, concede `EXECUTE` para usuários autenticados e envia `NOTIFY pgrst, 'reload schema'`. Ele não apaga dados existentes.

## Responsividade Mobile + PC

Esta versão inclui layout responsivo profissional para celular, tablet, notebook e desktop:

- menu lateral em drawer no mobile para Painel e Dev Admin;
- sidebar fixa no desktop;
- safe-area para iPhone/notch;
- tabelas com rolagem horizontal touch e primeira coluna fixa;
- botões com área mínima de toque;
- formulários e grids adaptativos;
- agenda pública otimizada para telas pequenas;
- cards/KPIs 4 colunas no desktop, 2/1 colunas no mobile;
- suporte a telas largas (1440px+);
- prevenção de overflow horizontal.



## Versao sem WhatsApp

Esta distribuicao nao possui integracao com WhatsApp, Meta Webhooks, WhatsApp Cloud API, fila de mensagens ou secrets relacionados.
Os campos de contato usam **telefone**. Para bancos que receberam anteriormente a integracao WhatsApp Advanced, execute opcionalmente `supabase/remove-whatsapp.sql` para remover apenas os objetos exclusivos dessa integracao.

## Admin Dev Enterprise

O Dev Console inclui módulos avançados de Empresas, Usuários, Planos, Suporte, Saúde, Auditoria e Configurações com KPIs, filtros, detalhes, exportação CSV e RBAC.

Documentação: `ADMIN_DEV_ENTERPRISE.md`

Diagnóstico do Supabase: `supabase/DEV_ADMIN_ENTERPRISE_CHECK.sql`
