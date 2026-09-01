# BarberAgenda 4.2.2 — Plano & Mensalidade

- Plano Profissional: R$ 80,00/mês.
- Profissionais ilimitados.
- Equipe ilimitada.
- Aviso no Dashboard.
- Estados: ativo, vence em breve, pagamento pendente, inativo e sem assinatura.
- Botão de pagamento via Mercado Pago.
- Link configurável no Admin Dev > Planos.
- Realtime da assinatura no Dashboard.

Execute `supabase/subscription-plan-v4.2.2.sql` antes de publicar.

Observação: o link de pagamento não confirma automaticamente a transação. Após conferir o pagamento, o Admin Dev deve marcar a assinatura como `active` e informar `current_period_ends_at`.
