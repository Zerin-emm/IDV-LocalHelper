using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;

namespace init
{
    class Program
    {
        private const string DOMAIN = "service.mkey.163.com";
        private const string HOSTS_FILE = @"C:\Windows\System32\drivers\etc\hosts";
        private static string WORKDIR = "";

        static void Main(string[] args)
        {
            Console.Title = "初始化程序";

            if (!IsAdministrator())
            {
                Console.WriteLine("需要管理员权限运行！");
                Console.WriteLine("请右键选择 以管理员身份运行");
                Console.ReadLine();
                return;
            }

            try
            {
                InitializeEnvironment();
            }
            catch (Exception ex)
            {
                Console.WriteLine(string.Format("程序运行错误: {0}", ex.Message));
                Console.ReadLine();
            }
        }

        static bool IsAdministrator()
        {
            using (var identity = WindowsIdentity.GetCurrent())
            {
                var principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        static void InitializeEnvironment()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            if (baseDir.EndsWith("init\\"))
            {
                baseDir = baseDir.Substring(0, baseDir.Length - 5);
            }
            WORKDIR = Path.Combine(baseDir, "certificate");

            if (Directory.Exists(WORKDIR))
            {
                Console.WriteLine(string.Format("清理工作目录残留：{0}", WORKDIR));
                Directory.Delete(WORKDIR, true);
                Console.WriteLine("清理完成");
            }

            Directory.CreateDirectory(WORKDIR);
            Console.WriteLine(string.Format("工作目录：{0}", WORKDIR));
            Directory.SetCurrentDirectory(WORKDIR);

            Console.WriteLine("生成SSL证书...");
            GenerateCertificates();

            Console.WriteLine("安装根证书...");
            InstallRootCertificate();

            Console.WriteLine("配置Hosts...");
            ModifyHostsFile();

            Console.WriteLine();
            Console.WriteLine("初始化完成！");
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("请手动点击 启动登录代理");
            Console.ResetColor();
            Console.WriteLine();
            Console.WriteLine("回车退出...");
            Console.ReadLine();
        }

        static void GenerateCertificates()
        {
            using (var rootKey = RSA.Create(2048))
            {
                var rootRequest = new CertificateRequest(
                    "CN=Identity-V, O=Identity-V, C=CN, ST=Beijing, L=BeiJing",
                    rootKey,
                    HashAlgorithmName.SHA256,
                    RSASignaturePadding.Pkcs1);

                rootRequest.CertificateExtensions.Add(
                    new X509BasicConstraintsExtension(true, true, 0, true));

                rootRequest.CertificateExtensions.Add(
                    new X509KeyUsageExtension(
                        X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign,
                        true));

                var rootCert = rootRequest.CreateSelfSigned(
                    DateTimeOffset.Now.AddDays(-1),
                    DateTimeOffset.Now.AddYears(1));

                File.WriteAllBytes("root_ca.pem", rootCert.Export(X509ContentType.Cert));

                using (var domainKey = RSA.Create(2048))
                {
                    var domainRequest = new CertificateRequest(
                        string.Format("CN={0}, O=Identity-V, C=CN, ST=Beijing, L=BeiJing", DOMAIN),
                        domainKey,
                        HashAlgorithmName.SHA256,
                        RSASignaturePadding.Pkcs1);

                    var sanBuilder = new SubjectAlternativeNameBuilder();
                    sanBuilder.AddDnsName(DOMAIN);
                    domainRequest.CertificateExtensions.Add(sanBuilder.Build());

                    domainRequest.CertificateExtensions.Add(
                        new X509BasicConstraintsExtension(false, false, 0, false));

                    domainRequest.CertificateExtensions.Add(
                        new X509KeyUsageExtension(
                            X509KeyUsageFlags.KeyEncipherment | X509KeyUsageFlags.DigitalSignature,
                            false));

                    domainRequest.CertificateExtensions.Add(
                        new X509EnhancedKeyUsageExtension(
                            new OidCollection { new Oid("1.3.6.1.5.5.7.3.1") },
                            false));

                    var domainCert = domainRequest.Create(
                        rootCert,
                        DateTimeOffset.Now.AddDays(-1),
                        DateTimeOffset.Now.AddYears(1),
                        Guid.NewGuid().ToByteArray());

                    var domainCertWithKey = domainCert.CopyWithPrivateKey(domainKey);

                    File.WriteAllBytes("domain_cert.pem", domainCert.Export(X509ContentType.Cert));
                    File.WriteAllBytes("domain.pfx", domainCertWithKey.Export(X509ContentType.Pfx));
                }
            }
        }

        static void InstallRootCertificate()
        {
            var psi = new ProcessStartInfo
            {
                FileName = "certutil",
                Arguments = "-addstore -f Root root_ca.pem",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            using (var proc = Process.Start(psi))
            {
                proc.WaitForExit();
            }
        }

        static void ModifyHostsFile()
        {
            var lines = new List<string>();
            if (File.Exists(HOSTS_FILE))
            {
                lines = File.ReadAllLines(HOSTS_FILE, Encoding.UTF8).ToList();
                Console.WriteLine("已存在Hosts文件");
            }
            else
            {
                Console.WriteLine("Hosts文件不存在，将创建新文件");
            }

            string domainLine = string.Format("127.0.0.1 {0}", DOMAIN);
            if (!lines.Any(line => line.Contains(DOMAIN)))
            {
                lines.Add(domainLine);
                Console.WriteLine(string.Format("已添加域名配置: {0}", DOMAIN));
            }
            else
            {
                Console.WriteLine(string.Format("域名配置已存在: {0}", DOMAIN));
            }

            File.WriteAllLines(HOSTS_FILE, lines, Encoding.UTF8);
        }
    }
}
