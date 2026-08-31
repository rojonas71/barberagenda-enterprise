# BarberAgenda Enterprise 4.0

## Objetivo

A versão 4.0 consolida a base Advanced e reduz a dependência de hotfixes individuais. O foco é operação real em barbearias e salões, com banco Supabase consistente, mobile/PC e módulos adicionais de ocupação e estoque.

## Novas rotas

- `/painel/lista-espera` — fila de clientes aguardando vaga.
- `/painel/estoque` — produtos, consumíveis, saldo e estoque mínimo.
- `/painel/diagnostico` — checagem de tabelas, colunas e RPCs.

## Lista de espera

A página pública pode oferecer entrada na lista de espera quando uma combinação de serviço, profissional e data estiver sem horários. O painel acompanha `waiting`, `contacted`, `booked`, `cancelled` e `expired` em tempo real.

## Estoque

O estoque registra produto, SKU, unidade, saldo, mínimo, custo e preço de venda. Ajustes usam a RPC `adjust_inventory_stock()` para atualizar o saldo de forma atômica e registrar o movimento.

## Políticas de agenda

Novas configurações em `businesses`:

- `booking_enabled`
- `auto_confirm_bookings`
- `allow_waitlist`
- `public_booking_message`
- `booking_advance_days`
- `min_booking_notice_minutes`
- `cancellation_notice_hours`

## Diagnóstico

A RPC `app_schema_health()` verifica os principais objetos que o frontend utiliza. Isso facilita identificar instalações incompletas sem esperar um erro do PostgREST ocorrer em cada tela.

## Migração mestre

Para um banco existente, execute somente:

```text
supabase/MASTER_PRODUCTION_UPGRADE.sql
```

O arquivo consolida a camada Advanced, Admin Dev, reparos de onboarding, `system_settings`, auditoria, RPCs globais, colunas de agenda e módulos Enterprise 4.0.

Para um projeto Supabase novo, execute:

```text
supabase/schema.sql
```

## PWA

A aplicação inclui `manifest.webmanifest`, ícone e service worker. Em produção HTTPS, navegadores compatíveis podem instalar o painel como aplicativo. Dados dinâmicos do Supabase continuam dependendo de conexão; o service worker prioriza somente o shell e assets estáticos.

## Sem WhatsApp

A versão Enterprise 4.0 não inclui Meta API, webhook, fila do WhatsApp ou tokens relacionados.
