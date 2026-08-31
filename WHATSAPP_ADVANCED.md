# BarberAgenda — WhatsApp PRO Advanced

Integração server-side com WhatsApp Cloud API, Supabase Edge Functions, Vault, Realtime e Cron.

## O que foi implementado

- `/painel/whatsapp` com configuração e observabilidade.
- Access Token armazenado criptografado no Supabase Vault.
- `whatsapp-admin`: configura token, testa conexão, envia mensagens manuais para a fila e permite retry/cancelamento.
- `whatsapp-worker`: processa fila com retry exponencial, gera lembretes e envia pela Cloud API.
- `whatsapp-webhook`: valida assinatura HMAC, recebe status e mensagens do WhatsApp.
- Fila persistente com `queued`, `processing`, `sent`, `delivered`, `read`, `failed`, `cancelled`.
- Realtime de fila e caixa de entrada.
- Automação por evento de agendamento: confirmação, reagendamento e cancelamento.
- Lembretes programados.
- Multiempresa por `business_id` e `Phone Number ID`.
- RLS para impedir uma empresa de acessar dados de outra.

## 1. Banco

No Supabase → SQL Editor, execute:

```text
supabase/whatsapp-advanced-upgrade.sql
```

No final, todos os itens de diagnóstico devem retornar `OK`.

## 2. Publicar as Edge Functions

```powershell
npx supabase login
npx supabase link --project-ref SEU_PROJECT_REF
npx supabase functions deploy whatsapp-admin
npx supabase functions deploy whatsapp-worker --no-verify-jwt
npx supabase functions deploy whatsapp-webhook --no-verify-jwt
```

O `supabase/config.toml` já marca webhook e worker como públicos no gateway; cada um aplica sua própria verificação.

## 3. Secrets server-side

Crie valores longos e aleatórios para `WHATSAPP_VERIFY_TOKEN` e `WHATSAPP_WORKER_SECRET`.

```powershell
npx supabase secrets set APP_ORIGIN=https://SEU-SITE.netlify.app
npx supabase secrets set WHATSAPP_VERIFY_TOKEN=SEU_VERIFY_TOKEN_FORTE
npx supabase secrets set WHATSAPP_WORKER_SECRET=SEU_WORKER_SECRET_FORTE
npx supabase secrets set WHATSAPP_APP_SECRET=SEU_META_APP_SECRET
```

Nunca use Access Token da Meta em `VITE_*` ou no Netlify frontend.

## 4. Configurar uma empresa

Acesse:

```text
/painel/whatsapp
```

Preencha:

- Phone Number ID;
- WhatsApp Business Account ID;
- versão da Graph API usada pelo seu app Meta;
- idioma (`pt_BR` normalmente);
- nomes dos templates aprovados;
- tempo do lembrete.

Cole o Access Token no card **Access Token** e salve. O navegador envia para `whatsapp-admin`, que o grava no Vault. O token não volta para o React depois disso.

## 5. Templates recomendados

Crie e aprove na Meta quatro templates transacionais. O código envia 6 parâmetros na mesma ordem:

1. nome do cliente;
2. nome da empresa;
3. data;
4. horário;
5. serviço;
6. profissional.

Exemplo conceitual de confirmação:

```text
Olá {{1}}! Seu horário na {{2}} está confirmado para {{3}} às {{4}}.
Serviço: {{5}}.
Profissional: {{6}}.
```

Use os nomes reais aprovados nos campos da tela. Não dependa dos nomes de exemplo.

## 6. Webhook Meta

Callback URL:

```text
https://SEU_PROJECT_REF.supabase.co/functions/v1/whatsapp-webhook
```

Verify Token: use exatamente o valor de `WHATSAPP_VERIFY_TOKEN`.

Depois, assine os campos/eventos necessários de mensagens/status no painel Meta. O POST valida `X-Hub-Signature-256` usando `WHATSAPP_APP_SECRET` antes de tocar no banco.

## 7. Worker automático

Abra:

```text
supabase/whatsapp-cron-setup.sql
```

Substitua:

- `https://CHANGE_ME.supabase.co`;
- `CHANGE_ME_PUBLISHABLE_KEY`;
- `CHANGE_ME_LONG_RANDOM_SECRET` (o mesmo `WHATSAPP_WORKER_SECRET`).

Execute no SQL Editor. O Cron chama o worker a cada minuto. Supabase Cron + `pg_net` é o componente que mantém lembretes e fila funcionando mesmo sem nenhum navegador aberto.

## 8. GitHub CI/CD

O workflow existente já publica todas as funções quando `supabase/functions/**` muda, desde que os secrets do GitHub estejam configurados:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`

O Access Token do WhatsApp não deve ser colocado nos GitHub Secrets quando você usa a configuração multiempresa com Vault.

## 9. Fluxo de produção

```text
Agendamento criado/alterado
        ↓
Trigger PostgreSQL
        ↓
whatsapp_message_queue
        ↓
Supabase Cron (1 min)
        ↓
whatsapp-worker
        ↓
WhatsApp Cloud API
        ↓
Webhook Meta
        ↓
sent → delivered → read
        ↓
Realtime no painel
```

## 10. Segurança

- token da Cloud API: Vault;
- App Secret e Verify Token: Edge Function Secrets;
- frontend: apenas publishable key do Supabase;
- RLS em configurações, fila e inbox;
- webhook com HMAC;
- worker com secret independente;
- retries limitados;
- deduplicação de eventos de agendamento;
- deduplicação de webhooks por SHA-256;
- `service_role`/secret key nunca vai para o bundle Vite.

## 11. Mensagem manual

O painel permite colocar texto livre na fila. A aceitação dessa mensagem depende das regras vigentes do WhatsApp/Meta para conversas. Para automações iniciadas pela empresa, prefira templates aprovados.

## 12. Diagnóstico

### Mensagens ficam `queued`

Confira o Cron e os secrets do worker.

### Mensagens ficam `failed`

Abra `/painel/whatsapp`; a coluna mostra `last_error`. Verifique token, Phone Number ID, Graph API e template.

### Webhook não valida

Confira `WHATSAPP_VERIFY_TOKEN`. Se o GET valida mas o POST falha, confira `WHATSAPP_APP_SECRET`.

### Template falha

Confirme nome, idioma e quantidade/ordem dos parâmetros exatamente como aprovado na Meta.
