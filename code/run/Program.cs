using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Web;
using System.Web.Script.Serialization;

namespace run
{
    class Program
    {
        private static DateTime startTime = DateTime.Now;
        private static string scriptDir = AppDomain.CurrentDomain.BaseDirectory;
        private static string logPath = Path.Combine(scriptDir, "log.txt");
        private static string workDir = "";
        private static string targetUrl = "";
        private static TcpListener listener;
        private static bool isRunning = true;
        private static X509Certificate2 serverCert;

        private static readonly object loginMethod = new[]
        {
            new Dictionary<string, object>
            {
                {"name", "手机账号"},
                {"icon_url", ""},
                {"text_color", ""},
                {"hot", true},
                {"type", 7},
                {"icon_url_large", ""}
            },
            new Dictionary<string, object>
            {
                {"login_url", ""},
                {"name", "网易邮箱"},
                {"icon_url", ""},
                {"text_color", ""},
                {"hot", true},
                {"type", 1},
                {"icon_url_large", ""}
            },
            new Dictionary<string, object>
            {
                {"login_url", ""},
                {"name", "扫码登录"},
                {"icon_url", ""},
                {"text_color", ""},
                {"hot", true},
                {"type", 17},
                {"icon_url_large", ""}
            }
        };

        private static readonly Dictionary<string, object> pcInfo = new Dictionary<string, object>
        {
            {"extra_unisdk_data", ""},
            {"from_game_id", "h55"},
            {"src_app_channel", "netease"},
            {"src_client_ip", ""},
            {"src_client_type", 1},
            {"src_jf_game_id", "h55"},
            {"src_pay_channel", "netease"},
            {"src_sdk_version", "3.15.0"},
            {"src_udid", ""}
        };

        private const string DOMAIN = "service.mkey.163.com";
        private static readonly string[] DNS_SERVERS = { "8.8.8.8", "114.114.114.114", "223.5.5.5" };

        static void Main(string[] args)
        {
            ClearLog();

            if (!ResolveDns())
            {
                WriteLog("DNS解析失败，请检查网络环境！");
                return;
            }

            if (!CheckEnvironment())
            {
                return;
            }

            StartServer();
        }

        static void WriteLog(string content)
        {
            try
            {
                string timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                string logEntry = string.Format("[{0}] {1}{2}", timestamp, content, Environment.NewLine);
                File.AppendAllText(logPath, logEntry, Encoding.UTF8);
            }
            catch { }
        }

        static void ClearLog()
        {
            try
            {
                File.WriteAllText(logPath, "", Encoding.UTF8);
            }
            catch { }
        }

