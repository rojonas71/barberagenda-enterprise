# BarberAgenda 4.4.0 — Agenda Offline First + Realtime

A agenda administrativa agora trabalha em modelo Offline First sem remover o Supabase como fonte de verdade.

## Entregue
- Agenda por dia.
- Filtro por profissional.
- Criação, edição e exclusão de agendamento.
- Alteração de status: pending, confirmed, completed, cancelled e no_show.
- UUID local com `crypto.randomUUID()` para novos registros offline.
- Indicador Online/Offline.
- Contador da fila de sincronização pendente.
- Realtime do Supabase para `appointments`, `services` e `professionals`.
- Recarregamento automático após retorno da conexão/sincronização.
- `updated_at` mantido no PostgreSQL por trigger.
- Conflitos de horário protegidos no PostgreSQL; a interface traduz os erros mais importantes.
- `no_show` deixa de ocupar disponibilidade.

## Como funciona offline

1. A interface mantém os dados já carregados no cache local.
2. Inserções/alterações/exclusões usam a camada `src/lib/offline.ts`.
3. Quando não existe conexão, a mutação é colocada no IndexedDB.
4. O registro criado recebe UUID antes da fila, evitando identidade temporária.
5. Ao voltar a internet, a fila é reenviada automaticamente.
6. O Realtime/reload atualiza a agenda com o estado confirmado pelo servidor.

## Conflito de horário

O navegador pode mostrar um agendamento otimista enquanto estiver offline. Isso não significa que o horário está definitivamente confirmado.
Ao sincronizar, PostgreSQL continua sendo a autoridade através do trigger `prevent_appointment_overlap`. Se outro atendimento ocupar o mesmo intervalo, a gravação é rejeitada com `appointments_no_overlap`.

## SQL

Execute `supabase/agenda-offline-realtime-v4.4.0.sql` no SQL Editor do projeto Supabase.

O SQL:
- adiciona `updated_at`;
- garante `no_show`;
- recria a proteção contra sobreposição;
- cria índices para a agenda;
- garante a tabela `appointments` na publicação `supabase_realtime` sem alterar a schema interna `realtime`;
- mantém RLS habilitado.

## Validação local

```powershell
npm install
npm run typecheck
npm run build
```

Depois publique no Netlify/GitHub conforme o fluxo existente.
