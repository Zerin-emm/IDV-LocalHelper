#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; 日志文件路径
progressFile := A_ScriptDir . "\DownloadApp\UI_Server\UI_Server_data\Download_Progress.txt"
LogFile := A_ScriptDir . "\DownloadApp\DownloadApp_log.txt"

; 写入日志的函数
WriteLog(Message) {
    if (!FileExist(LogFile))
        FileAppend("", LogFile, "UTF-8")
    CurrentTime := A_Now
    CurrentTime := FormatTime(CurrentTime, "yyyy-MM-dd HH:mm:ss")
    FileAppend("[" . CurrentTime . "] " . Message . "`n", LogFile, "UTF-8")
}

; 检测进程是否存在
CheckProcess(processName) {
    return ProcessExist(processName)
}

; 关闭进程
ProcessClose(processName) {
    RunWait("taskkill /F /IM " . processName, , "Hide")
}

; 获取目标版本号
GetTargetVersion() {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", "https://loadingbaycn.webapp.163.com/app/v1/file_distribution/download_app?app_id=73")
        req.Send()
        
        if (req.Status = 200) {
            if (RegExMatch(req.ResponseText, '"version_code"\s*:\s*"([^"]+)"', &m)) {
                WriteLog("获取到的版本号: " . m[1])
                return m[1]
            }
        }
        WriteLog("获取版本号失败，状态码: " . req.Status)
    } catch as e {
        WriteLog("网络请求错误: " . e.message)
    }
    return ""
}

; Base64 编码函数
Base64Encode(str) {
    try {
        stream := ComObject("ADODB.Stream")
        stream.Type := 2
        stream.Charset := "utf-8"
        stream.Open()
        stream.WriteText(str)
        stream.Position := 0
        stream.Type := 1
        bytes := stream.Read()
        stream.Close()
        
        xml := ComObject("Msxml2.DOMDocument")
        element := xml.createElement("b64")
        element.dataType := "bin.base64"
        element.nodeTypedValue := bytes
        result := element.text
        
        if (SubStr(result, 1, 4) = "77u/") {
            result := SubStr(result, 5)
        }
        
        WriteLog("Base64 编码结果: " . result)
        return result
    } catch as e {
        WriteLog("Base64 编码错误: " . e.message)
        return ""
    }
}
    
MainGui := Gui(, "IDV-Download")
MainGui.SetFont("s14", "Microsoft YaHei")
MainGui.Add("Text", "x10 y10 w460 h25", "第五人格下载器")
MainGui.SetFont("s12", "Microsoft YaHei")
MainGui.Add("Text", "x10 y42 w60 h20", "状态:")
statusText := MainGui.Add("Text", "x55 y42 w120 h20", "未下载")
MainGui.Add("Text", "x200 y42 w60 h20", "版本:")
MainGui.Add("Text", "x245 y42 w120 h20", "V1.0.0")
MainGui.Add("Text", "x325 y42 w60 h20", "帮助:")
webLink := MainGui.Add("Text", "x370 y42 w80 h20 cBlue", "网页链接")
webLink.OnEvent("Click", (*) => Run("https://zcn2uzvdaiwh.feishu.cn/wiki/URouw4itXiSSoAkxLirchjDHnWe"))
MainGui.Add("Text", "x10 y79 w80 h20", "下载路径:")
MainGui.SetFont("s12", "Microsoft YaHei")
pathEdit := MainGui.Add("Edit", "x90 y79 w400 h25 +ReadOnly +Background0xFDFDFD", A_ScriptDir)

; 添加焦点事件 - 使用 SendMessage 取消选择
pathEdit.OnEvent("Focus", CancelSelection)

