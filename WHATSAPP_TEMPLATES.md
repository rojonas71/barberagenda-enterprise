# Templates sugeridos — BarberAgenda WhatsApp

Use como referência ao criar templates transacionais no WhatsApp Manager. Ajuste o texto à sua marca e às regras vigentes da Meta antes de enviar para aprovação.

A integração envia os parâmetros nesta ordem:

1. Cliente
2. Empresa
3. Data
4. Horário
5. Serviço
6. Profissional

## Confirmação

Nome sugerido: `barberagenda_confirmacao`

```text
Olá {{1}}! ✅
Seu agendamento na {{2}} está confirmado.

📅 Data: {{3}}
⏰ Horário: {{4}}
✂️ Serviço: {{5}}
👤 Profissional: {{6}}

Até lá!
```

## Lembrete

Nome sugerido: `barberagenda_lembrete`

```text
Olá {{1}}! Passando para lembrar do seu horário na {{2}}. ⏰

📅 {{3}} às {{4}}
✂️ {{5}}
👤 {{6}}

Se precisar alterar o horário, entre em contato com a equipe.
```

## Cancelamento

Nome sugerido: `barberagenda_cancelamento`

```text
Olá {{1}}.
Seu agendamento na {{2}} foi cancelado.

📅 {{3}}
⏰ {{4}}
✂️ {{5}}
👤 {{6}}

Quando quiser, faça um novo agendamento.
```

## Reagendamento

Nome sugerido: `barberagenda_reagendamento`

```text
Olá {{1}}! Seu horário na {{2}} foi atualizado. 🔄

📅 Nova data: {{3}}
⏰ Novo horário: {{4}}
✂️ Serviço: {{5}}
👤 Profissional: {{6}}

Confira os dados acima e fale com a equipe caso precise de ajuda.
```
