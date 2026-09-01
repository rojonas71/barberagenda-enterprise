# BarberAgenda 4.2.1 — Profissionais PRO

Atualização focada no módulo **Profissionais**.

## Novidades
- Upload de foto direto pelo Supabase Storage.
- Telefone, e-mail e especialidade no perfil.
- Busca por nome, especialidade, telefone e e-mail.
- Filtro por profissionais ativos/inativos.
- Indicadores: total, ativos, inativos e comissão média.
- Botão **Jornada** abre Disponibilidade já selecionando o profissional.
- Layout em cards para celular e tabela completa no desktop.
- CRUD e Realtime mantidos.
- Validação de comissão e e-mail.

## Banco
Para projeto já existente, execute:

```text
supabase/professionals-v4.2.1.sql
```

A foto utiliza o bucket `business-assets` da versão 4.2.0.

## Build
```powershell
npm install
npm run build
```
