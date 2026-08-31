# BarberAgenda Enterprise V4 — Offline First

Esta versão adiciona operação offline ao PWA.

## O que funciona sem internet

- O aplicativo já visitado pode abrir sem Wi-Fi/dados móveis.
- Assets do Vite ficam em Cache Storage via Service Worker.
- Consultas REST do Supabase já carregadas ficam em IndexedDB e podem ser reutilizadas offline.
- RPCs de leitura conhecidos (`get_*`, `dev_list_*`, dashboard/health/schema) também possuem fallback local.
- Sessão já existente pode liberar a interface offline usando a sessão local do Supabase.
- Alterações REST feitas sem conexão entram em fila local e são reenviadas quando a internet volta.
- Agendamento público mostra explicitamente "Agendamento salvo offline" e não afirma confirmação antes da sincronização.
- Lista de espera pode ser salva offline.
- Indicador global mostra Online / Offline / pendências / Sincronizando.

## Autoridade dos dados

O Supabase continua sendo a autoridade final. Uma operação salva offline não é considerada confirmada pelo servidor até sincronizar. Isso é especialmente importante em horários de agenda: outro cliente pode ocupar o mesmo horário antes da reconexão.

## Segurança

- Nenhuma `service_role` ou secret key é armazenada no PWA.
- A fila remove `Authorization` e `apikey` antes de persistir a requisição.
- Ao sincronizar, o sistema usa o token atual da sessão e a publishable key configurada no frontend.
- Cache de leitura é particionado pela identidade (`sub`) extraída do token para evitar misturar dados de usuários diferentes no mesmo navegador.

## Arquivos principais

- `src/lib/offline.ts` — IndexedDB, cache resiliente, fila e sincronização.
- `src/components/OfflineStatus.tsx` — indicador global de conexão e pendências.
- `src/lib/supabase.ts` — transport offline-first do Supabase.
- `public/sw.js` — app shell e assets offline.
- `src/pages/BookingPage.tsx` — confirmação segura para agendamentos offline.

## Como testar

1. Faça deploy e abra o sistema online uma vez.
2. Navegue pelas telas que deseja usar offline para preencher o cache local.
3. No Chrome DevTools: Application > Service Workers, confirme que `/sw.js` está ativo.
4. Network > marque `Offline`, ou desligue Wi-Fi/dados móveis.
5. Reabra o PWA.
6. Faça uma alteração/agendamento: o indicador deve mostrar pendência.
7. Reative a internet.
8. A sincronização roda automaticamente; também é possível tocar no indicador para tentar sincronizar.

## Limitações esperadas

- Primeiro acesso em um aparelho precisa de internet para instalar/cachear o app.
- Login novo, recuperação de senha, Realtime e WhatsApp exigem internet.
- Dados nunca carregados antes não existem no cache local.
- Conflitos de agenda são validados pelo Supabase ao sincronizar.
- Admin Dev/saúde global podem exibir apenas a última informação cacheada quando offline.
