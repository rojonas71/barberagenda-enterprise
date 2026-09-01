# BarberAgenda 4.2.7 — Correção de quebra de linha no WhatsApp

O problema era o uso de `lines.join('\\n')`, que envia os caracteres `\` + `n`
para o WhatsApp.

A forma correta é:

```ts
return `https://wa.me/${number}?text=${encodeURIComponent(lines.join('\n'))}`
```

Assim o JavaScript cria quebras de linha reais antes do `encodeURIComponent`.
