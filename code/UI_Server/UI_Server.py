# ui_server_with_progress.py
import zmq
import time
import json  # 关键：导入 json 模块
import os
import ctypes

# 完全隐藏控制台窗口
def hide_console():
    """完全隐藏控制台窗口"""
    # 获取控制台窗口句柄
    hwnd = ctypes.windll.kernel32.GetConsoleWindow()
    if hwnd:
        # 隐藏窗口
        ctypes.windll.user32.ShowWindow(hwnd, 0)  # 0 表示隐藏窗口
        # 确保窗口不会被激活
        ctypes.windll.user32.SetWindowPos(hwnd, 0, 0, 0, 0, 0, 0x0001)

# 调用函数隐藏控制台窗口
hide_console()

def parse_rate(rate_str):
    """解析速度字符串，返回以 MB/s 为单位的数值"""
    try:
        # 移除单位，只保留数字
        rate_num = float(''.join(c for c in rate_str if c.isdigit() or c == '.'))
        # 根据单位转换
        if 'KB' in rate_str:
            return round(rate_num / 1024, 2)
        elif 'MB' in rate_str:
            return round(rate_num, 2)
        elif 'GB' in rate_str:
            return round(rate_num * 1024, 2)
        else:
            return round(rate_num / (1024**2), 2)  # 默认为 B/s
    except:
        return 0.0

def main():
    context = zmq.Context()
    
    # 订阅端口 (SUB)
    receiver = context.socket(zmq.SUB)
    receiver.setsockopt(zmq.SUBSCRIBE, b"434")
    receiver.bind("tcp://127.0.0.1:1740")
    
    # 发布端口 (PUB)
    sender = context.socket(zmq.PUB)
    sender.bind("tcp://127.0.0.1:1737")
    
    # 输出文件路径
    output_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Download_Progress.txt")
    
    last_heartbeat = 0
    
    try:
        while True:
            # 接收进度
            try:
                message = receiver.recv_multipart(flags=zmq.NOBLOCK)
                topic, msg_type, payload = message
                if msg_type == b"4":
                    try:
                        data = json.loads(payload.decode('utf-8'))
                        # 下载信息
                        download_percent = data.get("ShowDownloadPercent", 0) * 100
                        download_rate_str = data.get("ShowDownloadRateStr", "0 B/s")
                        download_rate = parse_rate(download_rate_str)
                        download_total = data.get("ShowDownloadSize", 0) / (1024**3)
                        download_done = download_total * data.get("ShowDownloadPercent", 0)
                        
                        # 构建信息
                        build_percent = data.get("ShowBuildPercent", 0) * 100
                        build_rate_str = data.get("ShowBuildRateStr", "0 B/s")
                        build_rate = parse_rate(build_rate_str)
                        build_total = data.get("ShowBuildSize", 0) / (1024**3)
                        build_done = build_total * data.get("ShowBuildPercent", 0)
                        
                        # 格式化输出
                        output_line = f"{download_percent:.1f}|{download_rate:.2f}|{download_done:.2f}|{download_total:.2f}|{build_percent:.1f}|{build_rate:.2f}|{build_done:.2f}|{build_total:.2f}"
                        
                        # 使用临时文件写入，避免文件访问冲突
                        temp_file = output_file + ".tmp"
                        with open(temp_file, "w", encoding="utf-8") as f:
                            f.write(output_line + "\n")
                        # 原子性替换原文件
                        os.replace(temp_file, output_file)
                    except Exception as e:
                        # 错误信息也写入文件
                        temp_file = output_file + ".tmp"
                        with open(temp_file, "w", encoding="utf-8") as f:
                            f.write(f"错误: {str(e)}\n")
                        # 原子性替换原文件
                        os.replace(temp_file, output_file)
            except zmq.Again:
                pass
            
            # 发送心跳
            now = time.time()
            if now - last_heartbeat >= 1:
                sender.send_multipart([b"434", b"4"])
                last_heartbeat = now
            
            time.sleep(0.1)
            
    except KeyboardInterrupt:
        pass
    finally:
        receiver.close()
        sender.close()
        context.term()

if __name__ == "__main__":
    main()