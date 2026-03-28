#SingleInstance Force
#Requires AutoHotkey v2.0
#NoTrayIcon
;@Ahk2Exe-SetName        IDV-Login
;@Ahk2Exe-SetVersion     1.0.0
;@Ahk2Exe-SetCompanyName Zerin
;@Ahk2Exe-SetCopyright   Copyright © 2026 Zerin
;@Ahk2Exe-SetDescription IDV-Login
;@Ahk2Exe-SetLanguage    0x0804
; 日志文件路径
global appLogFile := A_ScriptDir . "\LoginApp_log.txt"

WriteLog(Message) {
    global appLogFile
    if (!FileExist(appLogFile))
        FileAppend("", appLogFile, "UTF-8")
    CurrentTime := A_Now
    CurrentTime := FormatTime(CurrentTime, "yyyy-MM-dd HH:mm:ss")
    FileAppend("[" . CurrentTime . "] " . Message . "`n", appLogFile, "UTF-8")
}
WriteLog("")
WriteLog("程序启动")

; 全局变量
global logFile := A_ScriptDir . "\run\log.txt"
global lastLogSize := 0
global proxyStatus := "登录代理运行中"
global portOccupied := false
global gameStarted := false

; 确保 run\run_data 目录存在
DirCreate(A_ScriptDir . "\run")

; 确保 log.txt 文件存在
if (!FileExist(logFile)) {
    FileAppend("", logFile)
}

; 创建GUI窗口
MyGui := Gui(, "IDV-Login")
MyGui.SetFont("s14", "Microsoft YaHei")
myGui.Add("Text", "x10 y10 w460 h25", "第五人格登录器")
MyGui.SetFont("s12", "Microsoft YaHei")
MyGui.Add("Text", "x10 y42 w60 h20", "状态:")
statusText := MyGui.Add("Text", "x55 y42 w120 h20", "登录代理运行中")
MyGui.Add("Text", "x200 y42 w60 h20", "版本:")
MyGui.Add("Text", "x245 y42 w120 h20", "V1.0.0")
MyGui.Add("Text", "x325 y42 w60 h20", "帮助:")
webLink := MyGui.Add("Text", "x370 y42 w80 h20 cBlue", "网页链接")
webLink.OnEvent("Click", (*) => Run("https://zcn2uzvdaiwh.feishu.cn/wiki/space/7611520609637420221?ccm_open_type=lark_wiki_spaceLink&open_tab_from=wiki_home"))
MyGui.Add("Text", "x10 y70 w60 h20", "请求:")
MyGui.SetFont("s11", "Microsoft YaHei")
requestList := MyGui.Add("Edit", "x10 y99 w440 h200 -Wrap +Multi +ReadOnly +VScroll +Background0xFDFDFD")
MyGui.Add("Button", "x460 y99 w100 h50", "启动登录代理").OnEvent("Click", RunRun)
MyGui.Add("Button", "x460 y174 w100 h50", "停止登录代理").OnEvent("Click", KillRun)
MyGui.Add("Button", "x460 y249 w100 h50", "启动游戏").OnEvent("Click", StartGame)

; 窗口显示后，设置定时器 , 50ms 后清除选择状态
SetTimer(ClearSelection, 50)

MyGui.Show("w570 h310")

; 开始定时检测run.exe的运行情况（1000ms间隔）
SetTimer(CheckRunStatus, 1000)

RunRun(*) {
    WriteLog("点击了启动登录代理按钮")
    RunWait("taskkill /F /IM run.exe", "", "Hide")
    ; 执行同目录下的 run.exe，使用 Hide 参数静默执行
    Run(A_ScriptDir . "\run\run.exe", A_ScriptDir, "Hide")
    ; 重置日志文件大小记录，确保重新启动时能正确显示日志
    Sleep(200)
    global lastLogSize
    lastLogSize := 0
    WriteLog("登录代理已启动")
}

KillRun(*) {
    WriteLog("点击了停止登录代理按钮")
    RunWait("taskkill /F /IM run.exe", "", "Hide")
    ; 清屏一次
    global requestList
    requestList.Value := ""
    ; 更新状态显示
    global proxyStatus, statusText
    proxyStatus := "登录代理已停止"
    statusText.Value := "登录代理已停止"
    WriteLog("登录代理已停止")
}

StartGame(*) {
    WriteLog("点击了启动游戏按钮")
    Pos := InStr(A_ScriptDir, "idv-login",, 1)
    if (Pos > 0 && FileExist(DwrgPath := SubStr(A_ScriptDir, 1, Pos - 1) . "dwrg.exe")) {
        WriteLog("启动 dwrg.exe: " . DwrgPath)
        Run(DwrgPath " --start_from_launcher=1 --is_multi_start", SubStr(A_ScriptDir, 1, Pos - 1))
        WriteLog("游戏已启动")
    } else {
        WriteLog("dwrg.exe 不存在")
    }
}

