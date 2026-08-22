#ifndef MyAppVersion
  #error MyAppVersion must be provided by the build script
#endif

#ifndef BuildDir
  #error BuildDir must be provided by the build script
#endif

#ifndef OutputDir
  #error OutputDir must be provided by the build script
#endif

#define MyAppName "Best Todo List"
#define MyAppPublisher "lmyybh"
#define MyAppExeName "best_todo_list.exe"

[Setup]
AppId={{976E0DB1-EE66-49F9-8BFE-40A1EA8BB4AA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/lmyybh/best_todo_list
AppSupportURL=https://github.com/lmyybh/best_todo_list/issues
AppUpdatesURL=https://github.com/lmyybh/best_todo_list/releases
DefaultDirName={localappdata}\Programs\BestTodoList
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=best_todo_list-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=yes
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: ".dart_tool\*"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
