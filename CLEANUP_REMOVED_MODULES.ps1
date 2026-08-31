$ErrorActionPreference = "Stop"

Write-Host "BarberAgenda 4.1.1 - limpeza de modulos removidos" -ForegroundColor Cyan

$files = @(
  "src\pages\InventoryPage.tsx",
  "src\pages\AuditPage.tsx",
  "src\pages\SystemCheckPage.tsx",
  "src\pages\dev\DevAuditPage.tsx"
)

foreach ($relative in $files) {
  $path = Join-Path $PSScriptRoot $relative
  if (Test-Path $path) {
    Remove-Item $path -Force
    Write-Host "[OK] Removido: $relative" -ForegroundColor Green
  }
}

$forbidden = Get-ChildItem (Join-Path $PSScriptRoot "src") -Recurse -File |
  Select-String -Pattern '/painel/estoque|/painel/auditoria|/painel/diagnostico|/dev-admin/auditoria|InventoryPage|AuditPage|SystemCheckPage|DevAuditPage'

if ($forbidden) {
  Write-Host "[ATENCAO] Ainda existem referencias antigas:" -ForegroundColor Yellow
  $forbidden | ForEach-Object { Write-Host $_.Path ':' $_.LineNumber $_.Line }
  exit 1
}

Write-Host "[OK] Estoque, Auditoria e Diagnostico removidos do frontend." -ForegroundColor Green
Write-Host "Agora execute: npm install; npm run build" -ForegroundColor Cyan
