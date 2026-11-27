#ifndef ReleaseDir
  #error ReleaseDir must point to the Windows release directory.
#endif
#ifndef AppVersion
  #error AppVersion must be set from pubspec.yaml.
#endif

[Setup]
AppId={{8EA8AEDB-A5D8-47C6-B238-EDB645096FDA}
AppName=Ink Study
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Ink Study
DefaultGroupName=Ink Study
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
MinVersion=10.0
UninstallDisplayIcon={app}\ink_study.exe
OutputBaseFilename=InkStudy-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Ink Study"; Filename: "{app}\ink_study.exe"; WorkingDir: "{app}"

[Run]
Filename: "{app}\ink_study.exe"; Description: "Ink Study"; Flags: nowait postinstall skipifsilent
