# BarberAgenda Enterprise V4 — Build Fix + Admin Dev

Esta versão mantém o Admin Dev completo e remove definitivamente resíduos do módulo WhatsApp.

## Rotas Admin Dev

- `/dev-admin/login`
- `/dev-admin`
- `/dev-admin/empresas`
- `/dev-admin/usuarios`
- `/dev-admin/planos`
- `/dev-admin/suporte`
- `/dev-admin/saude`
- `/dev-admin/auditoria`
- `/dev-admin/configuracoes`

## SQL Admin Dev

Para banco existente, a ordem recomendada é:

1. `supabase/MASTER_PRODUCTION_UPGRADE.sql`
2. `supabase/fix-dev-admin-access.sql` (ou `setup-dev-admin.sql` para definir o primeiro super admin)
3. `supabase/QUICK_DIAGNOSTIC.sql`

Os hotfixes históricos permanecem no pacote para recuperação de instalações parciais.

## Build limpo

No PowerShell, execute:

```powershell
.\VERIFY_BUILD_ADMIN.ps1
npm install
npm run build
```

O script remove `src/pages/WhatsAppPage.tsx` caso uma versão antiga tenha deixado esse arquivo na pasta e verifica rotas críticas do Admin Dev.