LaunchTimer() {
    WriteLog("定时器触发，启动登录代理")
    RunRun()
}

; 启动定时器，只执行一次
SetTimer(LaunchTimer, -500)

; 打开软件后等待1秒再开始读取log文件，防止读取到上次的日志
SetTimer(StartReadingLog, 1000)

; 开始定时轮询的函数
StartReadingLog() {
    WriteLog("开始读取日志文件")
    SetTimer(ReadLogFile, 100)
    SetTimer(StartReadingLog, 0)
}

; 清除选择状态的函数
ClearSelection() {
    global requestList
    requestList.SelStart := StrLen(requestList.Value)
    requestList.SelLength := 0
    SetTimer(ClearSelection, 0) ; 停止定时器
}

; 实时读取日志文件的函数
ReadLogFile() {
    global logFile, lastLogSize, requestList, portOccupied, gameStarted
    
    if (!FileExist(logFile))
        return
    try
        fileSize := FileGetSize(logFile)
    catch
        return
    
    if (fileSize != lastLogSize) {
        try
            logContent := FileRead(logFile, "UTF-8")
        catch
            return
        
        currentContent := requestList.Value
        if (logContent != currentContent) {
            WriteLog("日志文件有更新，内容长度: " . StrLen(logContent))
            requestList.Value := logContent
            requestList.SelStart := StrLen(requestList.Value)
            requestList.SelLength := 0
            SendMessage(0x0115, 7, 0, requestList)
            
            lines := StrSplit(logContent, "`n")
            for line in lines {
                if (InStr(line, "443 端口被占用")) {
                    WriteLog("检测到 443 端口被占用")
                    processName := ""
                    pid := ""
                    if (InStr(line, "=>")) {
                        parts := StrSplit(line, "=>")
                        processInfo := Trim(parts[2])
                        if (InStr(processInfo, "=")) {
                            processParts := StrSplit(processInfo, "=")
                            processName := Trim(processParts[1])
                            pid := Trim(processParts[2])
                        } else {
                            processName := processInfo
                        }
                    }
            
                    if (processName = "run.exe") {
                        continue
                    }
                    portOccupied := true
                    msgContent := processName . " 占用了 443 端口 即将强制终止 "
                    WriteLog("弹窗提示: " . msgContent)
                    result := DllCall("user32\MessageBox", "Ptr", MyGui.Hwnd, "Str", msgContent, "Str", "443 端口被占用", "UInt", 0x10)
                    
                    if result = 1 {
                        WriteLog("用户选择终止进程: " . processName)
                        RunWait("*RunAs cmd.exe /c taskkill /F /PID " . pid, "", "Hide")
                        Sleep(1000)
                        RunRun()
                    }
                    break
                } else if (InStr(line, "初始化程序")) {
                    WriteLog("检测到需要初始化程序")
                    result := DllCall("user32\MessageBox", "Ptr", MyGui.Hwnd, "Str", "未进行初始化 将运行初始化程序", "Str", "未初始化", "UInt", 0x10)
                    if result = 1 {
                        WriteLog("用户选择运行初始化程序")
                        RunWait("*RunAs " . A_ScriptDir . "\init\init.exe", A_ScriptDir)
                        WriteLog("初始化程序执行完成")
                    }
                    break
                }
            }
        }
        
        lastLogSize := fileSize
    }
    
    try
        logContent := FileRead(logFile, "UTF-8")
    catch
        return
    
    lines := StrSplit(logContent, "`n")
    for line in lines {
        if (InStr(line, "代理服务运行中") && !gameStarted && !portOccupied) {
            WriteLog("检测到代理服务运行中，准备启动游戏")
            StartGame()
            gameStarted := true
            WriteLog("游戏已启动")
            break
        }
    }
}

; 关闭窗口退出程序
MyGui.OnEvent("Close", CloseGui)

CloseGui(*) {
    WriteLog("关闭窗口，退出程序")
    ; 软件退出时停止登录代理
    KillRun()
    WriteLog("程序已退出")
    ExitApp()
}

; 检测run.exe运行状态的函数
CheckRunStatus() {
    global proxyStatus, statusText
    
    pid := ProcessExist("run.exe")
    if (pid > 0) {
        if (proxyStatus != "登录代理运行中") {
            proxyStatus := "登录代理运行中"
            statusText.Value := "登录代理运行中"
            WriteLog("检测到 run.exe 正在运行")
        }
    } else {
        if (proxyStatus != "登录代理已停止") {
            proxyStatus := "登录代理已停止"
            statusText.Value := "登录代理已停止"
            WriteLog("检测到 run.exe 已停止")
        }
    }
}
