; TigerMarkView installer (Inno Setup)
;
; Build it with installer\Build-Installer.ps1 from the repository root — that publishes the app and
; invokes ISCC with the right paths. Compiling this script by hand works too, provided a Release
; win-x64 publish already exists at artifacts\publish\win-x64.
;
; Nothing here states the version, the product name, the publisher, or the copyright. All four are
; read back out of the published TigerMarkView.exe, which the SDK stamped from Version.props
; — the same chain the About dialog reads at run time, so the installer and About can never disagree.
; Adding a literal version to this file is exactly the drift Version.props exists to prevent.

; ---------------------------------------------------------------------------------------------
; Inputs (override with ISCC /D...)
; ---------------------------------------------------------------------------------------------

#ifndef SourceDir
  #define SourceDir AddBackslash(SourcePath) + "..\artifacts\publish\win-x64"
#endif

#ifndef OutputDir
  #define OutputDir AddBackslash(SourcePath) + "..\artifacts\installer"
#endif

#define AppExeName "TigerMarkView.exe"
#define AppExePath AddBackslash(SourceDir) + AppExeName

#if !FileExists(AppExePath)
  #error Publish output not found. Run installer\Build-Installer.ps1, or pass /DSourceDir=<publish folder>.
#endif

; ---------------------------------------------------------------------------------------------
; Identity, derived from the published executable's version resource
; ---------------------------------------------------------------------------------------------

#define AppName GetStringFileInfo(AppExePath, "ProductName")
#define AppPublisher GetStringFileInfo(AppExePath, COMPANY_NAME)
#define AppCopyright GetStringFileInfo(AppExePath, LEGAL_COPYRIGHT)
; "Comments", not FILE_DESCRIPTION: the SDK puts <Description> from Version.props there,
; while FileDescription is just the assembly name again.
#define AppDescription GetStringFileInfo(AppExePath, "Comments")

; ProductVersion carries SemVer build metadata. Strip it exactly as
; Core.About.ApplicationVersion.Format does for the About dialog.
#define RawProductVersion GetStringFileInfo(AppExePath, PRODUCT_VERSION)
#if Pos("+", RawProductVersion) > 0
  #define AppVersion Copy(RawProductVersion, 1, Pos("+", RawProductVersion) - 1)
#else
  #define AppVersion RawProductVersion
#endif

