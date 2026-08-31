# WhatsApp no agendamento público

Esta versão adiciona WhatsApp sem Cloud API, webhook ou token.

## Recursos
- Botão **WhatsApp** no cabeçalho da agenda pública quando a empresa possui telefone.
- Atalho **Falar no WhatsApp** no card do estabelecimento.
- Após o agendamento, botão **Enviar confirmação no WhatsApp** com mensagem pronta contendo cliente, serviço, profissional, data, horário, duração, valor e status.
- Números brasileiros com 10/11 dígitos recebem automaticamente o DDI `55`.
- Nenhum secret é necessário e nenhum dado é enviado automaticamente: o cliente escolhe abrir o WhatsApp e enviar a mensagem.

## Configuração
Basta manter o telefone real da empresa preenchido em `/painel/configuracoes`.
