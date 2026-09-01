# BarberAgenda 4.2.5 — Correção de emojis no WhatsApp

## Problema corrigido
Quando o arquivo era salvo/transferido com codificação ANSI/Windows-1252, emojis podiam virar `�`.

## Correção
As mensagens de cobrança agora usam escapes Unicode JavaScript (`\u{...}`) no código-fonte.
O navegador converte esses escapes para os emojis corretos antes de chamar `encodeURIComponent`.

Exemplo:
- `\u{1F44B}` → 👋
- `\u{1F4B0}` → 💰
- `\u{2705}` → ✅

Isso evita corrupção mesmo se algum editor do Windows abrir o arquivo com uma página de código inadequada.

## Importante
Mantenha os arquivos do projeto salvos como **UTF-8**.
No VS Code: canto inferior direito → Encoding → Save with Encoding → UTF-8.

Depois:
npm install
npm run build
