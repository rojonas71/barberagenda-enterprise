# BarberAgenda 4.3.0 — CRM Offline First

## O que mudou

O módulo Clientes agora funciona como CRM offline-first:

- leitura do CRM usando o cache IndexedDB já existente no BarberAgenda;
- criação e edição de clientes sem internet;
- notas internas adicionadas à fila offline;
- sincronização automática ao recuperar conexão;
- indicador de CRM online/offline;
- contador de alterações pendentes;
- filtros de clientes inativos em 30, 60 e 90 dias;
- mensagem de reativação pelo WhatsApp;
- opção de copiar a mensagem quando estiver sem internet;
- registro do último contato comercial;
- exportação CSV com último contato do CRM;
- atualização otimista para o usuário ver o que acabou de salvar mesmo offline.

## Segurança

O Supabase continua sendo a fonte de verdade.
O cache local serve para continuidade operacional.
RLS continua obrigatório nas tabelas expostas.

## SQL obrigatório

Execute:

`supabase/crm-offline-v4.3.0.sql`

## Observação sobre WhatsApp

Abrir/enviar no WhatsApp precisa de internet.
Sem conexão, o CRM permite copiar a mensagem e registrar a ação localmente.
