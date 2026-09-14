#requires -Version 5.1
<#
    جرد رموز التفعيل — عيادتي الرقمية
    =================================
    يقرأ الحالة الحيّة من الخادم ويكتب ملف CSV محدَّثاً يفتح في Excel مباشرة.

    المفتاح الإداري لا يُكتب داخل هذا الملف عمداً. يُقرأ بالترتيب:
      1) وسيط -AdminKey عند التشغيل
      2) متغيّر البيئة DENTAL_ADMIN_KEY
      3) سؤال عند التشغيل (يُكتب مخفيّاً ولا يُحفَظ)
    لتثبيته مرة واحدة على هذا الجهاز (عدّل القيمة بعد أي تدوير للمفتاح):
      setx DENTAL_ADMIN_KEY "المفتاح"
    ثم أغلق النافذة وافتح واحدة جديدة.
#>

param(
    [string]$AdminKey,
    [string]$BaseUrl = 'https://dental-clinic-faras.onrender.com',
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

if (-not $OutDir) { $OutDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutDir) { $OutDir = (Get-Location).Path }

# ------------------------------------------------------------ المفتاح الإداري
if (-not $AdminKey) { $AdminKey = $env:DENTAL_ADMIN_KEY }
if (-not $AdminKey) {
    Write-Host ''
    Write-Host '  لم يُضبَط متغيّر البيئة DENTAL_ADMIN_KEY.' -ForegroundColor Yellow
    $secure = Read-Host '  ألصق المفتاح الإداري (لن يظهر أثناء الكتابة)' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try   { $AdminKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if (-not $AdminKey) { Write-Host '  لا مفتاح — توقّف.' -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------- الجلب
$uri = "$BaseUrl/api/admin/activation-keys?limit=2000"
Write-Host ''
Write-Host '  يجلب الجرد من الخادم…' -ForegroundColor Cyan
Write-Host '  (قد تستغرق أول محاولة دقيقة كاملة إذا كانت الخدمة نائمة)' -ForegroundColor DarkGray

try {
    $all = Invoke-RestMethod -Uri $uri -Headers @{ 'X-Admin-Secret' = $AdminKey } -TimeoutSec 180
}
catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }

    # نصّ الخطأ يختلف بين PowerShell 5.1 و 7، وقد يأتي فارغاً — نجمعه من كل مصدر متاح.
    $msg = @($_.Exception.Message, $_.ErrorDetails.Message,
             $_.Exception.InnerException.Message, $_.ToString()) |
           Where-Object { $_ } | Select-Object -First 1
    if (-not $msg) { $msg = 'سبب غير معروف' }
    Write-Host ''
    switch ($status) {
        401 { Write-Host '  ✗ 401 — المفتاح الإداري غير صحيح (أو دُوِّر في Render ولم يُحدَّث هنا).' -ForegroundColor Red }
        404 { Write-Host '  ✗ 404 — المسار غير موجود في النسخة المنشورة. تأكّد أن آخر دفعة وصلت وأن Render أنهى البناء.' -ForegroundColor Red }
        default {
            if ($msg -match 'could not be resolved|remote name|No such host|nodename|Name or service not known') {
                Write-Host '  ✗ تعذّرت ترجمة العنوان — مشكلة DNS على هذا الجهاز لا في الخادم.' -ForegroundColor Red
                Write-Host '    جرّب:  ipconfig /flushdns   ثم أعد المحاولة.' -ForegroundColor DarkGray
            } elseif ($msg -match 'timed out|timeout') {
                Write-Host '  ✗ انتهت المهلة — الخدمة نائمة على الأرجح. أعد التشغيل بعد دقيقة.' -ForegroundColor Red
            } else {
                Write-Host "  ✗ فشل الاتصال: $msg" -ForegroundColor Red
            }
        }
    }
    Write-Host ''
    exit 1
}

$AdminKey = $null   # لا يبقى في الذاكرة بعد الاستخدام

# ------------------------------------------------------------------ التحويل
$tierAr = @{
    'premium'              = 'Premium'
    'premium_plus'         = 'Premium Plus'
    'expired_subscription' = 'منتهية'
    'pending_activation'   = 'بانتظار التفعيل'
}

function Convert-Tier($v) { if ($v -and $tierAr.ContainsKey($v)) { $tierAr[$v] } elseif ($v) { $v } else { '—' } }

function Get-Batch($code) {
    if ($code -like 'TEST-*' -or $code -like 'FARAS-*') { return 'رموز ثابتة (مزروعة في الكود)' }
    if ($code -like 'TRIAL-*') { return 'تجربة مجانية' }
    if ($code -like 'PP-*')    { return 'باقة العيادات' }
    if ($code -like 'STD-*')   { return 'دفعة Standard قديمة' }
    return 'دفعة Premium'
}

$rows = foreach ($k in $all.keys) {
    $left = $k.holder_days_left
    $flag = '—'
    if ($k.is_used -and $null -ne $left) {
        if ($left -lt 0)      { $flag = "منتهٍ منذ $([Math]::Abs($left)) يوماً" }
        elseif ($left -le 7)  { $flag = "ينتهي خلال $left أيام" }
        else                  { $flag = 'سارٍ' }
    }
    $exp = ''
    if ($k.holder_expires_at) { $exp = ([datetime]$k.holder_expires_at).ToString('yyyy-MM-dd') }

    [pscustomobject][ordered]@{
        'رمز التفعيل'    = $k.key_code
        'الدفعة'         = Get-Batch $k.key_code
        'المدة (يوم)'    = $k.duration_days
        'يفتح باقة'      = Convert-Tier $k.grants_tier
        'الحالة'         = $(if ($k.is_used) { 'مُستخدَم' } else { 'متاح' })
        'استُخدم من'     = $(if ($k.used_by_email) { $k.used_by_email } else { '—' })
        'باقته الآن'     = Convert-Tier $k.holder_tier
        'ينتهي في'       = $(if ($exp) { $exp } else { '—' })
        'الأيام المتبقية' = $(if ($null -ne $left) { $left } else { '' })
        'تنبيه'          = $flag
    }
}

# المستخدَمة أولاً وأقربها انتهاءً في الأعلى
$rows = $rows | Sort-Object @{ Expression = { $_.'الحالة' -ne 'مُستخدَم' } },
                           @{ Expression = { if ($_.'الأيام المتبقية' -ne '') { [int]$_.'الأيام المتبقية' } else { 999999 } } },
                           @{ Expression = { $_.'الدفعة' } },
                           @{ Expression = { $_.'رمز التفعيل' } }

# ------------------------------------------------------------------- الحفظ
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$csv   = Join-Path $OutDir "activation-codes_$stamp.csv"

# يُكتب بعلامة BOM صراحةً: بدونها يعرض Excel على ويندوز العربية رموزاً مشوّهة.
# لا نعتمد على Export-Csv -Encoding UTF8 لأن معناه اختلف بين PowerShell 5.1 و 7.
$lines = $rows | ConvertTo-Csv -NoTypeInformation
[IO.File]::WriteAllLines($csv, $lines, (New-Object Text.UTF8Encoding $true))

# ------------------------------------------------------------------ الملخّص
$s = $all.summary
$expired = @($rows | Where-Object { $_.'تنبيه' -like 'منتهٍ*' })
$soon    = @($rows | Where-Object { $_.'تنبيه' -like 'ينتهي*' })

Write-Host ''
Write-Host ('  ' + '─' * 58) -ForegroundColor DarkGray
Write-Host "   الإجمالي $($s.total)   ·   مُستخدَم $($s.used)   ·   متاح $($s.available)" -ForegroundColor White
foreach ($t in $s.by_grants_tier.PSObject.Properties) {
    $v = $t.Value
    Write-Host ("   {0,-14} إجمالي {1,-5} مُستخدَم {2,-5} متاح {3}" -f (Convert-Tier $t.Name), $v.total, $v.used, $v.available) -ForegroundColor Gray
}
Write-Host ('  ' + '─' * 58) -ForegroundColor DarkGray

if ($expired.Count) {
    Write-Host ''
    Write-Host '   اشتراكات منتهية:' -ForegroundColor Red
    foreach ($r in $expired) { Write-Host ("     • {0}   ({1})" -f $r.'استُخدم من', $r.'تنبيه') -ForegroundColor Red }
}
if ($soon.Count) {
    Write-Host ''
    Write-Host '   تنتهي خلال أسبوع:' -ForegroundColor Yellow
    foreach ($r in $soon) { Write-Host ("     • {0}   ({1})" -f $r.'استُخدم من', $r.'تنبيه') -ForegroundColor Yellow }
}
if (-not $expired.Count -and -not $soon.Count) {
    Write-Host ''
    Write-Host '   كل الاشتراكات سارية ولا شيء يقترب من الانتهاء.' -ForegroundColor Green
}

Write-Host ''
Write-Host "   حُفظ في: $csv" -ForegroundColor Cyan
Write-Host ''

try { Invoke-Item $csv } catch { Write-Host '   (تعذّر فتحه تلقائياً — افتحه يدوياً)' -ForegroundColor DarkGray }