        static bool ResolveDns()
        {
            string result = "";
            object lockObj = new object();
            bool found = false;

            var threads = DNS_SERVERS.Select(dns => new Thread(() =>
            {
                if (found) return;
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = "nslookup",
                        Arguments = string.Format("{0} {1}", DOMAIN, dns),
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden
                    };

                    using (var proc = Process.Start(psi))
                    {
                        if (proc.WaitForExit(2000))
                        {
                            var output = proc.StandardOutput.ReadToEnd();
                            var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                            foreach (var line in lines)
                            {
                                if (line.Contains("Address") || line.Contains("Addresses"))
                                {
                                    var parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                                    if (parts.Length > 0)
                                    {
                                        var ip = parts.Last();
                                        if (ip != dns && !string.IsNullOrWhiteSpace(ip))
                                        {
                                            lock (lockObj)
                                            {
                                                if (!found)
                                                {
                                                    result = ip;
                                                    found = true;
                                                }
                                            }
                                            return;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                catch { }
            })).ToArray();

            foreach (var t in threads) t.Start();
            foreach (var t in threads) t.Join(3000);

            if (!string.IsNullOrEmpty(result))
            {
                targetUrl = string.Format("https://{0}", result);
                return true;
            }
            return false;
        }

        static bool CheckEnvironment()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            if (baseDir.EndsWith("run\\"))
            {
                baseDir = baseDir.Substring(0, baseDir.Length - 4);
            }
            workDir = Path.Combine(baseDir, "certificate");

            if (!Directory.Exists(workDir))
            {
                WriteLog("未初始化！请先运行初始化程序");
                return false;
            }

            string pfxFile = Path.Combine(workDir, "domain.pfx");
            if (!File.Exists(pfxFile))
            {
                WriteLog("未初始化！请先运行初始化程序");
                return false;
            }

            try
            {
                serverCert = new X509Certificate2(pfxFile);
                if (serverCert == null)
                {
                    WriteLog("证书加载失败！");
                    return false;
                }
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("证书加载异常: {0}", ex.Message));
                return false;
            }

            string processInfo = "";
            if (IsPortOccupied(443, out processInfo))
            {
                WriteLog(string.Format("443 端口被占用=>{0}", processInfo));
                Environment.Exit(0);
                return false;
            }

            try
            {
                var ips = Dns.GetHostAddresses(DOMAIN);
                bool hostsValid = ips.Any(ip => ip.ToString() == "127.0.0.1");
                if (!hostsValid)
                {
                    WriteLog("Hosts 状态异常！请重新运行初始化程序");
                    return false;
                }
            }
            catch
            {
                WriteLog("Hosts 状态异常！请重新运行初始化程序");
                return false;
            }

            return true;
        }

        static bool IsPortOccupied(int port, out string processInfo)
        {
            processInfo = "未知进程";
            try
            {
                using (var client = new TcpClient())
                {
                    var result = client.BeginConnect("127.0.0.1", port, null, null);
                    bool success = result.AsyncWaitHandle.WaitOne(100);
                    if (success && client.Connected)
                    {
                        client.EndConnect(result);
                        processInfo = GetPortProcess(port);
                        return true;
                    }
                }
            }
            catch { }
            return false;
        }

        static string GetPortProcess(int port)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = string.Format("/c netstat -ano | findstr :{0}", port),
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                using (var proc = Process.Start(psi))
                {
                    string output = proc.StandardOutput.ReadToEnd();
                    proc.WaitForExit();

                    var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (var line in lines)
                    {
                        var parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length >= 5)
                        {
                            string pid = parts.Last();
                            int pidNum = 0;
                            if (int.TryParse(pid, out pidNum))
                            {
                                var taskPsi = new ProcessStartInfo
                                {
                                    FileName = "cmd.exe",
                                    Arguments = string.Format("/c tasklist /FI \"PID eq {0}\" /FO CSV /NH", pid),
                                    UseShellExecute = false,
                                    RedirectStandardOutput = true,
                                    CreateNoWindow = true,
                                    WindowStyle = ProcessWindowStyle.Hidden
                                };

                                using (var taskProc = Process.Start(taskPsi))
                                {
                                    string taskOutput = taskProc.StandardOutput.ReadToEnd();
                                    taskProc.WaitForExit();

                                    if (!string.IsNullOrWhiteSpace(taskOutput))
                                    {
                                        var csvParts = taskOutput.Split(',');
                                        if (csvParts.Length > 0)
                                        {
                                            string processName = csvParts[0].Trim('"');
                                            return string.Format("{0}={1}", processName, pid);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch { }
            return "未知进程";
        }

        static void StartServer()
        {
            WriteLog("第五人格登录代理");
            WriteLog(string.Format("目标域名: {0}", DOMAIN));
            WriteLog("本地绑定: 127.0.0.1:443");
            WriteLog(string.Format("工作目录: {0}", workDir));
            WriteLog("代理服务运行中");

            double elapsed = (DateTime.Now - startTime).TotalSeconds;
            WriteLog(string.Format("耗费时间: {0:F1}秒", elapsed));

            try
            {
                listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 443);
                listener.Start();

                while (isRunning)
                {
                    try
                    {
                        var client = listener.AcceptTcpClient();
                        ThreadPool.QueueUserWorkItem(HandleClient, client);
                    }
                    catch
                    {
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("服务器启动失败: {0}", ex.Message));
            }
        }

        static void HandleClient(object state)
        {
            var client = state as TcpClient;
            if (client == null) return;

            try
            {
                var stream = client.GetStream();
                var sslStream = new SslStream(stream, false);
                sslStream.AuthenticateAsServer(serverCert, false, SslProtocols.Tls12 | SslProtocols.Tls11 | SslProtocols.Tls, false);

                var request = ReadHttpRequest(sslStream);
                if (request == null) return;

                ProcessRequest(request, sslStream);
            }
            catch { }
            finally
            {
                client.Close();
            }
        }

        static HttpRequest ReadHttpRequest(SslStream stream)
        {
            try
            {
                var buffer = new byte[8192];
                var data = new List<byte>();
                int bytesRead;

                while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    data.AddRange(buffer.Take(bytesRead));
                    
                    var headerEnd = Encoding.UTF8.GetString(data.ToArray());
                    if (headerEnd.Contains("\r\n\r\n"))
                    {
                        break;
                    }
                }

                var requestStr = Encoding.UTF8.GetString(data.ToArray());
                var lines = requestStr.Split(new[] { "\r\n" }, StringSplitOptions.None);
                if (lines.Length == 0) return null;

                var requestLine = lines[0].Split(' ');
                if (requestLine.Length < 2) return null;

                var request = new HttpRequest
                {
                    Method = requestLine[0],
                    Path = requestLine[1],
                    Headers = new Dictionary<string, string>(),
                    Body = ""
                };

                int bodyStart = requestStr.IndexOf("\r\n\r\n");
                if (bodyStart > 0)
                {
                    request.Body = requestStr.Substring(bodyStart + 4);
                }

                for (int i = 1; i < lines.Length; i++)
                {
                    if (string.IsNullOrEmpty(lines[i])) break;
                    var colonPos = lines[i].IndexOf(':');
                    if (colonPos > 0)
                    {
                        var key = lines[i].Substring(0, colonPos).Trim();
                        var value = lines[i].Substring(colonPos + 1).Trim();
                        request.Headers[key] = value;
                    }
                }

                string contentLengthStr;
                if (request.Headers.TryGetValue("Content-Length", out contentLengthStr))
                {
                    int contentLength = int.Parse(contentLengthStr);
                    while (request.Body.Length < contentLength)
                    {
                        bytesRead = stream.Read(buffer, 0, buffer.Length);
                        if (bytesRead == 0) break;
                        request.Body += Encoding.UTF8.GetString(buffer, 0, bytesRead);
                    }
                }

                return request;
            }
            catch
            {
                return null;
            }
        }

        static void ProcessRequest(HttpRequest request, SslStream stream)
        {
            try
            {
                string path = request.Path.Split('?')[0];
                string method = request.Method;

                if (path.StartsWith("/mpay/games/") && path.EndsWith("/login_methods") && method == "GET")
                {
                    HandleLoginMethods(request, stream);
                }
                else if (path == "/mpay/api/users/login/mobile/user_info" && method == "POST")
                {
                    WriteLog("[验证码登录] 获取用户信息");
                    RequestPostAsCv(request, stream, "i4.7.0");
                }
                else if (path == "/mpay/api/users/login/mobile/get_sms" && method == "POST")
                {
                    WriteLog("[验证码登录] 获取短信验证码");
                    RequestPostAsCv(request, stream, "i4.7.0");
                }
                else if (path == "/mpay/api/users/login/mobile/verify_sms" && method == "POST")
                {
                    WriteLog("[验证码登录] 验证短信验证码");
                    RequestPostAsCv(request, stream, "i4.7.0");
                }
                else if (path == "/mpay/api/users/login/mobile/finish" && method == "POST")
                {
                    WriteLog("[验证码登录] 完成登录");
                    RequestPostAsCv(request, stream, "i4.7.0");
                }
                else if (path == "/mpay/api/users/login/mobile/guide" && method == "POST")
                {
                    WriteLog("登录成功");
                    RequestPostAsCv(request, stream, "i4.7.0");
                }
                else if (path == "/mpay/api/users/login/mobile/verify_pwd" && method == "POST")
                {
                    WriteLog("[密码登录] 验证密码");
                    RequestPostAsCv(request, stream, "i4.7.0");
                }
                else if (path.StartsWith("/mpay/games/") && path.Contains("/devices/") && path.Contains("/users"))
                {
                    if (method == "POST")
                    {
                        RequestPostAsCv(request, stream, "i4.7.0");
                    }
                    else if (method == "GET")
                    {
                        HandleLogin(request, stream);
                    }
                }
                else if (path == "/mpay/games/pc_config" && method == "GET")
                {
                    HandlePcConfig(request, stream);
                }
                else if (path.StartsWith("/mpay/api/qrcode/"))
                {
                    Proxy(request, stream);
                }
                else
                {
                    if (path == "/mpay/config/common.json")
                    {
                        WriteLog("客户端连接正常");
                    }

                    if (method == "GET")
                    {
                        RequestGetAsCv(request, stream, "i4.7.0");
                    }
                    else
                    {
                        RequestPostAsCv(request, stream, "i4.7.0");
                    }
                }
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("请求处理异常: {0}", ex.Message));
            }
        }

        static void HandleLoginMethods(HttpRequest request, SslStream stream)
        {
            try
            {
                string contentType;
                var respText = RequestGetAsCvInternal(request, "i4.7.0", out contentType);
                var serializer = new JavaScriptSerializer();
                var data = serializer.Deserialize<Dictionary<string, object>>(respText);

                if (data.ContainsKey("entrance"))
                {
                    data["entrance"] = new[] { loginMethod };
                }
                data["select_platform"] = true;
                data["qrcode_select_platform"] = true;

                if (data.ContainsKey("config"))
                {
                    var config = data["config"] as Dictionary<string, object>;
                    if (config != null)
                    {
                        foreach (var key in config.Keys.ToList())
                        {
                            var item = config[key] as Dictionary<string, object>;
                            if (item != null)
                            {
                                item["select_platforms"] = new[] { 0, 1, 2, 3, 4 };
                            }
                        }
                    }
                }

                string json = serializer.Serialize(data);
                WriteResponse(stream, json, 200, contentType);
                WriteLog("登录界面劫持成功");
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("处理登录入口请求异常: {0}", ex.Message));
                Proxy(request, stream);
            }
        }

        static void HandleLogin(HttpRequest request, SslStream stream)
        {
            try
            {
                WriteLog("[本地登录] 获取用户信息");
                string contentType;
                var respText = RequestGetAsCvInternal(request, "i4.7.0", out contentType);
                var serializer = new JavaScriptSerializer();
                var data = serializer.Deserialize<Dictionary<string, object>>(respText);

                if (data.ContainsKey("user"))
                {
                    var user = data["user"] as Dictionary<string, object>;
                    if (user != null)
                    {
                        user["pc_ext_info"] = pcInfo;
                    }
                }

                string json = serializer.Serialize(data);
                WriteResponse(stream, json, 200, contentType);
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("[本地登录] 获取用户信息异常: {0}", ex.Message));
                Proxy(request, stream);
            }
        }

        static void HandlePcConfig(HttpRequest request, SslStream stream)
        {
            try
            {
                string contentType;
                var respText = RequestGetAsCvInternal(request, "i4.7.0", out contentType);
                var serializer = new JavaScriptSerializer();
                var data = serializer.Deserialize<Dictionary<string, object>>(respText);

                if (data.ContainsKey("game"))
                {
                    var game = data["game"] as Dictionary<string, object>;
                    if (game != null && game.ContainsKey("config"))
                    {
                        var config = game["config"] as Dictionary<string, object>;
                        if (config != null)
                        {
                            config["cv_review_status"] = 1;
                        }
                    }
                }

                string json = serializer.Serialize(data);
                WriteResponse(stream, json, 200, contentType);
                WriteLog("请求转发成功");
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("处理PC配置请求异常: {0}", ex.Message));
                Proxy(request, stream);
            }
        }

        static void RequestGetAsCv(HttpRequest request, SslStream stream, string cv)
        {
            string contentType;
            var respText = RequestGetAsCvInternal(request, cv, out contentType);
            WriteResponse(stream, respText, 200, contentType);
        }

        static string RequestGetAsCvInternal(HttpRequest request, string cv, out string contentType)
        {
            contentType = "application/json";
            
            string query = "";
            int queryPos = request.Path.IndexOf('?');
            if (queryPos > 0)
            {
                query = request.Path.Substring(queryPos + 1);
            }
            
            if (!string.IsNullOrEmpty(cv))
            {
                query += string.Format("&cv={0}", cv);
            }

            string path = request.Path.Split('?')[0];
            string url = string.Format("{0}{1}?{2}", targetUrl, path, query);

            using (var client = CreateHttpClient())
            {
                foreach (var header in request.Headers)
                {
                    if (header.Key.ToLower() != "host")
                    {
                        try { client.Headers[header.Key] = header.Value; } catch { }
                    }
                }

                var data = client.DownloadData(url);
                contentType = client.ResponseHeaders["Content-Type"];
                if (contentType == null) contentType = "application/json";
                return Encoding.UTF8.GetString(data);
            }
        }

        static void RequestPostAsCv(HttpRequest request, SslStream stream, string cv)
        {
            try
            {
                string query = "";
                int queryPos = request.Path.IndexOf('?');
                if (queryPos > 0)
                {
                    query = request.Path.Substring(queryPos + 1);
                }
                
                if (!string.IsNullOrEmpty(cv))
                {
                    query += string.Format("&cv={0}", cv);
                }

                string path = request.Path.Split('?')[0];
                string url = string.Format("{0}{1}?{2}", targetUrl, path, query);

                string newBody = request.Body;
                string contentType;
                request.Headers.TryGetValue("Content-Type", out contentType);
                if (contentType == null) contentType = "";

                if (contentType.Contains("application/json"))
                {
                    var serializer = new JavaScriptSerializer();
                    try
                    {
                        var jsonBody = serializer.Deserialize<Dictionary<string, object>>(request.Body);
                        jsonBody["cv"] = cv;
                        jsonBody.Remove("arch");
                        newBody = serializer.Serialize(jsonBody);
                    }
                    catch { }
                }

                using (var client = CreateHttpClient())
                {
                    foreach (var header in request.Headers)
                    {
                        if (header.Key.ToLower() != "host" && 
                            header.Key.ToLower() != "content-type" &&
                            header.Key.ToLower() != "content-length")
                        {
                            try { client.Headers[header.Key] = header.Value; } catch { }
                        }
                    }

                    byte[] data = client.UploadData(url, "POST", Encoding.UTF8.GetBytes(newBody));
                    WriteResponse(stream, data, 200, client.ResponseHeaders["Content-Type"]);
                }
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("POST请求异常: {0}", ex.Message));
                Proxy(request, stream);
            }
        }

        static void Proxy(HttpRequest request, SslStream stream)
        {
            try
            {
                string query = "";
                int queryPos = request.Path.IndexOf('?');
                if (queryPos > 0)
                {
                    query = request.Path.Substring(queryPos + 1);
                }

                string path = request.Path.Split('?')[0];
                string url = string.Format("{0}{1}?{2}", targetUrl, path, query);
                string method = request.Method;

                using (var client = CreateHttpClient())
                {
                    foreach (var header in request.Headers)
                    {
                        if (header.Key.ToLower() != "host")
                        {
                            try { client.Headers[header.Key] = header.Value; } catch { }
                        }
                    }

                    byte[] data;
                    if (method == "POST")
                    {
                        data = client.UploadData(url, "POST", Encoding.UTF8.GetBytes(request.Body));
                    }
                    else
                    {
                        data = client.DownloadData(url);
                    }

                    WriteResponse(stream, data, 200, client.ResponseHeaders["Content-Type"]);
                }
            }
            catch (Exception ex)
            {
                WriteLog(string.Format("代理请求异常: {0}", ex.Message));
                WriteResponse(stream, "{}", 500, "application/json");
            }
        }

        static WebClient CreateHttpClient()
        {
            var client = new WebClient();
            ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, errors) => true;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
            client.Encoding = Encoding.UTF8;
            return client;
        }

        static void WriteResponse(SslStream stream, string content, int statusCode, string contentType)
        {
            WriteResponse(stream, Encoding.UTF8.GetBytes(content), statusCode, contentType);
        }

        static void WriteResponse(SslStream stream, byte[] content, int statusCode, string contentType)
        {
            var sb = new StringBuilder();
            sb.AppendFormat("HTTP/1.1 {0} OK\r\n", statusCode);
            sb.AppendFormat("Content-Type: {0}\r\n", contentType ?? "application/json");
            sb.AppendFormat("Content-Length: {0}\r\n", content.Length);
            sb.Append("Connection: close\r\n");
            sb.Append("\r\n");

            var headerBytes = Encoding.UTF8.GetBytes(sb.ToString());
            stream.Write(headerBytes, 0, headerBytes.Length);
            stream.Write(content, 0, content.Length);
            stream.Flush();
        }
    }

    class HttpRequest
    {
        public string Method { get; set; }
        public string Path { get; set; }
        public Dictionary<string, string> Headers { get; set; }
        public string Body { get; set; }
    }
}
