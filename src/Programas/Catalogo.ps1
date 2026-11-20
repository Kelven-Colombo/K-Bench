# ============================================================
#  Catálogo de programas e runtimes. Tudo de fonte oficial:
#  winget (repositório da Microsoft), Microsoft Store ou o CDN do Office.
#  Presets: Basico (PC de cliente), MC (loja), Tecnico (bancada), Runtimes.
# ============================================================

function Get-KProgramas {
    $p = {
        param($Id, $Nome, $Descricao, $Categoria, $Pacote, [string[]]$Presets = @(), $Fonte = 'winget', $Arquivo, [bool]$SemDesinstalar,
              [string]$Custom, [string]$Override)
        # Custom: argumentos somados aos silenciosos do pacote (winget --custom); Override: substitui todos (--override)
        [pscustomobject]@{ Id = $Id; Nome = $Nome; Descricao = $Descricao; Categoria = $Categoria; Pacote = $Pacote
                           Presets = $Presets; Fonte = $Fonte; Arquivo = $Arquivo; SemDesinstalar = $SemDesinstalar
                           Custom = $Custom; Override = $Override }
    }
    $rt = 'Runtimes'
    $base = 'Basico', 'MC', 'Runtimes'

    # ── Runtimes (o "All-in-One", mas cada pacote vindo da Microsoft) ──
    & $p VC2005  'Visual C++ 2005'  'x86 e x64. Jogos e programas antigos.' $rt 'Microsoft.VCRedist.2005.x86,Microsoft.VCRedist.2005.x64' $base
    & $p VC2008  'Visual C++ 2008'  'x86 e x64.' $rt 'Microsoft.VCRedist.2008.x86,Microsoft.VCRedist.2008.x64' $base
    & $p VC2010  'Visual C++ 2010'  'x86 e x64.' $rt 'Microsoft.VCRedist.2010.x86,Microsoft.VCRedist.2010.x64' $base
    & $p VC2012  'Visual C++ 2012'  'x86 e x64.' $rt 'Microsoft.VCRedist.2012.x86,Microsoft.VCRedist.2012.x64' $base
    & $p VC2013  'Visual C++ 2013'  'x86 e x64.' $rt 'Microsoft.VCRedist.2013.x86,Microsoft.VCRedist.2013.x64' $base
    & $p VC2015  'Visual C++ 2015-2022'  'x86 e x64. O que quase todo programa atual usa.' $rt 'Microsoft.VCRedist.2015+.x86,Microsoft.VCRedist.2015+.x64' $base
    & $p Net6    '.NET Desktop Runtime 6'  'Fora de suporte da Microsoft, mas vários programas ainda pedem.' $rt 'Microsoft.DotNet.DesktopRuntime.6' $base
    & $p Net8    '.NET Desktop Runtime 8'  'Versão de suporte longo (LTS).' $rt 'Microsoft.DotNet.DesktopRuntime.8' $base
    & $p Net9    '.NET Desktop Runtime 9'  '' $rt 'Microsoft.DotNet.DesktopRuntime.9' $base
    & $p Net10   '.NET Desktop Runtime 10'  'Versão de suporte longo (LTS) mais nova.' $rt 'Microsoft.DotNet.DesktopRuntime.10' $base
    & $p NetFx35 '.NET Framework 3.5'  'Recurso do Windows (baixa pelo Windows Update). Programas antigos e alguns de nota fiscal.' $rt 'NetFx3' $base 'feat'
    & $p DirectX 'DirectX (junho/2010)'  'As DLLs antigas do DirectX 9/10/11 que jogos e emuladores pedem. Não tem desinstalador.' $rt 'Microsoft.DirectX' $base 'winget' '%SystemRoot%\System32\d3dx9_43.dll' $true
    & $p WebView2 'WebView2'  'Motor do Edge usado por apps (Teams, Outlook novo...). Já vem no Windows 11.' $rt 'Microsoft.EdgeWebView2Runtime' @('Runtimes') 'winget' '%ProgramFiles(x86)%\Microsoft\EdgeWebView\Application' $true
    & $p Java    'Java 8 (Oracle)'  'Só se algum programa pedir (bancos antigos, alguns sistemas fiscais).' $rt 'Oracle.JavaRuntimeEnvironment'
    & $p XNA     'XNA Framework 4.0'  'Jogos indie antigos (Terraria, Stardew Valley antigo...).' $rt 'Microsoft.XNARedist'
    & $p OpenAL  'OpenAL'  'Áudio de jogos antigos.' $rt 'CreativeTechnology.OpenAL'

    # ── Navegadores ──
    $c = 'Navegadores'
    & $p Chrome  'Google Chrome' '' $c 'Google.Chrome' @('Basico', 'MC')
    & $p Firefox 'Firefox' '' $c 'Mozilla.Firefox'
    & $p Brave   'Brave' 'Bloqueia anúncios por padrão.' $c 'Brave.Brave'
    & $p ChromeBeta 'Google Chrome Beta' 'Instala ao lado do Chrome normal.' $c 'Google.Chrome.Beta'
    & $p Helium  'Helium' 'Baseado no Chromium, leve, sem rastreamento e com bloqueio de anúncios.' $c 'ImputNet.Helium'

    # ── Documentos e Office ──
    $c = 'Documentos e Office'
    & $p M365Pessoal  'Microsoft 365 (conta pessoal/família)' 'Word, Excel, PowerPoint, Outlook e OneNote. Ativa com a conta Microsoft do cliente.' $c 'O365HomePremRetail' @() 'odt'
    & $p M365Empresas 'Microsoft 365 (conta empresarial)' 'Mesmos apps, para assinaturas Business/escola.' $c 'O365BusinessRetail' @() 'odt'
    & $p LibreOffice  'LibreOffice' 'Pacote de escritório gratuito, abre arquivos do Office.' $c 'TheDocumentFoundation.LibreOffice'
    & $p OnlyOffice   'ONLYOFFICE' 'Gratuito, com visual parecido com o do Office e ótima compatibilidade com .docx/.xlsx/.pptx.' $c 'ONLYOFFICE.DesktopEditors'
    & $p AcrobatReader 'Adobe Acrobat Reader' 'Leitor de PDF mais compatível (formulários, assinaturas).' $c 'Adobe.Acrobat.Reader.64-bit' @('Basico', 'MC')
    & $p Sumatra      'SumatraPDF' 'Leitor de PDF levíssimo.' $c 'SumatraPDF.SumatraPDF'

    # ── Nuvem e comunicação ──
    $c = 'Nuvem e comunicação'
    & $p GoogleDrive 'Google Drive para computador' '' $c 'Google.GoogleDrive' @('MC')
    & $p WhatsApp    'WhatsApp' 'Da Microsoft Store.' $c '9NKSQGP7F2NH' @('MC') 'msstore'
    & $p Telegram    'Telegram' '' $c 'Telegram.TelegramDesktop'
    & $p Discord     'Discord' '' $c 'Discord.Discord'
    & $p Zoom        'Zoom' '' $c 'Zoom.Zoom'
    & $p Teams       'Microsoft Teams' '' $c 'Microsoft.Teams'

    # ── Design e mídia ──
    $c = 'Design e mídia'
    & $p Affinity 'Affinity' 'Foto, vetor e diagramação num app só. Gratuito.' $c 'Canva.Affinity' @('MC')
    & $p Inkscape 'Inkscape' 'Vetor, gratuito.' $c 'Inkscape.Inkscape'
    & $p Gimp     'GIMP' 'Edição de imagem, gratuito.' $c 'GIMP.GIMP.3'
    & $p VLC      'VLC' 'Toca qualquer vídeo ou áudio.' $c 'VideoLAN.VLC' @('Basico', 'MC')
    & $p MPCHC    'MPC-HC' 'Player leve e clássico.' $c 'clsid2.mpc-hc'
    & $p KLite    'K-Lite Codec Pack (Standard)' 'Codecs pra todo formato + MPC-HC. Use no lugar do MPC-HC avulso.' $c 'CodecGuide.K-LiteCodecPack.Standard'
    & $p Spotify  'Spotify' '' $c 'Spotify.Spotify'
    & $p OBS      'OBS Studio' 'Gravar a tela e fazer live.' $c 'OBSProject.OBSStudio'
    & $p Audacity 'Audacity' 'Edição de áudio.' $c 'Audacity.Audacity'
    & $p ShareX   'ShareX' 'Captura de tela com edição e gravação.' $c 'ShareX.ShareX'

    # ── Utilitários ──
    $c = 'Utilitários'
    & $p SevenZip  '7-Zip' 'Abre .zip, .rar, .7z...' $c '7zip.7zip' @('Basico', 'MC', 'Tecnico')
    & $p NanaZip   'NanaZip' '7-Zip com cara de Windows 11 (entra no menu de contexto novo).' $c 'M2Team.NanaZip'
    & $p WinRAR    'WinRAR' 'Pago (avaliação sem prazo).' $c 'RARLab.WinRAR'
    & $p Revo      'Revo Uninstaller' 'Desinstalador com limpeza de rastros (o K-Bench também tem: aba Desinstalar).' $c 'RevoUninstaller.RevoUninstaller'
    & $p UniGetUI  'UniGetUI' 'Interface pro winget/Scoop/Chocolatey: ver e atualizar tudo instalado.' $c 'Devolutions.UniGetUI'
    & $p NotepadPP 'Notepad++' '' $c 'Notepad++.Notepad++' @('Tecnico')
    & $p Everything 'Everything' 'Busca de arquivos instantânea.' $c 'voidtools.Everything' @('Tecnico')
    & $p PowerToys 'PowerToys' 'Utilitários da Microsoft (FancyZones, renomear em massa...).' $c 'Microsoft.PowerToys'
    & $p Bitwarden 'Bitwarden' 'Gerenciador de senhas gratuito.' $c 'Bitwarden.Bitwarden'
    & $p qBittorrent 'qBittorrent' '' $c 'qBittorrent.qBittorrent'

    # ── Acesso remoto ──
    $c = 'Acesso remoto'
    & $p AnyDesk    'AnyDesk' 'Pra dar suporte a distância.' $c 'AnyDesk.AnyDesk' @('Basico', 'MC')
    & $p TeamViewer 'TeamViewer' '' $c 'TeamViewer.TeamViewer'

    # ── Ferramentas do técnico ──
    $c = 'Ferramentas do técnico'
    & $p CrystalDiskInfo 'CrystalDiskInfo' 'Saúde do SSD/HD (SMART).' $c 'CrystalDewWorld.CrystalDiskInfo' @('Tecnico')
    & $p HWiNFO   'HWiNFO' 'Sensores, temperaturas e detalhes de hardware.' $c 'REALiX.HWiNFO' @('Tecnico')
    & $p CPUZ     'CPU-Z' '' $c 'CPUID.CPU-Z' @('Tecnico')
    & $p HWMonitor 'HWMonitor' '' $c 'CPUID.HWMonitor'
    & $p Rufus    'Rufus' 'Criar pendrive de instalação do Windows.' $c 'Rufus.Rufus' @('Tecnico')
    & $p DDU      'DDU (Display Driver Uninstaller)' 'Remove driver de vídeo por completo. Use no modo de segurança.' $c 'Wagnardsoft.DisplayDriverUninstaller' @('Tecnico')
    & $p IntelDSA 'Assistente de Driver e Suporte Intel' 'Atualiza drivers Intel (vídeo, Wi-Fi, Bluetooth) direto da Intel.' $c 'Intel.IntelDriverAndSupportAssistant'
    & $p NvidiaApp 'NVIDIA App' 'Drivers e ajustes da placa NVIDIA (substituiu o GeForce Experience). Da Microsoft Store, publicado pela NVIDIA.' $c 'XP8CLZL93F5Z4P' @() 'msstore'
    & $p Ventoy   'Ventoy' 'Pendrive com várias ISOs.' $c 'Ventoy.Ventoy'
    & $p Malwarebytes 'Malwarebytes' 'Segunda opinião contra vírus (a versão grátis é só scanner).' $c 'Malwarebytes.Malwarebytes'
    & $p BleachBit 'BleachBit' '' $c 'BleachBit.BleachBit'

    # ── Jogos ──
    $c = 'Jogos'
    & $p Steam 'Steam' '' $c 'Valve.Steam'
    & $p Epic  'Epic Games' '' $c 'EpicGames.EpicGamesLauncher'
    & $p Hydra 'Hydra' 'Launcher de jogos open source.' $c 'HydraLauncher.Hydra'

    # ── Desenvolvimento (já configurado: PATH, JAVA_HOME, menu de contexto) ──
    $c = 'Desenvolvimento'
    $d = @('Dev')
    $jdk = 'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome'
    & $p Git       'Git' 'Já no PATH.' $c 'Git.Git' $d
    & $p VSCode    'Visual Studio Code' 'Com "Abrir com Code" no menu de contexto, no PATH e associado aos arquivos de código.' $c 'Microsoft.VisualStudioCode' $d 'winget' $null $false '' '/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'
    & $p Python    'Python 3.14' 'No PATH, com o lançador "py".' $c 'Python.Python.3.14' $d 'winget' $null $false 'PrependPath=1 Include_launcher=1 Include_test=0'
    & $p NodeLTS   'Node.js LTS' 'Com npm, no PATH.' $c 'OpenJS.NodeJS.LTS' $d
    & $p JDK21     'Java JDK 21 (Temurin)' 'LTS. Configura JAVA_HOME e PATH.' $c 'EclipseAdoptium.Temurin.21.JDK' $d 'winget' $null $false $jdk
    & $p JDK25     'Java JDK 25 (Temurin)' 'LTS mais nova. Configura JAVA_HOME e PATH.' $c 'EclipseAdoptium.Temurin.25.JDK' @() 'winget' $null $false $jdk
    & $p DotNetSdk '.NET SDK 10' '' $c 'Microsoft.DotNet.SDK.10'
    & $p PowerShell7 'PowerShell 7' '' $c 'Microsoft.PowerShell' $d
    & $p Terminal  'Windows Terminal' 'Já vem no Windows 11.' $c 'Microsoft.WindowsTerminal'
    & $p GitHubDesktop 'GitHub Desktop' '' $c 'GitHub.GitHubDesktop'
    & $p Cursor    'Cursor' 'Editor com IA, baseado no VS Code.' $c 'Anysphere.Cursor'
    & $p IntelliJ  'IntelliJ IDEA Community' 'Java/Kotlin.' $c 'JetBrains.IntelliJIDEA.Community'
    & $p PyCharm   'PyCharm Community' 'Python.' $c 'JetBrains.PyCharm.Community'
    & $p VisualStudio 'Visual Studio Community' 'C#/C++. Instala só o básico; as cargas de trabalho se escolhem no Visual Studio Installer.' $c 'Microsoft.VisualStudio.Community'
    & $p AndroidStudio 'Android Studio' '' $c 'Google.AndroidStudio'
    & $p WSL       'WSL (Linux no Windows)' '' $c 'Microsoft.WSL'
    & $p Docker    'Docker Desktop' 'Precisa do WSL; pede reinício.' $c 'Docker.DockerDesktop'
    & $p Postman   'Postman' 'Testar APIs.' $c 'Postman.Postman'
    & $p Go        'Go' '' $c 'GoLang.Go'
    & $p Rust      'Rust (rustup)' '' $c 'Rustlang.Rustup'
}

function Get-KPresetsProgramas {
    [ordered]@{ Basico = 'Básico'; MC = 'MC Serviços'; Tecnico = 'Técnico'; Dev = 'Dev'; Runtimes = 'Só runtimes' }
}
