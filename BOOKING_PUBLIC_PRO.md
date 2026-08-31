# Agenda Pública PRO

Atualização da tela pública `/b/:slug` para uma experiência de agendamento mais completa.

## Melhorias

- cabeçalho profissional com logo, endereço e status Realtime;
- progresso visual em 4 etapas;
- cards de serviço com descrição, duração e preço;
- profissionais com foto, bio e estado selecionado;
- atalhos de datas para os próximos dias;
- calendário completo dentro do limite de antecedência configurado;
- horários agrupados em manhã, tarde e noite;
- carregamento explícito da disponibilidade;
- lista de espera quando não houver vagas;
- nome, telefone e observação opcional do cliente;
- revisão obrigatória das regras antes da confirmação;
- resumo fixo do agendamento no desktop;
- resumo adaptado para mobile;
- tela de sucesso após confirmar;
- escuta Realtime também para alterações em `appointments`;
- layout responsivo para desktop, tablet e celular.

## Banco de dados

Esta atualização não exige nova migração SQL. Ela usa os campos e RPCs já existentes na versão Enterprise V4:

- `get_busy_ranges`
- `get_booking_day_rules`
- `get_public_schedule_blocks`
- `appointments`
- `waitlist_entries`
- `businesses.booking_advance_days`
- `businesses.cancellation_notice_hours`
- `businesses.auto_confirm_bookings`

## Validação

Depois de instalar as dependências:

```bash
npm install
npm run build
```
