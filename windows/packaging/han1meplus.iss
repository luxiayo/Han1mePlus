; Han1me+ Windows 安装器（Inno Setup 6）
; CI 调用：ISCC.exe han1meplus.iss /DAppVersion=<版本号>
; 产物：build/Han1mePlus-v<版本号>-windows-x64-setup.exe
; 按用户级安装（PrivilegesRequired=lowest → {autopf} 解析到
; %LOCALAPPDATA%\Programs\Han1mePlus），无需管理员权限、不弹 UAC。

#ifndef AppVersion
#define AppVersion "1.2.0"
#endif

[Setup]
AppId={{CDD537F5-485C-460F-A17D-C4A637E26FC5}
AppName=Han1me+
AppVersion={#AppVersion}
AppPublisher=luxiayo
DefaultDirName={autopf}\Han1mePlus
DefaultGroupName=Han1me+
DisableProgramGroupPage=yes
OutputDir=..\..\build
OutputBaseFilename=Han1mePlus-v{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayName=Han1me+
UninstallDisplayIcon={app}\han1me_plus.exe
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Han1me+"; Filename: "{app}\han1me_plus.exe"
Name: "{autodesktop}\Han1me+"; Filename: "{app}\han1me_plus.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\han1me_plus.exe"; Description: "{cm:LaunchProgram,Han1me+}"; Flags: nowait postinstall skipifsilent
