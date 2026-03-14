-- build init
MSBuild init.csproj /p:Configuration=Release

-- build run
MSBuild run.csproj /p:Configuration=Release

-- build UI_Server
pyinstaller -w -i 16.ico --add-data "16.ico;." --upx-dir=. --contents-directory "UI_Server_data" UI_Server.py

-- 环境要求
init/run：
- .NET Framework 4.7.2
- MSBuild 或 VS 2017+

UI_Server.py：
- Python 3.6+
- pip install pyzmq pyinstaller

DownloadApp.ahk / LoginApp.ahk：
- AutoHotkey v2.0+

-- build-tree
D:.
├─DownloadApp.exe
├─DownloadApp/
│  ├─downloadIPC.exe
│  ├─OrbitSDK.dll
│  └─UI_Server/
│     ├─UI_Server.exe
│     └─UI_Server_data/
└─idv-login/
   ├─dwrg.ico
   ├─LoginApp.exe
   ├─init/
   │  ├─init.exe
   │  └─init.exe.config
   └─run/
      ├─run.exe
      └─run.exe.config