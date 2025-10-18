#define AppVersion GetEnv("DEBRIFY_VERSION")
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{9B23C6A1-6A05-4B0C-9D6C-5DB02E2AA8F7}}
AppName=Debrify
AppVersion={#AppVersion}
AppPublisher=Debrify
AppPublisherURL=https://github.com/varunsalian/debrify
DefaultDirName={autopf}\\Debrify
DisableDirPage=yes
DefaultGroupName=Debrify
DisableProgramGroupPage=yes
OutputDir=..\\build\\windows\\installer
OutputBaseFilename=debrify-{#AppVersion}-setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=runner\\resources\\app_icon.ico
WizardStyle=modern

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\\build\\windows\\runner\\Release\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\Debrify"; Filename: "{app}\\debrify.exe"
Name: "{autodesktop}\\Debrify"; Filename: "{app}\\debrify.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\\debrify.exe"; Description: "Launch Debrify"; Flags: nowait postinstall skipifsilent
