; Windows installer for the AI Usage tray app (Inno Setup 6).
;
; Built by windows/build-installer.ps1 from PyInstaller's "dist\AI Usage" folder
; (windows/ai-usage.spec), in .github/workflows/windows.yml — on every push, and
; for each release, which release.yml runs that workflow for.
;
; Per user: no admin rights, installed to %LOCALAPPDATA%\Programs\AI Usage.
; Settings and history live in %APPDATA% / %LOCALAPPDATA%\ai-usage-widget and
; survive updates and uninstalls alike.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Never change the AppId: it is how Windows knows a new version is the same app
; and updates it in place.
AppId={{DA55F997-6C64-4B6F-92EB-D3BEB6885B68}
AppName=AI Usage
AppVersion={#AppVersion}
AppVerName=AI Usage {#AppVersion}
AppPublisher=Muddyblack
AppPublisherURL=https://github.com/Muddyblack/ai-usage-widget
AppSupportURL=https://github.com/Muddyblack/ai-usage-widget/issues
DefaultDirName={autopf}\AI Usage
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..
OutputBaseFilename=AI-Usage-Setup-{#AppVersion}
SetupIconFile=..\dist\ai-usage.ico
UninstallDisplayIcon={app}\AI Usage.exe
UninstallDisplayName=AI Usage
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The running app is stopped in [Code] instead of by the Restart Manager, which
; would ask the user about a tray app with no window to close.
CloseApplications=no

[Tasks]
; Offered on a first install only. On an update it would apply the choice
; remembered from that install, turning autostart back on for someone who had
; switched it off in the app since; left out, the Run value stays as it is.
Name: "autostart"; Description: "Start AI Usage when I sign in"; Check: not IsUpgrade
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\dist\AI Usage\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; An update replaces the whole bundle: files a new PyInstaller build no longer
; has must not linger next to the ones it does.
Type: filesandordirs; Name: "{app}\_internal"

[Icons]
Name: "{autoprograms}\AI Usage"; Filename: "{app}\AI Usage.exe"
Name: "{autodesktop}\AI Usage"; Filename: "{app}\AI Usage.exe"; Tasks: desktopicon

[Registry]
; The same value the app's own "Start with Windows" switch writes (app.py,
; set_autostart), so the two stay one setting.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "AI Usage"; ValueData: """{app}\AI Usage.exe"""; Tasks: autostart
; Removed on uninstall whichever of the two turned it on.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "AI Usage"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\AI Usage.exe"; Description: "{cm:LaunchProgram,AI Usage}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM ""AI Usage.exe"""; Flags: runhidden; RunOnceId: "StopAIUsage"

[Code]
var
  WasRunning: Boolean;

// An earlier install is there: its uninstaller is registered under AppId (with
// the doubled brace undone) plus "_is1". Keep the GUID in step with AppId.
function IsUpgrade: Boolean;
var
  Uninstaller: String;
begin
  Result := RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA55F997-6C64-4B6F-92EB-D3BEB6885B68}_is1', 'UninstallString', Uninstaller);
end;

// Stop a running copy before its files are replaced. taskkill exits 0 when it
// stopped something and 128 when nothing was running.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  WasRunning := Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM "AI Usage.exe"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  Result := '';
end;

// A silent update (/SILENT, winget) skips the [Run] entry's checkbox, which
// would leave the tray app stopped until the next sign-in: start it again when
// it was running before.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if (CurStep = ssPostInstall) and WizardSilent and WasRunning then
    ExecAsOriginalUser(ExpandConstant('{app}\AI Usage.exe'), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;
