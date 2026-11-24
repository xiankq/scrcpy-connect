[Setup]
AppId=dev.scrcpyconnect.scrcpy_connect
AppName=Interconnect
AppVersion={#AppVersion}
AppPublisher=Interconnect contributors
ArchitecturesAllowed={#TargetArch}
ArchitecturesInstallIn64BitMode={#TargetArch}
DefaultDirName={localappdata}\Programs\Interconnect
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Interconnect.exe
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
ArchiveExtraction=full

[Tasks]
Name: "platformtools"; Description: "Download Android Platform-Tools (ADB) from Google (requires Internet access)"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#Bundle}\*"; DestDir: "{app}"; Excludes: "scrcpy_connect.exe"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#AdbUrl}"; DestName: "platform-tools.zip"; DestDir: "{app}"; \
  Hash: "{#AdbSha256}"; ExternalSize: {#AdbExtractedBytes}; Tasks: platformtools; \
  Flags: external download extractarchive recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Interconnect"; Filename: "{app}\Interconnect.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Interconnect"; Filename: "{app}\Interconnect.exe"; WorkingDir: "{app}"; Tasks: desktopicon