; 取消选择的函数
CancelSelection(ctrl, *) {
    SendMessage(0xB1, -1, -1, ctrl)
}
MainGui.SetFont("s12", "Microsoft YaHei")
MainGui.Add("Text", "x10 y109 w70 h20", "下载进度:")
MainGui.Add("Text", "x150 y109 w70 h20", "下载速度:")
MainGui.Add("Text", "x230 y109 w100 h20 vDownloadRate", "0 MB/s")
MainGui.Add("Text", "x10 y139 w150 h20", "已下载/总大小:")
MainGui.Add("Text", "x140 y139 w150 h20 vDownloadSize", "0 GB/0 GB")
MainGui.Add("Text", "x90 y109 w50 h20 vDownloadProgress", "0%")
MainGui.Add("Progress", "x10 y169 w400 h30 vDownloadProgressBar", 0)
MainGui.Add("Text", "x10 y209 w70 h20", "构建进度:")
MainGui.Add("Text", "x150 y209 w70 h20", "构建速度:")
MainGui.Add("Text", "x230 y209 w100 h20 vBuildRate", "0 MB/s")
MainGui.Add("Text", "x10 y239 w150 h20", "已构建/总大小:")
MainGui.Add("Text", "x140 y239 w150 h20 vBuildSize", "0 GB/0 GB")
MainGui.Add("Text", "x90 y209 w50 h20 vBuildProgress", "0%")
MainGui.Add("Progress", "x10 y269 w400 h30 vBuildProgressBar", 0)
MainGui.Add("Button", "x460 y174 w100 h50", "打开文件夹").OnEvent("Click", OpenFolder)
MainGui.Add("Button", "x460 y249 w100 h50", "开始下载").OnEvent("Click", StartGameDownload)
OpenFolder(*)
{
    Run("explorer.exe " . A_ScriptDir)
}
StartGameDownload(*)
{
    WriteLog("开始下载...")
    
    try
    {
        ; 启动 UI_Server.exe
        uiServerPath := A_ScriptDir . "\DownloadApp\UI_Server\UI_Server.exe"
        WriteLog("启动 UI_Server.exe...")
        Run(uiServerPath, A_ScriptDir, "Hide")
        WriteLog("UI_Server.exe 启动成功")
        
        ; 先获取 Base64 编码的路径
        WriteLog("开始 Base64 编码路径: " . A_ScriptDir)
        pathBase64 := Base64Encode(A_ScriptDir)
        
        ; 获取目标版本号
        WriteLog("开始获取目标版本号...")
        targetVersion := GetTargetVersion()
        
        ; 构建命令行参数
        command := A_ScriptDir . "\DownloadApp\downloadIPC.exe" 
        command .= " --gameid:73"
        command .= " --contentid:434"
        command .= " --subport:1737"
        command .= " --pubport:1740"
        command .= " --path:" . pathBase64
        command .= " --env:live"
        command .= " --oversea:0"
        command .= " --targetVersion:" . (targetVersion ? targetVersion : "v3_3196_9b3234bf4a8368a7c935da5a89ebd84a")
        command .= " --originVersion:"
        command .= " --scene:1"
        command .= " --rateLimit:0"
        command .= " --sysVer:10"
        command .= " --channel:mkt-h55-official"
        command .= " --locale:zh_Hans"
        command .= " --isSSD:1"
        command .= " --isRepairMode:0"
        
        WriteLog("构建的命令行: " . command)
        
        WriteLog("启动 downloadIPC.exe...")
        Run(command, A_ScriptDir, "Hide")
        WriteLog("下载程序启动成功")
        
        WriteLog("等待 5 秒，检测 downloadIPC.exe 进程...")
        Sleep(5000)
        
        ; 检测 downloadIPC.exe 进程
        if (CheckProcess("downloadIPC.exe")) {
            statusText.Text := "正在下载"
            WriteLog("检测到 downloadIPC.exe 进程，状态更新为正在下载")
            ; 设置定时器，每 1 秒检测一次 downloadIPC.exe 进程
            SetTimer(CheckDownloadProcess, 1000)
        } else {
            WriteLog("未检测到 downloadIPC.exe 进程")
            statusText.Text := "启动失败"
            MsgBox("下载程序启动失败", "错误", "OK Iconx")
            ProcessClose("UI_Server.exe")
        }
    }
    catch as e
    {
        WriteLog("错误: " . e.message)
    }
}

; 检测 downloadIPC.exe 进程
CheckDownloadProcess() {
    if (!CheckProcess("downloadIPC.exe")) {
        ; 停止定时器
        SetTimer(CheckDownloadProcess, 0)
        
        ; 更新状态为下载完成
        statusText.Text := "下载完成"
        WriteLog("downloadIPC.exe 进程已退出，状态更新为下载完成")
        
        ; 弹窗提示
        MsgBox("下载已完成", "提示", "OK Iconi")
        
        ; 结束 UI_Server.exe 进程
        ProcessClose("UI_Server.exe")
        WriteLog("UI_Server.exe 进程已结束")
    }
}

; 添加定时器定期读取进度文件
SetTimer(ReadProgressFile, 1000)

; 添加窗口关闭事件处理
MainGui.OnEvent("Close", GuiClose)

MainGui.Show("w570 h310")
SetTimer(() => SendMessage(0xB1, -1, -1, pathEdit), -10)

; 窗口关闭事件处理函数
GuiClose(*) {
    ; 停止所有定时器
    SetTimer(ReadProgressFile, 0)
    SetTimer(CheckDownloadProcess, 0)
    
    ; 关闭 UI_Server.exe 进程
    ProcessClose("UI_Server.exe")
    ProcessClose("downloadIPC.exe")
    ; 退出脚本
    ExitApp()
}

; 读取进度文件并更新GUI
ReadProgressFile() {
    if (!FileExist(progressFile))
        return
    
    try {
        fileContent := FileRead(progressFile)
        fileContent := Trim(StrReplace(StrReplace(fileContent, "`r`n"), "`n"))
        
        if (fileContent = "")
            return
        
        parts := StrSplit(fileContent, "|")
        if (parts.Length < 8)
            return
        
        MainGui["DownloadProgress"].Text := parts[1] . "%"
        MainGui["DownloadProgressBar"].Value := parts[1]
        MainGui["DownloadRate"].Text := parts[2] . " MB/s"
        MainGui["DownloadSize"].Text := parts[3] . " GB/" . parts[4] . " GB"
        MainGui["BuildProgress"].Text := parts[5] . "%"
        MainGui["BuildProgressBar"].Value := parts[5]
        MainGui["BuildRate"].Text := parts[6] . " MB/s"
        MainGui["BuildSize"].Text := parts[7] . " GB/" . parts[8] . " GB"
    } catch {
        ; 静默失败
    }
}