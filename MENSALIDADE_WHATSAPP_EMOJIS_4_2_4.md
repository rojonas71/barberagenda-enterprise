# BarberAgenda 4.2.4 — Cobrança WhatsApp com emojis

A mensagem de cobrança em **Admin Dev → Empresas** agora muda automaticamente conforme a situação da mensalidade.

## Mensagens automáticas

### 🟢 Lembrete normal
Exibe:
- 👋 saudação;
- 💈 BarberAgenda;
- 📦 plano;
- 💰 valor mensal;
- 📅 vencimento;
- 🔗 link de pagamento;
- 📲 pedido do comprovante;
- ✅ confirmação;
- ✂️🚀 encerramento.

### 🟡 Vence em breve
Quando faltarem até **5 dias** para o vencimento, o texto muda para um lembrete de vencimento próximo.

### 🔴 Mensalidade pendente
Se a assinatura estiver `past_due`, `inactive` ou a data de vencimento já tiver passado, o WhatsApp abre com uma mensagem de pagamento pendente.

## Uso

Admin Dev → Empresas → **Cobrar**

ou

Admin Dev → Empresas → Detalhes → **Avisar mensalidade**

O sistema usa o WhatsApp cadastrado na empresa e o link de pagamento configurado no plano.

## Observação
Esta versão continua usando `wa.me`. Ela abre o WhatsApp com a mensagem preenchida, mas não envia automaticamente sem confirmação humana.
