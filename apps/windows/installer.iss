; Inno Setup script for TapoCam. Built by build.ps1 -Installer (CI passes the version).
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef FileVersion
  #define FileVersion "1.0.0.0"
#endif

[Setup]
AppId={{6F4C2D1A-8B7E-4E5F-9A3C-2D1B0E9F7A61}
AppName=TapoCam
AppVersion={#AppVersion}
AppVerName=TapoCam {#AppVersion}
AppPublisher=EndLess728
AppPublisherURL=https://github.com/EndLess728/TapoCam
VersionInfoVersion={#FileVersion}
DefaultDirName={autopf}\TapoCam
DisableProgramGroupPage=yes
; Per-user install by default, so no admin prompt.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=out
OutputBaseFilename=TapoCam-{#AppVersion}-windows-setup
SetupIconFile=TapoCam\Assets\TapoCam.ico
UninstallDisplayIcon={app}\TapoCam.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "dist\TapoCam\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\TapoCam"; Filename: "{app}\TapoCam.exe"
Name: "{autodesktop}\TapoCam"; Filename: "{app}\TapoCam.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TapoCam.exe"; Description: "{cm:LaunchProgram,TapoCam}"; Flags: nowait postinstall skipifsilent