[Setup]
; Fixed for the lifetime of the product: this is what makes a later setup recognise an existing
; installation and upgrade it in place rather than installing a second copy alongside. Never change it.
AppId={{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppCopyright={#AppCopyright}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup
VersionInfoCompany={#AppPublisher}
VersionInfoCopyright={#AppCopyright}

; Per-user by default and therefore no elevation prompt; the mode dialog lets the user choose an
; all-users install, which is the only thing that asks for elevation. {autopf} follows that choice:
;   per user  -> {localappdata}\Programs\TigerMarkView
;   all users -> {commonpf}\TigerMarkView          (%ProgramFiles%\TigerMarkView)
; UsePreviousPrivileges (on by default) means an upgrade re-uses the mode of the existing install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline dialog
DefaultDirName={autopf}\{#AppName}

; One Start Menu shortcut, placed directly in Programs rather than in a folder of its own.
DisableProgramGroupPage=yes

; x64 only: the app is published win-x64 and TigerMarkView.Pdf hosts the x64 WebView2 loader.
; x64compatible also covers Arm64 Windows 11's x64 emulation.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 10 1607 is the floor for the .NET 10 runtime the app needs.
MinVersion=10.0.14393

UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile={#AddBackslash(SourcePath)}..\src\TigerMarkView\Assets\TMV.ico
; The licence that actually ships, not a second copy of it.
LicenseFile={#AddBackslash(SourceDir)}Docs\LICENSE.txt

WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#AppName}-{#AppVersion}-win-x64-setup

; No file associations in this phase — .md stays with whatever the user already uses.
ChangesAssociations=no
ChangesEnvironment=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; PATH is checked by default because this is the complete GUI + CLI product. The code below owns one
; exact raw entry, avoids claiming a pre-existing entry, and removes only the entry it inserted.
Name: "addtopath"; Description: "Add the TigerMarkView install directory to PATH"; \
    GroupDescription: "Command-line integration:"; Flags: checkedonce
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole publish output, minus debug symbols and XML doc files — around 105 MB of .pdb that the
; applications never read. Everything else (TigerMarkView.exe, tiger-mark.exe, Avalonia, TigerCli,
; Markdig, the WebView2 loader, Docs\HELP.md, Docs\THIRD-PARTY-NOTICES.md, Docs\LICENSE.txt) ships as
; staged, so the GUI, CLI, PDF export, and offline Help are one product installation.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.xml"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Comment: "{#AppDescription}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Comment: "{#AppDescription}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; \
    Flags: nowait postinstall skipifsilent

; Deliberately no [UninstallDelete]. Settings live at %LocalAppData%\TigerMarkView\settings.json,
; outside {app}, and uninstalling must leave them (and the WebView2 user data folder beside them)
; alone, so reinstalling restores the user's theme, reload mode, editor, recent files, and window
; placement. Only files this installer wrote are removed.

[Code]

const
  { Microsoft's documented detection key for the Evergreen WebView2 Runtime. }
  WebView2ClientKey = 'Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  DirectoryAttribute = $10;
  UserEnvironmentKey = 'Environment';
  MachineEnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  PathValueName = 'Path';
  PathOwnershipKey = 'Software\{#AppPublisher}\{#AppName}\Installer';
  PathOwnershipValue = 'OwnedPathEntry';

function EnvironmentRoot: Integer;
begin
  if IsAdminInstallMode then
    Result := HKLM
  else
    Result := HKCU;
end;

function EnvironmentKey: String;
begin
  if IsAdminInstallMode then
    Result := MachineEnvironmentKey
  else
    Result := UserEnvironmentKey;
end;

function NormalizePathEntry(const Value: String): String;
begin
  Result := Trim(Value);
  while (Length(Result) > 3) and
        ((Result[Length(Result)] = '\') or (Result[Length(Result)] = '/')) do
    Delete(Result, Length(Result), 1);
end;

function SamePathEntry(const Left, Right: String): Boolean;
begin
  Result := CompareText(NormalizePathEntry(Left), NormalizePathEntry(Right)) = 0;
end;

function SameExactPathEntry(const Left, Right: String): Boolean;
begin
  Result := CompareText(Trim(Left), Trim(Right)) = 0;
end;

function PathContainsEntry(const PathValue, Entry: String): Boolean;
var
  Remaining, Segment: String;
  Separator: Integer;
begin
  Result := False;
  Remaining := PathValue;
  while True do
  begin
    Separator := Pos(';', Remaining);
    if Separator = 0 then
      Segment := Remaining
    else
      Segment := Copy(Remaining, 1, Separator - 1);

    if SamePathEntry(Segment, Entry) then
    begin
      Result := True;
      Exit;
    end;

    if Separator = 0 then
      Exit;
    Delete(Remaining, 1, Separator);
  end;
end;

function RemoveFirstPathEntry(const PathValue, Entry: String; var Removed: Boolean): String;
var
  Remaining, Segment: String;
  Separator: Integer;
  FirstOutput, ExactEntryExists, Matches: Boolean;
begin
  Result := '';
  Removed := False;
  FirstOutput := True;
  Remaining := PathValue;
  ExactEntryExists := False;

  { An equivalent entry may have been added by the user after installation. Prefer the exact raw
    entry we recorded, so uninstall never removes that later lookalike while leaving our own entry. }
  while True do
  begin
    Separator := Pos(';', Remaining);
    if Separator = 0 then
      Segment := Remaining
    else
      Segment := Copy(Remaining, 1, Separator - 1);
    if SameExactPathEntry(Segment, Entry) then
      ExactEntryExists := True;
    if Separator = 0 then
      Break;
    Delete(Remaining, 1, Separator);
  end;

  Remaining := PathValue;

  while True do
  begin
    Separator := Pos(';', Remaining);
    if Separator = 0 then
      Segment := Remaining
    else
      Segment := Copy(Remaining, 1, Separator - 1);

    if ExactEntryExists then
      Matches := SameExactPathEntry(Segment, Entry)
    else
      Matches := SamePathEntry(Segment, Entry);

    if (not Removed) and Matches then
      Removed := True
    else
    begin
      if not FirstOutput then
        Result := Result + ';';
      Result := Result + Segment;
      FirstOutput := False;
    end;

    if Separator = 0 then
      Exit;
    Delete(Remaining, 1, Separator);
  end;
end;

procedure AddOwnedPathEntry;
var
  Root: Integer;
  Key, ExistingPath, OwnedEntry, Entry: String;
begin
  Root := EnvironmentRoot;
  Key := EnvironmentKey;
  Entry := ExpandConstant('{app}');
  RegQueryStringValue(Root, Key, PathValueName, ExistingPath);

  if PathContainsEntry(ExistingPath, Entry) then
  begin
    { Preserve ownership across upgrades, but never claim a matching entry another product or the
      user created before TigerMarkView. }
    if RegQueryStringValue(Root, PathOwnershipKey, PathOwnershipValue, OwnedEntry) and
       SamePathEntry(OwnedEntry, Entry) then
      RegWriteStringValue(Root, PathOwnershipKey, PathOwnershipValue, Entry);
    Exit;
  end;

  if (ExistingPath <> '') and (ExistingPath[Length(ExistingPath)] <> ';') then
    ExistingPath := ExistingPath + ';';
  if not RegWriteExpandStringValue(Root, Key, PathValueName, ExistingPath + Entry) then
    RaiseException('Could not add TigerMarkView to PATH.');
  if not RegWriteStringValue(Root, PathOwnershipKey, PathOwnershipValue, Entry) then
    RaiseException('Could not record TigerMarkView PATH ownership.');
end;

procedure RemoveOwnedPathEntry;
var
  Root: Integer;
  Key, ExistingPath, UpdatedPath, OwnedEntry: String;
  Removed: Boolean;
begin
  Root := EnvironmentRoot;
  Key := EnvironmentKey;
  if not RegQueryStringValue(Root, PathOwnershipKey, PathOwnershipValue, OwnedEntry) then
    Exit;

  if RegQueryStringValue(Root, Key, PathValueName, ExistingPath) then
  begin
    UpdatedPath := RemoveFirstPathEntry(ExistingPath, OwnedEntry, Removed);
    if Removed and not RegWriteExpandStringValue(Root, Key, PathValueName, UpdatedPath) then
      RaiseException('Could not remove TigerMarkView from PATH.');
  end;
  RegDeleteValue(Root, PathOwnershipKey, PathOwnershipValue);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('addtopath') then
      AddOwnedPathEntry
    else
      RemoveOwnedPathEntry;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveOwnedPathEntry;
end;

function DesktopRuntimeFoundUnder(const DotNetRoot: String): Boolean;
var
  SharedDir: String;
  FindRec: TFindRec;
begin
  Result := False;
  if DotNetRoot = '' then
    Exit;
  SharedDir := AddBackslash(DotNetRoot) + 'shared\Microsoft.WindowsDesktop.App';
  if not DirExists(SharedDir) then
    Exit;
  { The runtime rolls forward within a major version only, so net10.0 needs a 10.x directory. }
  if FindFirst(AddBackslash(SharedDir) + '10.*', FindRec) then
  try
    repeat
      if (FindRec.Attributes and DirectoryAttribute) <> 0 then
      begin
        Result := True;
        Break;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

function DesktopRuntimeInstalled: Boolean;
begin
  Result := DesktopRuntimeFoundUnder(ExpandConstant('{commonpf64}') + '\dotnet') or
            DesktopRuntimeFoundUnder(GetEnv('DOTNET_ROOT'));
end;

function WebView2RuntimeInstalled: Boolean;
var
  Version: String;
begin
  Result := (RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\' + WebView2ClientKey, 'pv', Version) or
             RegQueryStringValue(HKLM, 'SOFTWARE\' + WebView2ClientKey, 'pv', Version) or
             RegQueryStringValue(HKCU, 'SOFTWARE\' + WebView2ClientKey, 'pv', Version)) and
            (Version <> '') and (Version <> '0.0.0.0');
end;

{ Warn about a missing prerequisite instead of letting the app fail to start with no explanation.
  Nothing is downloaded or installed here — this only names what is missing and where it comes from,
  and the user may continue, since they may be about to install it themselves. }
function InitializeSetup: Boolean;
var
  NL, Missing: String;
begin
  Result := True;
  { Chr(13) + Chr(10) rather than #13#10: ISPP reads a line whose first non-blank character is '#'
    as a preprocessor directive, so a line-leading #13#10 fails to compile. }
  NL := Chr(13) + Chr(10);
  Missing := '';

  if not DesktopRuntimeInstalled then
    Missing := Missing + NL +
      '  - .NET 10 Desktop Runtime (x64)' + NL +
      '    https://dotnet.microsoft.com/download/dotnet/10.0' + NL;

  if not WebView2RuntimeInstalled then
    Missing := Missing + NL +
      '  - Microsoft Edge WebView2 Runtime' + NL +
      '    https://developer.microsoft.com/microsoft-edge/webview2/' + NL;

  if Missing <> '' then
    Result := SuppressibleMsgBox(
      '{#AppName} needs the following, which this installer does not include and could not find:' +
      NL + Missing + NL +
      'You can install {#AppName} now and add the missing component afterwards, but it will not ' +
      'start until you do.' + NL + NL +
      'Continue with the installation?',
      mbConfirmation, MB_YESNO, IDYES) = IDYES;
end;
