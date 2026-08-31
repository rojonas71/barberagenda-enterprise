# BarberAgenda — Mobile + PC

## Breakpoints principais

- `> 1440px`: desktop amplo, conteúdo e dashboards com melhor aproveitamento horizontal.
- `901px–1439px`: notebook/desktop padrão com sidebar fixa.
- `641px–900px`: tablet/mobile landscape com menu drawer.
- `431px–640px`: smartphones com grids em 1–2 colunas, formulários empilhados e agenda otimizada.
- `<= 430px`: celulares pequenos com KPIs em coluna única e ações em largura total.

## Painel da empresa

No desktop a navegação permanece em sidebar fixa. No mobile aparece um cabeçalho compacto com botão de menu; a sidebar abre como drawer, possui backdrop e fecha ao navegar, tocar fora, pressionar `Esc` ou ampliar a janela para desktop.

## Admin Dev

O Dev Console utiliza o mesmo padrão responsivo: sidebar fixa no PC e drawer no celular. Tabelas globais mantêm rolagem horizontal touch para preservar todas as colunas administrativas.

## Agenda pública

A página `/b/:slug` foi otimizada para toque:

- serviços e profissionais em uma coluna no celular;
- horários em 3 colunas e 2 colunas em celulares pequenos;
- inputs com 16px no iOS para evitar zoom automático;
- botões com altura mínima para toque;
- `viewport-fit=cover` e safe-area para aparelhos com notch.

## Tabelas e CRUD

Tabelas permanecem completas no desktop. Em telas pequenas, usam rolagem horizontal com suporte a touch e primeira coluna fixa para manter o contexto do registro durante a navegação.
