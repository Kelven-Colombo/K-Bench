// ============================================================
//  K-Bench.exe: lançador. Não tem lógica do K-Bench; só:
//   1. já abre como administrador (manifesto);
//   2. tenta baixar o kbench.ps1 da última release no GitHub;
//   3. sem internet (ou falha), usa a cópia embutida no .exe;
//   4. roda o script no PowerShell (sem argumentos = interface gráfica).
//  Compilado pelo build.ps1 com o csc.exe que vem no Windows.
// ============================================================
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("K-Bench")]
[assembly: AssemblyProduct("K-Bench")]
[assembly: AssemblyDescription("Bancada de técnico para Windows")]
[assembly: AssemblyCopyright("MIT - github.com/Kelven-Colombo/K-Bench")]

static class KBench
{
    const string Url = "https://github.com/Kelven-Colombo/K-Bench/releases/latest/download/kbench.ps1";

    class Cliente : WebClient
    {
        protected override WebRequest GetWebRequest(Uri u)
        {
            WebRequest r = base.GetWebRequest(u);
            r.Timeout = 8000;
            return r;
        }
    }

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            string pasta = Path.Combine(Path.GetTempPath(), "K-Bench");
            Directory.CreateDirectory(pasta);
            string script = Path.Combine(pasta, "kbench.ps1");

            byte[] dados = null;
            if (!Array.Exists(args, a => a.Equals("-Offline", StringComparison.OrdinalIgnoreCase)))
            {
                try
                {
                    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                    using (Cliente c = new Cliente())
                    {
                        c.Headers.Add("User-Agent", "K-Bench");
                        byte[] baixado = c.DownloadData(Url);
                        if (Valido(baixado)) dados = baixado;
                    }
                }
                catch { }
            }
            if (dados == null)
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("kbench.ps1"))
                using (MemoryStream m = new MemoryStream())
                {
                    s.CopyTo(m);
                    dados = m.ToArray();
                }
            }
            File.WriteAllBytes(script, dados);

            StringBuilder resto = new StringBuilder();
            foreach (string a in args)
            {
                if (a.Equals("-Offline", StringComparison.OrdinalIgnoreCase)) continue;
                resto.Append(a.IndexOf(' ') >= 0 ? " \"" + a + "\"" : " " + a);
            }
            bool temArgs = resto.Length > 0;

            // Sem argumentos abre só a janela do K-Bench; com argumentos (linha de comando) abre um console
            // que fica aberto no fim, pra dar pra ler o resultado
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass" + (temArgs ? " -NoExit" : "") + " -File \"" + script + "\"" + resto);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = !temArgs;
            Process.Start(psi);
            return 0;
        }
        catch (Exception e)
        {
            MessageBox.Show("Não foi possível abrir o K-Bench:\n\n" + e.Message, "K-Bench",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    // Script do K-Bench: UTF-8 com BOM e com o marcador do projeto
    static bool Valido(byte[] b)
    {
        if (b == null || b.Length < 50000 || b[0] != 0xEF || b[1] != 0xBB || b[2] != 0xBF) return false;
        string ini = Encoding.UTF8.GetString(b, 3, Math.Min(400, b.Length - 3));
        return ini.Contains("K-Bench");
    }
}
