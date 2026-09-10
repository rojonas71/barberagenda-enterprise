# BarberAgenda 4.5.0 — Link Exclusivo por Empresa

## Objetivo

Cada empresa possui um endereço público exclusivo para receber agendamentos:

`/b/<slug>`

Exemplo:

`https://SEU-DOMINIO/b/barbearia-do-joao`

## O que foi atualizado

- Link público exclusivo por empresa.
- Slug normalizado no painel.
- Índice único case-insensitive no PostgreSQL.
- QR Code do link público no painel de Configurações.
- Copiar link.
- Compartilhar link usando Web Share API quando disponível.
- Abrir agenda pública em nova aba.
- Página pública `/b/:slug` mantida como ponto oficial de agendamento.
- Título do navegador personalizado com o nome da empresa.
- Página pública continua respeitando serviços, profissionais, horários, bloqueios e conflitos.
- Documentação SQL de integração.

## Fluxo

Empresa → Configurações → Slug público → Link exclusivo → QR Code → Cliente → `/b/:slug` → Agendamento.

## SQL

Execute:

`supabase/link-publico-v4.5.0.sql`

antes de disponibilizar a funcionalidade em produção.

### Atenção aos slugs existentes

O índice `ux_businesses_slug_public` exige que não existam duas empresas com o mesmo slug, ignorando diferença entre maiúsculas e minúsculas. Se sua base possuir duplicidades, ajuste os slugs antes de executar a migration.

## QR Code

O QR Code exibido no painel é renderizado por um serviço externo de geração de QR. O conteúdo codificado é somente o link público da empresa.

O agendamento continua sendo processado pelo BarberAgenda/Supabase; o QR não contém credenciais ou dados privados.

## Segurança

- Não expor service_role/secret no frontend.
- Manter RLS nas tabelas públicas.
- O slug identifica apenas a página pública; autorização de dados privados continua dependendo das políticas RLS.
