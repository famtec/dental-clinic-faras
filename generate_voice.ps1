# ============================================================
#  توليد التعليق الصوتي للإعلان — صوت أنثوي سوري (ar-SY-AmanyNeural)
#  شغّل هالملف بـ PowerShell من مجلد المشروع:  .\generate_voice.ps1
#  المتطلّبات (مرة وحدة):   pip install edge-tts
#  الناتج: مجلد voice\ فيه 12 ملف mp3 — ابعتهن لي وأنا بدمجهن بالفيديو.
# ============================================================

$ErrorActionPreference = "Stop"
$out = Join-Path $PSScriptRoot "voice"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$voice = "ar-SY-AmanyNeural"
$rate  = "+6%"    # إيقاع إعلاني مضبوط على 60 ثانية
$pitch = "+0Hz"

$lines = @(
  "بعدك عم تدير عيادتك بدفاتر وأوراق؟",
  "عيادتي الرقمية — نظام إدارة عيادات الأسنان، عربي بالكامل.",
  "من الكمبيوتر: كل مرضاك قدامك، وبضغطة بتفوت على ملف المريض.",
  "مخطط أسنان تفاعلي، وصفات، وأرشيف أشعة — بمكان واحد.",
  "مواعيد اليوم بجدول واضح، وتذكير واتساب لكل مريض.",
  "دخلك ومصاريفك وأرباحك بتقارير شهرية، ومخزونك تحت السيطرة.",
  "ورابط حجز ورمز كيو آر — مرضاك بيحجزوا لحالهن.",
  "وما وقفنا هون: تطبيق أندرويد كامل بجيبتك.",
  "نفس عيادتك بإيدك: مرضى، مواعيد، مالية، ومخزون.",
  "وبيشتغل بدون إنترنت، وبيتزامن لحالو أول ما يرجع.",
  "وإشعار فوري بكل طلب حجز، ووضع ليلي مريح لعينيك.",
  "عيادتي الرقمية — عيادتك كلها بمكان واحد."
)

for ($i = 0; $i -lt $lines.Count; $i++) {
  $n    = "{0:d2}" -f ($i + 1)
  $file = Join-Path $out "v$n.mp3"
  Write-Host "[$n/12] $($lines[$i])"
  edge-tts --voice $voice "--rate=$rate" "--pitch=$pitch" --text $lines[$i] --write-media $file
}

Write-Host ""
Write-Host "خلص — الملفات بمجلد: $out" -ForegroundColor Green
$made = (Get-ChildItem $out -Filter *.mp3 | Where-Object { $_.Length -gt 0 }).Count
if ($made -eq 12) { Write-Host "تم توليد 12 ملف صوتي بنجاح" -ForegroundColor Green }
else { Write-Host "تحذير: تولّد $made ملف فقط من 12" -ForegroundColor Yellow }
