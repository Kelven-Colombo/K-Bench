# ============================================================
#  Desinstalador completo (tipo Revo): roda o desinstalador do
#  programa e depois caça rastros (pastas, registro, atalhos,
#  serviços, tarefas, inicialização). Tudo que sai tem backup:
#  registro e tarefas em estado\desinstalados\, arquivos na Lixeira.
# ============================================================

# ── Lista de instalados (a mesma do Painel de Controle + apps da Store) ──
function Get-KAppsInstalados {
    $raizes = @(
        @{ C = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; E = 'Máquina' }
        @{ C = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; E = 'Máquina (32 bits)' }
        @{ C = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; E = 'Usuário' }
    )
    $vistos = @{}
    $lista = foreach ($r in $raizes) {
        foreach ($k in Get-ChildItem $r.C -ErrorAction SilentlyContinue) {
            $v = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if (-not $v.DisplayName -or $v.SystemComponent -eq 1 -or $v.ParentKeyName -or
                "$($v.ReleaseType)" -match 'Update|Hotfix' -or -not ($v.UninstallString -or $v.QuietUninstallString)) { continue }
            $chaveDup = "$($v.DisplayName)|$($v.DisplayVersion)"
            if ($vistos[$chaveDup]) { continue }
            $vistos[$chaveDup] = $true
            $pasta = Get-KPastaApp $v
            $exe = (Split-KLinhaComando "$($v.UninstallString)")[0]
            $data = if ("$($v.InstallDate)" -match '^(\d{4})(\d{2})(\d{2})$') { "$($Matches[3])/$($Matches[2])/$($Matches[1])" } else { '' }
            [pscustomobject]@{
                Nome = "$($v.DisplayName)".Trim(); Versao = "$($v.DisplayVersion)"; Editor = "$($v.Publisher)".Trim()
                Tamanho = if ($v.EstimatedSize) { Format-KTamanho ([double]$v.EstimatedSize * 1KB) } else { '' }
                Bytes = [double]$v.EstimatedSize * 1KB
                Data = $data; Escopo = $r.E; Tipo = 'Win32'
                Chave = $k.Name; ChavePS = $k.PSPath; Codigo = $k.PSChildName
                Pasta = $pasta
                Desinstalar = "$($v.UninstallString)"; Silencioso = "$($v.QuietUninstallString)"
                Msi = ($v.WindowsInstaller -eq 1)
                Quebrado = [bool]($exe -and $exe -notmatch 'msiexec' -and -not (Test-Path -LiteralPath $exe))
            }
        }
    }
    # Apps da Microsoft Store instalados pelo usuário (nome bonito vem do Menu Iniciar)
    $nomes = @{}
    foreach ($s in Get-StartApps -ErrorAction SilentlyContinue) { $pfn = ($s.AppID -split '!')[0]; if (-not $nomes[$pfn]) { $nomes[$pfn] = $s.Name } }
    $store = foreach ($a in Get-AppxPackage -ErrorAction SilentlyContinue) {
        if ($a.IsFramework -or $a.NonRemovable -or $a.SignatureKind -ne 'Store' -or $a.IsResourcePackage) { continue }
        $n = $nomes[$a.PackageFamilyName]
        if (-not $n) { continue }   # sem atalho no Iniciar = componente, não app
        [pscustomobject]@{
            Nome = $n; Versao = "$($a.Version)"; Editor = $(if ($a.Publisher -match '^CN=([^,]+)' -and $Matches[1] -notmatch '^[0-9A-Fa-f-]{36}$') { $Matches[1] } else { '' }); Tamanho = ''; Bytes = 0
            Data = ''; Escopo = 'Microsoft Store'; Tipo = 'Store'; Chave = $null; ChavePS = $null; Codigo = $a.PackageFullName
            Pasta = $null; Desinstalar = ''; Silencioso = ''; Msi = $false; Quebrado = $false
        }
    }
    @($lista) + @($store) | Sort-Object Nome
}

