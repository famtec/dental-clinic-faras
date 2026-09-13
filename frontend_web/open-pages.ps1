# =============================================================================
#  عيادتي الرقمية — تشغيل خادم محلي وفتح صفحات الاتجاه ب
#  شغّله بالنقر المزدوج، أو:  powershell -ExecutionPolicy Bypass -File open-pages.ps1
# =============================================================================

$Root = "C:\Users\HP\Desktop\Web_Development\dental_project\frontend_web"
$Port = 8000

Set-Location $Root

# --- إن كان المنفذ مشغولاً من تشغيل سابق، أوقفه ---------------------------
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host "المنفذ $Port مشغول — أوقف الخادم السابق..." -ForegroundColor Yellow
    $busy | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

# --- شغّل الخادم في نافذة مستقلة -------------------------------------------
Write-Host "تشغيل الخادم على المنفذ $Port ..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
    '-NoExit','-Command',
    "Set-Location '$Root'; Write-Host 'خادم عيادتي الرقمية — أغلق هذه النافذة لإيقافه' -ForegroundColor Green; python -m http.server $Port"
)

Start-Sleep -Seconds 3

# --- افتح الصفحات التي لا تحتاج تسجيل دخول ---------------------------------
$open = @('login','register','booking','landing','contact_developer')
foreach ($p in $open) {
    Start-Process "http://localhost:$Port/$p.html"
    Start-Sleep -Milliseconds 400
}

Write-Host ""
Write-Host "فُتحت 5 صفحات." -ForegroundColor Green
Write-Host "qr.html تتطلّب جلسة — سجّل الدخول من صفحة login ثم افتح:" -ForegroundColor Yellow
Write-Host "   http://localhost:$Port/qr.html"
Write-Host ""
Write-Host "لإيقاف الخادم: أغلق النافذة الخضراء." -ForegroundColor Gray
