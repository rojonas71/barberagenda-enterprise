# BarberAgenda 4.2.0 — Logo + Banner

## Atualização
- Campo manual **Logo (URL)** removido da tela de Configurações.
- Upload de **logo** direto pelo painel.
- Upload de **banner** direto pelo painel.
- Preview antes de salvar.
- PNG, JPG e WEBP, até 5 MB.
- Logo recomendada: 512×512 px.
- Banner recomendado: 1600×600 px.
- Banner exibido automaticamente na página pública `/b/:slug`.
- Layout do banner adaptado para celular e computador.

## Banco existente
Execute no Supabase SQL Editor:

```text
supabase/business-media-upload.sql
```

Depois publique o frontend atualizado.

## Fluxo
1. Painel → Configurações.
2. Enviar logo.
3. Enviar banner.
4. Clicar em **Salvar configurações**.
5. Abrir o link público da barbearia para conferir.

O bucket `business-assets` é público para exibição das imagens. Escrita é limitada ao proprietário da empresa pelo caminho `<business_id>/...`.
