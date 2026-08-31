# BarberAgenda — versão sem WhatsApp

Esta versão remove integralmente a integração com WhatsApp/Meta do aplicativo.

Removido do frontend:
- rota `/painel/whatsapp`;
- item WhatsApp do menu;
- página de mensageria;
- links `wa.me` no CRM;
- textos/campos identificados como WhatsApp (agora `Telefone`).

Removido do backend:
- Edge Functions `whatsapp-admin`, `whatsapp-worker` e `whatsapp-webhook`;
- helper `_shared/whatsapp.ts`;
- configuração de funções WhatsApp no `supabase/config.toml`;
- objetos WhatsApp do `supabase/schema.sql`;
- migrations, Cron e verificações específicas da integração.

Se a integração WhatsApp Advanced já foi instalada no projeto Supabase, execute opcionalmente:

```text
supabase/remove-whatsapp.sql
```

Esse script remove somente objetos exclusivos do WhatsApp e não apaga empresas, clientes, agendamentos, financeiro ou Admin Dev.
