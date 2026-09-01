# BarberAgenda 4.2.3 — Mensalidade pelo WhatsApp

## Novo
No **Admin Dev → Empresas**, usuários com permissão de cobrança (`super_admin` ou `billing`) passam a ter:

- botão **Cobrar** na tabela;
- botão **Avisar mensalidade** nos detalhes da empresa;
- mensagem pronta com nome do plano;
- valor mensal;
- vencimento, quando cadastrado;
- link de pagamento do plano;
- pedido para enviar o comprovante.

O WhatsApp usado é o telefone cadastrado na empresa.

## Mensagem padrão
Olá! 👋 Tudo bem?

Este é um lembrete da mensalidade do BarberAgenda. ✂️📅

💳 Plano: Plano Profissional
💰 Valor: R$ 80,00/mês
📅 Vencimento: DD/MM/AAAA

Para manter seu acesso ao sistema em dia, realize o pagamento pelo link:
https://mpago.la/2tn4qBx

Após o pagamento, envie o comprovante por aqui. ✅

Obrigado por utilizar o BarberAgenda!

## Instalação
Execute no Supabase SQL Editor:

`supabase/billing-whatsapp-v4.2.3.sql`

Depois rode:

`npm run build`

## Automação
Esta versão usa `wa.me`: o Admin Dev clica e o WhatsApp abre com a mensagem pronta.
Ela **não envia mensagens automaticamente sem ação humana**.

Para envio automático em datas de vencimento seria necessário integrar uma API oficial/provedor de WhatsApp e um job/Edge Function.
