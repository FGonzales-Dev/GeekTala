; Inno Setup script for the Noote Windows installer.
;
; Build with tools/build-windows-installer.ps1, which builds the release app
; first and passes AppVersion and VCRedistDir. To compile by hand after
; `flutter build windows --release`:
;   ISCC.exe /DAppVersion=1.0.0 /DVCRedistDir="<...>\Microsoft.VC145.CRT" windows\installer\noote.iss
;
; The installer goes to build\installer\noote-setup-<version>.exe.

#define AppName "Noote"
#define AppExeName "noote.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
; Keep AppId the same across versions so a new installer upgrades in place.
AppId={{FEFEDD31-8478-4955-8D90-AFE79CBBDE75}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
; Installs for the current user (no admin prompt) into
; %LOCALAPPDATA%\Programs\Noote; the wizard offers an all-users install too.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=noote-setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Flutter's assets folder is replaced wholesale on upgrade so stale files from
; an older version don't linger. Notes live in the user's app data folder, not
; here, so they are never touched by installing, upgrading, or uninstalling.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef VCRedistDir
; App-local copy of the Microsoft C++ runtime, so the app starts on PCs that
; don't have the Visual C++ Redistributable installed.
Source: "{#VCRedistDir}\msvcp140*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VCRedistDir}\vcruntime140*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VCRedistDir}\concrt140.dll"; DestDir: "{app}"; Flags: ignoreversion
#endif

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
