$ErrorActionPreference = "Stop"

Write-Host "BarberAgenda Enterprise V4 - verificacao Build + Admin Dev" -ForegroundColor Cyan

$oldWhatsApp = Join-Path $PSScriptRoot "src\pages\WhatsAppPage.tsx"
if (Test-Path $oldWhatsApp) {
    Remove-Item $oldWhatsApp -Force
    Write-Host "[OK] Arquivo antigo WhatsAppPage.tsx removido." -ForegroundColor Green
}

$forbidden = Get-ChildItem (Join-Path $PSScriptRoot "src") -Recurse -File |
    Select-String -Pattern 'WhatsAppPage|/painel/whatsapp|current="whatsapp"'

if ($forbidden) {
    Write-Host "[ERRO] Ainda existem referencias antigas de WhatsApp:" -ForegroundColor Red
    $forbidden | ForEach-Object { Write-Host $_.Path ':' $_.LineNumber $_.Line }
    exit 1
}
Write-Host "[OK] Nenhum residuo antigo de WhatsApp no frontend." -ForegroundColor Green

$app = Get-Content (Join-Path $PSScriptRoot "src\App.tsx") -Raw
$routes = @(
  '/dev-admin/login',
  '/dev-admin',
  'empresas',
  'usuarios',
  'planos',
  'suporte',
  'saude',
  'auditoria',
  'configuracoes'
)

foreach ($route in $routes) {
    if ($app -notmatch [regex]::Escape($route)) {
        Write-Host "[ERRO] Rota Admin Dev ausente: $route" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[OK] Rotas principais do Admin Dev presentes." -ForegroundColor Green

$devPages = Get-ChildItem (Join-Path $PSScriptRoot "src\pages\dev") -Filter *.tsx -File
if ($devPages.Count -lt 9) {
    Write-Host "[ERRO] Paginas Admin Dev incompletas. Encontradas: $($devPages.Count)" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] $($devPages.Count) paginas do Admin Dev encontradas." -ForegroundColor Green

$requiredSql = @(
  'MASTER_PRODUCTION_UPGRADE.sql',
  'dev-admin-upgrade.sql',
  'fix-dev-admin-rpcs.sql',
  'fix-system-settings.sql',
  'fix-audit-logs.sql',
  'setup-dev-admin.sql'
)
foreach ($file in $requiredSql) {
    if (-not (Test-Path (Join-Path $PSScriptRoot "supabase\$file"))) {
        Write-Host "[ERRO] SQL Admin Dev ausente: $file" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[OK] SQLs essenciais do Admin Dev presentes." -ForegroundColor Green
Write-Host "Verificacao concluida. Agora rode: npm install; npm run build" -ForegroundColor Cyan
