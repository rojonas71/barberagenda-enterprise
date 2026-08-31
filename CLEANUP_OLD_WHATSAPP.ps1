$ErrorActionPreference = "Stop"
Write-Host "Limpando resíduos antigos do módulo WhatsApp..." -ForegroundColor Cyan

$oldPage = Join-Path $PSScriptRoot "src\pages\WhatsAppPage.tsx"
if (Test-Path $oldPage) {
  Remove-Item $oldPage -Force
  Write-Host "Removido: src/pages/WhatsAppPage.tsx" -ForegroundColor Green
} else {
  Write-Host "WhatsAppPage.tsx já não existe." -ForegroundColor DarkGray
}

$matches = Get-ChildItem (Join-Path $PSScriptRoot "src") -Recurse -File -Include *.ts,*.tsx |
  Select-String -Pattern 'WhatsAppPage|/painel/whatsapp|current="whatsapp"|current=''whatsapp''' -SimpleMatch:$false

if ($matches) {
  Write-Host "Ainda existem referências antigas:" -ForegroundColor Yellow
  $matches | ForEach-Object { Write-Host ("{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()) }
  exit 1
}

Write-Host "Nenhum resíduo de WhatsApp encontrado em src/." -ForegroundColor Green
Write-Host "Agora execute: npm run build" -ForegroundColor Cyan
