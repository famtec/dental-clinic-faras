; مثبّت ويندوز لتطبيق «عيادتي الرقمية» (2026-09-25)
; ═══════════════════════════════════════════════════════════════════════════
; البناء:
;   flutter build windows --release
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer\dental_app.iss
; الناتج: build\installer\DigitalClinic-Setup-<الإصدار>.exe
;
; التثبيت لكل مستخدم (PrivilegesRequired=lowest) في مجلد برامجه دون طلب صلاحية
; المدير، مع خيار التثبيت للجميع من نافذة المثبّت. مكتبات Visual C++ التي
; يحتاجها محرّك Flutter تُنسخ بجانب التطبيق نفسه، فلا يفشل الإقلاع على جهاز
; بلا حزمة VC++ Redistributable.
;
; رقم الإصدار يُحدَّث يدوياً مع version في pubspec.yaml.

#define AppName "عيادتي الرقمية"
#define AppVersion "1.5.0"
#define AppExe "dental_app.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"
#define VcRedistDir "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT"

[Setup]
AppId={{6F4B2C1E-9A3D-4E7B-B8C5-2D1F0A9E7C43}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=المهندس فارس حلاوي
AppPublisherURL=https://dental-clinic-faras.onrender.com
DefaultDirName={autopf}\DigitalClinic
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=DigitalClinic-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#VcRedistDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedistDir}\msvcp140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedistDir}\msvcp140_2.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedistDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedistDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