# Caminho dentro de outro (sem curingas: colchetes em nome de pasta quebrariam o -like)
function Test-KDentro([string]$Caminho, [string]$Pasta) {
    $Caminho.StartsWith($Pasta.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Format-KTamanho([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) } elseif ($Bytes -ge 1MB) { '{0:N0} MB' -f ($Bytes / 1MB) } elseif ($Bytes -gt 0) { '{0:N0} KB' -f ($Bytes / 1KB) } else { '' }
}

# "C:\x\unins000.exe" /arg  →  exe, argumentos   (com ou sem aspas)
function Split-KLinhaComando([string]$Linha) {
    $l = [Environment]::ExpandEnvironmentVariables($Linha.Trim())
    if (-not $l) { return @('', '') }
    if ($l.StartsWith('"')) {
        $i = $l.IndexOf('"', 1)
        if ($i -gt 0) { return @($l.Substring(1, $i - 1), $l.Substring($i + 1).Trim()) }
    }
    $m = [regex]::Match($l, '^(.+?\.exe)(\s+.*)?$', 'IgnoreCase')
    if ($m.Success) { return @($m.Groups[1].Value, $m.Groups[2].Value.Trim()) }
    @($l, '')
}

# Pastas que nunca são "a pasta do programa", mesmo que o registro diga
function Test-KPastaProtegida([string]$Pasta) {
    if (-not $Pasta -or $Pasta.Length -lt 6) { return $true }
    $p = $Pasta.TrimEnd('\')
    $prot = @($env:SystemDrive, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA,
              "$env:LOCALAPPDATA\Programs", "$env:LOCALAPPDATA\Temp", $env:USERPROFILE, $env:PUBLIC, (Split-Path $env:USERPROFILE),
              "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files", "$env:ProgramData\Package Cache",
              "$env:SystemRoot\Installer", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents", "$env:USERPROFILE\Downloads") |
            Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    if ($prot -contains $p) { return $true }
    if ($p -like "$env:SystemRoot\*") { return $true }
    if (($p -split '\\').Count -lt 2) { return $true }   # raiz de unidade
    $false
}

function Get-KPastaApp($v) {
    $cands = @("$($v.InstallLocation)")
    # Sem InstallLocation: a pasta do desinstalador ou do ícone, se não for genérica
    # só se for um desinstalador de verdade (app do Chrome desinstala com chrome.exe: a pasta seria a do Chrome!)
    $e = (Split-KLinhaComando "$($v.UninstallString)")[0]
    if ($e -and (Split-Path $e -Leaf) -match '^(unins|uninst|uninstall|remove|_?setup)' -and $e -notmatch '\\Installer\\|Package Cache|\\Temp\\') {
        $cands += (Split-Path $e -Parent)
    }
    foreach ($c in $cands) {
        $c = [Environment]::ExpandEnvironmentVariables($c.Trim('"', ' ')).TrimEnd('\')
        if ($c -and -not (Test-KPastaProtegida $c)) { return $c }
    }
    $null
}

# ── Rodar o desinstalador ──────────────────────────────────────
function Test-KNsis([string]$Exe) {
    try {
        $fs = [IO.File]::OpenRead($Exe)
        $buf = New-Object byte[] ([Math]::Min($fs.Length, 2MB)); [void]$fs.Read($buf, 0, $buf.Length); $fs.Close()
        [Text.Encoding]::ASCII.GetString($buf).Contains('Nullsoft')
    } catch { $false }
}

function Get-KComandoDesinstalar($App, [bool]$Silencioso) {
    $modo = if ($Silencioso) { '/qn' } else { '/qb' }
    if ($App.Msi -and $App.Codigo -match '^\{[0-9A-Fa-f-]{36}\}$') {
        return @{ Exe = "$env:SystemRoot\System32\msiexec.exe"; Args = "/x $($App.Codigo) $modo /norestart"; Tipo = 'MSI' }
    }
    $exe, $arg = Split-KLinhaComando $App.Desinstalar
    if ($exe -match 'msiexec') {
        $g = [regex]::Match($arg, '\{[0-9A-Fa-f-]{36}\}').Value
        if ($g) { return @{ Exe = "$env:SystemRoot\System32\msiexec.exe"; Args = "/x $g $modo /norestart"; Tipo = 'MSI' } }
    }
    if ($Silencioso -and $App.Silencioso) {
        $e2, $a2 = Split-KLinhaComando $App.Silencioso
        return @{ Exe = $e2; Args = $a2; Tipo = 'Silencioso do fabricante' }
    }
    if ($Silencioso -and (Split-Path $exe -Leaf) -match '^unins\d{3}\.exe$') {
        return @{ Exe = $exe; Args = "$arg /VERYSILENT /SUPPRESSMSGBOXES /NORESTART".Trim(); Tipo = 'Inno Setup' }
    }
    if ($Silencioso -and (Test-Path -LiteralPath $exe) -and (Test-KNsis $exe)) {
        # _?= faz o NSIS rodar no lugar (sem se copiar pro TEMP), então dá pra esperar ele terminar
        return @{ Exe = $exe; Args = "$arg /S _?=$(Split-Path $exe -Parent)".Trim(); Tipo = 'NSIS' }
    }
    @{ Exe = $exe; Args = $arg; Tipo = 'Interativo' }
}

# Espera o processo e os filhos (Inno e outros se relançam de uma cópia no TEMP)
function Wait-KArvoreProcesso([int]$Id, [int]$TimeoutMin = 30) {
    $arvore = New-Object 'System.Collections.Generic.HashSet[int]'
    [void]$arvore.Add($Id)
    $limite = (Get-Date).AddMinutes($TimeoutMin)
    do {
        Start-Sleep -Milliseconds 300
        $procs = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction SilentlyContinue)
        foreach ($p in $procs) { if ($arvore.Contains([int]$p.ParentProcessId)) { [void]$arvore.Add([int]$p.ProcessId) } }
        $vivos = @($procs | Where-Object { $arvore.Contains([int]$_.ProcessId) })
    } while ($vivos -and (Get-Date) -lt $limite)
}

function Test-KAppAindaInstalado($App) {
    if ($App.Tipo -eq 'Store') { return [bool](Get-AppxPackage | Where-Object PackageFullName -eq $App.Codigo) }
    Test-Path -LiteralPath $App.ChavePS
}

# Passo 1: desinstalador oficial. Devolve 'Removido', 'AindaInstalado' ou 'SemDesinstalador'.
function Invoke-KDesinstaladorApp {
    param([Parameter(Mandatory)]$App, [bool]$Silencioso = $true)
    Write-KLog "Desinstalando $($App.Nome) $($App.Versao)" Info
    if ($App.Tipo -eq 'Store') {
        try { Remove-AppxPackage -Package $App.Codigo -ErrorAction Stop; Write-KLog 'App da Store removido' OK }
        catch { Write-KLog "Não deu pra remover: $($_.Exception.Message)" Erro }
        return $(if (Test-KAppAindaInstalado $App) { 'AindaInstalado' } else { 'Removido' })
    }
    if ($App.Quebrado) {
        Write-KLog 'O desinstalador do programa não existe mais (instalação quebrada): vou direto pros rastros' Aviso
        return 'SemDesinstalador'
    }
    $cmd = Get-KComandoDesinstalar $App $Silencioso
    Write-KLog "Desinstalador: $($cmd.Tipo)$(if ($cmd.Tipo -eq 'Interativo') { ' (siga as telas dele)' })" Detalhe
    try {
        $p = if ($cmd.Args) { Start-Process -FilePath $cmd.Exe -ArgumentList $cmd.Args -PassThru -ErrorAction Stop }
             else { Start-Process -FilePath $cmd.Exe -PassThru -ErrorAction Stop }
        Wait-KArvoreProcesso $p.Id
        Start-Sleep -Seconds 1
        if ($p.HasExited -and $p.ExitCode -notin 0, 3010, 1641, $null) { Write-KLog "Desinstalador terminou com código $($p.ExitCode)" Detalhe }
    } catch { Write-KLog "Não deu pra iniciar o desinstalador: $($_.Exception.Message)" Erro }
    if (Test-KAppAindaInstalado $App) {
        Write-KLog "$($App.Nome) ainda aparece como instalado (desinstalação cancelada ou falhou)" Aviso
        return 'AindaInstalado'
    }
    Write-KLog 'Desinstalador concluído' OK
    'Removido'
}

# ── Caça aos rastros ───────────────────────────────────────────
function ConvertTo-KChaveNome([string]$t) { ($t.ToLowerInvariant() -replace '[^a-z0-9]', '') }

function Get-KPalavrasApp($App) {
    $genericos = 'microsoft', 'microsoftcorporation', 'windows', 'common', 'commonfiles', 'temp', 'programs', 'packages', 'update', 'updater',
                 'installer', 'setup', 'app', 'apps', 'data', 'cache', 'default', 'system', 'users', 'public', 'software', 'tools', 'games',
                 'intel', 'nvidia', 'amd', 'google', 'apple', 'adobe', 'oracle', 'acer', 'lenovo', 'dell', 'hp', 'asus', 'samsung', 'realtek', 'mozilla'
    $nome = $App.Nome -replace '\(.*?\)', '' -replace '[®™©]', ''
    $nome = $nome -replace '\s+v?\d+([.\-_]\d+)+.*$', '' -replace '\s+(x64|x86|64-bit|32-bit|64 bits|32 bits)\s*$', ''
    $nome = $nome.Trim(' ', '-')
    $editor = ($App.Editor -replace ',?\s+(Inc\.?|LLC|Ltd\.?|Limited|Corporation|Corp\.?|GmbH|Co\.?|S\.A\.|AB|B\.V\.|Software|Technologies|Team)\b.*$', '').Trim()
    $produto = @($nome, ($nome -replace '\s+\d+$', ''))
    if ($editor -and $nome -like "$editor *") { $produto += $nome.Substring($editor.Length).Trim() }   # "Google Chrome" → "Chrome"
    if ($App.Pasta) { $produto += (Split-Path $App.Pasta -Leaf) }
    [pscustomobject]@{
        Produto = @($produto | ForEach-Object { ConvertTo-KChaveNome $_ } | Where-Object { $_.Length -ge 4 -and $_ -notin $genericos } | Sort-Object -Unique)
        Editor  = @(@($editor, $(if ($App.Pasta -and -not (Test-KPastaProtegida (Split-Path $App.Pasta -Parent))) { Split-Path (Split-Path $App.Pasta -Parent) -Leaf })) |
                    ForEach-Object { ConvertTo-KChaveNome $_ } | Where-Object { $_.Length -ge 3 } | Sort-Object -Unique)
    }
}

function Get-KTamanhoPasta([string]$Pasta) {
    try { (Get-ChildItem -LiteralPath $Pasta -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { 0 }
}

function Get-KRastrosApp {
    param([Parameter(Mandatory)]$App, [switch]$Forcado)
    $pal = Get-KPalavrasApp $App
    $outras = @(Get-KAppsInstalados | Where-Object { $_.Pasta -and $_.Nome -ne $App.Nome } | ForEach-Object { $_.Pasta.TrimEnd('\') })
    $achados = New-Object System.Collections.Generic.List[object]
    $vistos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $add = {
        param($Tipo, $Caminho, $Confianca, $Obs = '')
        if (-not $vistos.Add("$Tipo|$Caminho")) { return }
        # Não mexe em pasta que contém (ou é) a pasta de outro programa ainda instalado
        if ($Tipo -eq 'Pasta' -and @($outras | Where-Object { $_ -eq $Caminho -or (Test-KDentro $_ $Caminho) })) { return }
        $tam = if ($Tipo -eq 'Pasta') { Get-KTamanhoPasta $Caminho } elseif ($Tipo -in 'Arquivo', 'Atalho') { (Get-Item -LiteralPath $Caminho -Force -ErrorAction SilentlyContinue).Length } else { 0 }
        $achados.Add([pscustomobject]@{ Tipo = $Tipo; Caminho = $Caminho; Confianca = $Confianca; Obs = $Obs; Bytes = [double]$tam; Tamanho = (Format-KTamanho $tam) })
    }
    $casa = { param($n) $pal.Produto -contains (ConvertTo-KChaveNome $n) }
    $dadosUsuario = { param($c) $c -like "$env:APPDATA\*" -or $c -like "$env:LOCALAPPDATA\*" -or $c -like "$env:USERPROFILE\AppData\LocalLow\*" -or $c -like "$env:USERPROFILE\Documents\*" }

    # Pasta de instalação
    if ($App.Pasta -and (Test-Path -LiteralPath $App.Pasta) -and -not (Test-KPastaProtegida $App.Pasta)) { & $add 'Pasta' $App.Pasta 'Alta' 'pasta de instalação' }

    # Pastas com o nome do programa (direto ou dentro da pasta do fabricante)
    $raizes = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, "$env:LOCALAPPDATA\Programs",
                "$env:USERPROFILE\AppData\LocalLow", "$env:USERPROFILE\Documents", "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files") |
              Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique
    foreach ($r in $raizes) {
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue) {
            $user = & $dadosUsuario $d.FullName
            if (& $casa $d.Name) {
                & $add 'Pasta' $d.FullName $(if ($user) { 'Média' } else { 'Alta' }) $(if ($user) { 'dados/configurações do usuário' } else { '' })
            } elseif ($pal.Editor -contains (ConvertTo-KChaveNome $d.Name)) {
                $filhos = @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)
                $doApp = @($filhos | Where-Object { $_.PSIsContainer -and (& $casa $_.Name) })
                foreach ($f in $doApp) { & $add 'Pasta' $f.FullName $(if ($user) { 'Média' } else { 'Alta' }) $(if ($user) { 'dados/configurações do usuário' } else { '' }) }
                # Pasta do fabricante que vai ficar vazia
                if ($filhos.Count -eq 0 -or ($doApp.Count -and $doApp.Count -eq $filhos.Count)) {
                    & $add 'Pasta' $d.FullName 'Média' $(if ($user) { 'dados/configurações do usuário' } else { 'pasta do fabricante (ficaria vazia)' })
                }
            }
        }
    }

    # Registro: HKLM\SOFTWARE, WOW6432Node e HKCU\Software
    foreach ($r in 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\Software') {
        foreach ($k in Get-ChildItem $r -ErrorAction SilentlyContinue) {
            if (& $casa $k.PSChildName) { & $add 'Chave' $k.Name 'Alta' }
            elseif ($pal.Editor -contains (ConvertTo-KChaveNome $k.PSChildName)) {
                $sub = @(Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue)
                $doApp = @($sub | Where-Object { & $casa $_.PSChildName })
                foreach ($s in $doApp) { & $add 'Chave' $s.Name 'Alta' }
                $temValores = @((Get-Item $k.PSPath -ErrorAction SilentlyContinue).Property).Count
                if (-not $temValores -and ($sub.Count -eq 0 -or ($doApp.Count -and $doApp.Count -eq $sub.Count))) { & $add 'Chave' $k.Name 'Média' 'chave do fabricante (ficaria vazia)' }
            }
        }
    }
    if ($App.ChavePS -and (Test-Path -LiteralPath $App.ChavePS)) { & $add 'Chave' $App.Chave $(if ($Forcado) { 'Alta' } else { 'Média' }) 'entrada em Programas instalados' }

    # Atalhos (Iniciar e Área de Trabalho) que apontam pra pasta do programa ou têm o nome dele
    $sh = New-Object -ComObject WScript.Shell
    $locais = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
                "$env:PUBLIC\Desktop", [Environment]::GetFolderPath('Desktop')) | Where-Object { Test-Path $_ }
    foreach ($l in $locais) {
        foreach ($d in Get-ChildItem -LiteralPath $l -Directory -Recurse -Force -ErrorAction SilentlyContinue) {
            if (& $casa $d.Name) { & $add 'Pasta' $d.FullName 'Alta' 'pasta no Menu Iniciar' }
        }
        foreach ($f in Get-ChildItem -LiteralPath $l -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue) {
            $alvo = try { $sh.CreateShortcut($f.FullName).TargetPath } catch { '' }
            if (($App.Pasta -and $alvo -and (Test-KDentro $alvo $App.Pasta)) -or (& $casa $f.BaseName)) { & $add 'Atalho' $f.FullName 'Alta' }
        }
    }

    if ($App.Pasta) {
        # Serviços e drivers rodando de dentro da pasta do programa
        foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
            if ("$($s.PathName)" -like "*$($App.Pasta)\*") { & $add 'Serviço' $s.Name 'Alta' $s.DisplayName }
        }
        # Inicialização automática
        foreach ($rk in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run') {
            $props = Get-ItemProperty $rk -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            foreach ($pp in $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
                if ("$($pp.Value)" -like "*$($App.Pasta)\*" -or (& $casa $pp.Name)) { & $add 'Inicialização' "$((Get-Item $rk).Name)|$($pp.Name)" 'Alta' }
            }
        }
    }
    # Tarefas agendadas que rodam algo da pasta do programa ou têm o nome dele
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        if ($t.TaskPath -like '\Microsoft\*') { continue }
        $execs = @($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
        if (($App.Pasta -and $execs -like "*$($App.Pasta)\*") -or (& $casa $t.TaskName) -or
            @($pal.Produto | Where-Object { $_.Length -ge 5 -and (ConvertTo-KChaveNome $t.TaskName).StartsWith($_) }).Count) {
            & $add 'Tarefa' "$($t.TaskPath)$($t.TaskName)" 'Alta'
        }
    }

    # Remove itens que estão dentro de uma pasta já listada (sai junto)
    $pastas = @($achados | Where-Object Tipo -eq 'Pasta' | ForEach-Object Caminho)
    @($achados | Where-Object { $c = $_.Caminho; -not ($_.Tipo -in 'Pasta', 'Arquivo', 'Atalho' -and @($pastas | Where-Object { Test-KDentro $c $_ }).Count) })
}

# ── Remoção com backup ─────────────────────────────────────────
function Remove-KRastros {
    param([Parameter(Mandatory)][object[]]$Itens, [string]$Nome = 'programa')
    $seguro = ($Nome -replace '[^\w\- ]', '').Trim()
    $bk = Join-Path $KB.Raiz "estado\desinstalados\$(Get-Date -Format 'yyyyMMdd_HHmmss')_$seguro"
    New-Item -ItemType Directory -Path $bk -Force | Out-Null
    Add-Type -AssemblyName Microsoft.VisualBasic
    $n = 0; $erros = 0; $i = 0
    $ordem = @{ 'Serviço' = 0; 'Tarefa' = 1; 'Inicialização' = 2; 'Atalho' = 3; 'Arquivo' = 4; 'Pasta' = 5; 'Chave' = 6 }

    # Processos rodando de dentro das pastas que vão sair
    $pastas = @($Itens | Where-Object Tipo -eq 'Pasta' | ForEach-Object Caminho)
    foreach ($pr in Get-Process -ErrorAction SilentlyContinue) {
        $exe = try { $pr.Path } catch { $null }
        if ($exe -and @($pastas | Where-Object { Test-KDentro $exe $_ }).Count) { Write-KLog "Encerrando $($pr.ProcessName)" Detalhe; try { $pr.Kill() } catch {} }
    }

    foreach ($it in $Itens | Sort-Object { $ordem[$_.Tipo] }) {
        $i++
        try {
            switch ($it.Tipo) {
                'Serviço' {
                    & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$($it.Caminho)" (Join-Path $bk "servico_$i.reg") /y 2>&1 | Out-Null
                    Stop-Service -Name $it.Caminho -Force -ErrorAction SilentlyContinue
                    $r = & sc.exe delete $it.Caminho 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "$r" }
                }
                'Tarefa' {
                    $tp = $it.Caminho.Substring(0, $it.Caminho.LastIndexOf('\') + 1); $tn = $it.Caminho.Substring($it.Caminho.LastIndexOf('\') + 1)
                    Export-ScheduledTask -TaskPath $tp -TaskName $tn | Set-Content (Join-Path $bk "tarefa_$i.xml") -Encoding Unicode
                    Add-Content (Join-Path $bk 'tarefas.txt') "tarefa_$i.xml|$($it.Caminho)" -Encoding UTF8
                    Unregister-ScheduledTask -TaskPath $tp -TaskName $tn -Confirm:$false -ErrorAction Stop
                }
                'Inicialização' {
                    $k, $v = $it.Caminho -split '\|', 2
                    & reg.exe export $k (Join-Path $bk "inicializacao_$i.reg") /y 2>&1 | Out-Null
                    Remove-ItemProperty -Path "Registry::$k" -Name $v -ErrorAction Stop
                }
                'Chave' {
                    & reg.exe export $it.Caminho (Join-Path $bk "chave_$i.reg") /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'backup da chave falhou; não removida' }
                    Remove-Item -LiteralPath "Registry::$($it.Caminho)" -Recurse -Force -ErrorAction Stop
                }
                'Pasta' {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Caminho, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
                default {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($it.Caminho, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
            }
            $n++
            Write-KLog "$($it.Tipo): $($it.Caminho)" Detalhe
        } catch {
            $erros++
            Write-KLog "$($it.Tipo) $($it.Caminho): $($_.Exception.Message.Trim())" Aviso
        }
    }
    $Itens | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $bk 'itens.json') -Encoding UTF8
    Write-KLog "$n rastro(s) removido(s)$(if ($erros) { ", $erros não (em uso ou protegido)" }). Arquivos na Lixeira; registro e tarefas em $bk" $(if ($erros) { 'Aviso' } else { 'OK' })
    $bk
}

# Desfaz a parte de registro/tarefas/serviços (os arquivos voltam pela Lixeira)
function Restore-KRastros([Parameter(Mandatory)][string]$Pasta) {
    foreach ($r in Get-ChildItem $Pasta -Filter *.reg) { & reg.exe import $r.FullName 2>&1 | Out-Null; Write-KLog "Registro restaurado: $($r.Name)" Detalhe }
    $lista = Join-Path $Pasta 'tarefas.txt'
    if (Test-Path $lista) {
        foreach ($l in Get-Content $lista -Encoding UTF8) {
            $arq, $cam = $l -split '\|', 2
            try { Register-ScheduledTask -Xml (Get-Content (Join-Path $Pasta $arq) -Raw) -TaskName $cam -Force | Out-Null; Write-KLog "Tarefa restaurada: $cam" Detalhe } catch { Write-KLog "Tarefa $cam`: $($_.Exception.Message)" Aviso }
        }
    }
    Write-KLog 'Registro e tarefas restaurados. Pastas e atalhos: restaure pela Lixeira. Serviços voltam após reiniciar.' OK
}

# Fluxo completo pra linha de comando: desinstala, caça rastros e remove os de confiança alta
function Invoke-KDesinstalacaoCompleta {
    param([Parameter(Mandatory)][string]$Nome, [switch]$Forcar, [bool]$Silencioso = $true)
    $apps = @(Get-KAppsInstalados | Where-Object { $_.Nome -like $Nome -or $_.Nome -eq $Nome })
    if ($apps.Count -ne 1) {
        if (-not $apps) { Write-KLog "Nenhum programa instalado com o nome '$Nome' (veja -ListarInstalados; aceita curinga *)" Erro }
        else { Write-KLog "Mais de um programa com '$Nome': $(($apps | ForEach-Object Nome) -join ' | ')" Erro }
        return
    }
    $app = $apps[0]
    $st = Invoke-KDesinstaladorApp $app $Silencioso
    if ($st -eq 'AindaInstalado' -and -not $Forcar) { Write-KLog 'Nada removido. Use -Forcar pra limpar os rastros mesmo assim.' Aviso; return }
    if ($app.Tipo -eq 'Store') { return }
    $r = @(Get-KRastrosApp $app -Forcado:($st -ne 'Removido'))
    foreach ($x in $r) { Write-KLog ("[{0}] {1}: {2} {3}" -f $x.Confianca, $x.Tipo, $x.Caminho, $x.Obs) Detalhe }
    $alta = @($r | Where-Object Confianca -eq 'Alta')
    if ($alta) { Remove-KRastros $alta $app.Nome | Out-Null } else { Write-KLog 'Nenhum rastro de confiança alta' OK }
    $media = @($r | Where-Object Confianca -ne 'Alta').Count
    if ($media) { Write-KLog "$media item(ns) de confiança média ficaram (dados do usuário etc.); revise na aba Desinstalar." Info }
}
