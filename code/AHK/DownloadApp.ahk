#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; 日志文件路径
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
    Url := "https://loadingbaycn.webapp.163.com/app/v1/file_distribution/download_app?app_id=73"
    
    try
    {
        ; 创建 HTTP 请求对象
        HttpRequest := ComObject("WinHttp.WinHttpRequest.5.1")
        HttpRequest.Open("GET", Url)
        WriteLog("发送网络请求: " . Url)
        HttpRequest.Send()
        
        Status := HttpRequest.Status
        WriteLog("网络请求状态: " . Status)
        if (Status = 200)
        {
            JsonText := HttpRequest.ResponseText
            ; 限制 JSON 日志信息为前 250 个字符
            JsonLog := StrLen(JsonText) > 250 ? SubStr(JsonText, 1, 250) . "..." : JsonText
            WriteLog("获取到的 JSON 数据: " . JsonLog)
            
            ; 使用简单的字符串操作提取 version_code
            ; 查找 version_code 字段
            SearchStr := "version_code"
            Pos := InStr(JsonText, SearchStr)
            if (Pos > 0)
            {
                WriteLog("找到 version_code 字段，位置: " . Pos)
                ; 找到冒号
                ColonPos := InStr(JsonText, ":",, Pos)
                if (ColonPos > 0)
                {
                    WriteLog("找到冒号，位置: " . ColonPos)
                    ; 找到值的开始（跳过空格和引号）
                    ValueStart := ColonPos + 1
                    while (ValueStart <= StrLen(JsonText) && (SubStr(JsonText, ValueStart, 1) = " " || SubStr(JsonText, ValueStart, 1) = "`""))
                    {
                        ValueStart++
                    }
                    WriteLog("值的开始位置: " . ValueStart)
                    
                    ; 找到值的结束（下一个引号）
                    ValueEnd := InStr(JsonText, "`"" ,, ValueStart)
                    if (ValueEnd > ValueStart)
                    {
                        WriteLog("值的结束位置: " . ValueEnd)
                        ; 提取 version_code 值
                        VersionCode := SubStr(JsonText, ValueStart, ValueEnd - ValueStart)
                        WriteLog("提取到的 version_code: " . VersionCode)
                        return VersionCode
                    }
                    else
                    {
                        WriteLog("未找到值的结束位置")
                    }
                }
                else
                {
                    WriteLog("未找到冒号")
                }
            }
            else
            {
                WriteLog("未找到 version_code 字段")
            }
        }
        else
        {
            WriteLog("网络请求失败，状态码: " . Status)
        }
    }
    catch as e
    {
        WriteLog("网络请求错误: " . e.message)
    }
    
    return ""
}

; Base64 编码函数
Base64Encode(str) {
    try
    {
        ; 直接使用 PowerShell 命令进行 Base64 编码
        ; 创建临时文件
        tempFile := A_ScriptDir . "\DownloadApp\base64_temp.txt"
        WriteLog("创建临时文件: " . tempFile)
        ; 检查文件是否存在，存在则删除
        if (FileExist(tempFile)) {
            WriteLog("删除已存在的临时文件")
            FileDelete(tempFile)
        }
        ; 确保临时目录存在
        SplitPath(tempFile, , &dir)
        WriteLog("确保临时目录存在: " . dir)
        DirCreate(dir)
        ; 写入字符串到临时文件
        WriteLog("写入字符串到临时文件")
        FileAppend(str, tempFile, "UTF-8")
        
        ; 执行 PowerShell 命令进行 Base64 编码（静默模式）
        outputFile := A_ScriptDir . "\DownloadApp\base64_output.txt"
        ; 构建 PowerShell 命令
        ; 使用 -NoProfile 参数减少启动时间，-ExecutionPolicy Bypass 确保执行权限
        powershellCommand := 'powershell -NoProfile -ExecutionPolicy Bypass -Command "[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path \"' . tempFile . '\" -Raw -Encoding UTF8))) | Out-File -FilePath \"' . outputFile . '\" -Encoding UTF8 -Force"'
        WriteLog("执行 PowerShell 命令: " . powershellCommand)
        ; 使用 Run 命令并设置隐藏窗口
        RunWait(powershellCommand, , "Hide")
        WriteLog("PowerShell 命令执行完成")
        ; 检查输出文件是否存在
        if (FileExist(outputFile)) {
            WriteLog("输出文件已生成，大小: " . FileGetSize(outputFile) . " 字节")
        } else {
            WriteLog("输出文件未生成")
        }
        
        ; 读取编码结果
        base64Str := ""
        if (FileExist(outputFile)) {
            try {
                ; 使用 FileRead 函数的正确语法
                base64Str := FileRead(outputFile, "UTF-8")
                WriteLog("获取到的 Base64 编码结果: " . base64Str)
            } catch as e {
                WriteLog("读取输出文件错误: " . e.message)
            }
        } else {
            WriteLog("未找到输出文件")
        }
        
        ; 清理临时文件
        if (FileExist(tempFile)) {
            WriteLog("清理临时文件")
            FileDelete(tempFile)
        }
        if (FileExist(outputFile)) {
            FileDelete(outputFile)
        }
        
        ; 移除换行符
        base64Str := StrReplace(base64Str, "`r`n")
        WriteLog("处理后的 Base64 编码结果: " . base64Str)
        
        Return base64Str
    }
    catch as e
    {
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
; 网页链接（超链接）
webLink := MainGui.Add("Text", "x370 y42 w80 h20 cBlue", "网页链接")
webLink.OnEvent("Click", (*) => Run("https://zcn2uzvdaiwh.feishu.cn/wiki/space/7611520609637420221?ccm_open_type=lark_wiki_spaceLink&open_tab_from=wiki_home"))
MainGui.Add("Text", "x10 y79 w80 h20", "下载路径:")
MainGui.SetFont("s12", "Microsoft YaHei")
; 创建 Edit 控件
pathEdit := MainGui.Add("Edit", "x90 y79 w400 h25 +ReadOnly +Background0xFDFDFD", A_ScriptDir)

; 添加焦点事件 - 使用 SendMessage 取消选择
pathEdit.OnEvent("Focus", CancelSelection)

; 取消选择的函数
CancelSelection(ctrl, *) {
    ; 发送 EM_SETSEL 消息 (0xB1) 来取消选择
    ; wParam=0xFFFF, lParam=0xFFFF 表示选择全部
    ; 我们用 wParam=-1, lParam=-1 表示取消选择（光标在末尾）
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
    ; 打开脚本所在目录
    Run("explorer.exe " . A_ScriptDir)
}
StartGameDownload(*)
{
    ; 开始下载日志
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
        WriteLog("Base64 编码结果: " . pathBase64)
        
        ; 获取目标版本号
        WriteLog("开始获取目标版本号...")
        targetVersion := GetTargetVersion()
        WriteLog("获取到的版本号: " . (targetVersion ? targetVersion : "使用默认版本号"))
        
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
        
        ; 启动程序
        WriteLog("启动 downloadIPC.exe...")
        Run(command, A_ScriptDir, "Hide")
        WriteLog("下载程序启动成功")
        
        ; 等待 5 秒，检测 downloadIPC.exe 进程
        WriteLog("等待 5 秒，检测 downloadIPC.exe 进程...")
        Sleep(5000)
        
        ; 检测 downloadIPC.exe 进程
        if (CheckProcess("downloadIPC.exe")) {
            ; 更新状态为正在下载
            statusText.Text := "正在下载"
            WriteLog("检测到 downloadIPC.exe 进程，状态更新为正在下载")
            
            ; 设置定时器，每 1 秒检测一次 downloadIPC.exe 进程
            SetTimer(CheckDownloadProcess, 1000)
        } else {
            WriteLog("未检测到 downloadIPC.exe 进程")
            ; 直接标记为下载完成
            statusText.Text := "下载完成"
            WriteLog("downloadIPC.exe 进程未启动，状态更新为下载完成")
            
            ; 弹窗提示
            MsgBox("下载已完成", "提示", "OK Iconi")
            
            ; 结束 UI_Server.exe 进程
            ProcessClose("UI_Server.exe")
            WriteLog("UI_Server.exe 进程已结束")
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
SetTimer(ReadProgressFile, 1000) ; 每1秒读取一次

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
    ; 进度文件路径
    progressFile := A_ScriptDir . "\DownloadApp\UI_Server\UI_Server_data\Download_Progress.txt"
    
    ; 检查文件是否存在
    if (FileExist(progressFile)) {
        try {
            ; 读取文件内容
            fileContent := FileRead(progressFile)
            
            ; 检查文件内容是否为空
            if (fileContent != "") {
                ; 去除换行符和首尾空格
                fileContent := StrReplace(fileContent, "`r`n")
                fileContent := StrReplace(fileContent, "`n")
                fileContent := Trim(fileContent)
                
                ; 解析文件内容
                ; 格式: 下载进度|下载速度|已下载|总大小|构建进度|构建速度|已构建|总大小
                parts := StrSplit(fileContent, "|")
                
                ; 确保有足够的部分
                if (parts.Length >= 8) {
                    ; 提取各个值
                    downloadPercent := parts[1]
                    downloadRate := parts[2]
                    downloaded := parts[3]
                    totalSize := parts[4]
                    buildPercent := parts[5]
                    buildRate := parts[6]
                    built := parts[7]
                    buildTotalSize := parts[8]
                    
                    ; 更新下载进度
                    MainGui["DownloadProgress"].Text := downloadPercent . "%"
                    MainGui["DownloadProgressBar"].Value := downloadPercent
                    
                    ; 更新下载速度
                    MainGui["DownloadRate"].Text := downloadRate . " MB/s"
                    
                    ; 更新已下载/总大小
                    MainGui["DownloadSize"].Text := downloaded . " GB/" . totalSize . " GB"
                    
                    ; 更新构建进度
                    MainGui["BuildProgress"].Text := buildPercent . "%"
                    MainGui["BuildProgressBar"].Value := buildPercent
                    
                    ; 更新构建速度
                    MainGui["BuildRate"].Text := buildRate . " MB/s"
                    
                    ; 更新已构建/总大小
                    MainGui["BuildSize"].Text := built . " GB/" . buildTotalSize . " GB"
                } else {
                    ; 记录分割结果
                    WriteLog("文件内容: " . fileContent)
                    WriteLog("分割后部分数量: " . parts.Length)
                    for index, part in parts {
                        WriteLog("部分 " . index . ": " . part)
                    }
                }
            } else {
                WriteLog("文件内容为空")
            }
        } catch as e {
            WriteLog("读取进度文件错误: " . e.message)
        }
    }
}