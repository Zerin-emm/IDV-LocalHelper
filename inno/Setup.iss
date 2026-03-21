#define MyAppName "IDV-LocalHelper"
#define MyAppVersion "1.0"

[Setup]
AppId=Unused
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName=D:\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=D:\windows\Desktop\LICENSE.txt
PrivilegesRequired=lowest
OutputDir=D:\windows\Desktop\innosetup_outfile
OutputBaseFilename=IDV-LocalHelper
SolidCompression=yes
WizardStyle=classic dynamic windows11
CreateUninstallRegKey=no

[Languages]
Name: "chinese"; MessagesFile: "compiler:Languages\Chinese.isl"

[Files]
Source: "D:\windows\Desktop\Identity-V\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\IDV-LocalHelper"; Filename: "{app}\idv-login\LoginApp.exe"; IconFilename: "{app}\idv-login\dwrg.ico"
Name: "{autodesktop}\IDV-LocalHelper"; Filename: "{app}\idv-login\LoginApp.exe"; IconFilename: "{app}\idv-login\dwrg.ico"

[Registry]
Root: HKA64; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\IDV-LocalHelper"; Flags: uninsdeletekey
Root: HKA64; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\IDV-LocalHelper"; ValueType: string; ValueName: "DisplayName"; ValueData: "{#MyAppName} {#MyAppVersion}"
Root: HKA64; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\IDV-LocalHelper"; ValueType: string; ValueName: "DisplayVersion"; ValueData: "{#MyAppVersion}"
Root: HKA64; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\IDV-LocalHelper"; ValueType: string; ValueName: "UninstallString"; ValueData: """{app}\unins000.exe"""
Root: HKA64; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\IDV-LocalHelper"; ValueType: string; ValueName: "DisplayIcon"; ValueData: "{app}\DownloadApp.exe,0"
Root: HKA64; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\IDV-LocalHelper"; ValueType: string; ValueName: "InstallLocation"; ValueData: "{app}"

[Code]

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssDone then
  begin
    ExecAsOriginalUser(ExpandConstant('{app}\DownloadApp.exe'), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
  end;
end;

procedure DeleteAppDir();
begin
  if DelTree(ExpandConstant('{app}'), True, True, True) then
    Log('应用程序目录删除成功')
  else
    Log('应用程序目录删除失败，可能仍有文件占用或权限不足');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usDone then
  begin
    DeleteAppDir();
  end;
end;

[UninstallRun]
Filename: "cmd.exe"; \
    Parameters: "/c cd /d ""{app}"" && 删除证书.bat"; \
    Flags: runascurrentuser runhidden waituntilterminated skipifdoesntexist; \
    StatusMsg: "正在清理证书，请稍候..."; \
    RunOnceId: "DeleteIdentityVCert"