# ============================================================
#  Programas e runtimes: instalar / desinstalar / atualizar.
#  winget pros pacotes, recurso do Windows pro .NET 3.5 e
#  Office Deployment Tool (CDN oficial da Microsoft) pro Microsoft 365.
# ============================================================

# ── winget ─────────────────────────────────────────────────────
function Get-KCaminhoWinget {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    $a = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $a) { return $a }
    # Admin sem o alias no PATH: roda direto da pasta do pacote
    $pk = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($pk) { $e = Join-Path $pk.InstallLocation 'winget.exe'; if (Test-Path $e) { return $e } }
}

# Windows recém-instalado às vezes tem o winget provisionado mas não registrado; LTSC não tem nenhum.
function Install-KWinget {
    if (Get-KCaminhoWinget) { return $true }
    Write-KLog 'winget não encontrado: registrando o Instalador de Aplicativos' Info
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch {}
    if (Get-KCaminhoWinget) { Write-KLog 'winget pronto' OK; return $true }

    Write-KLog 'Baixando o winget da Microsoft' Info
    $dir = Join-Path $KB.Raiz 'cache\winget'
    try {
        $deps = @(
            Get-KDownload 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' (Join-Path $dir 'VCLibs.appx')
            Get-KDownload 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx' (Join-Path $dir 'UIXaml.appx')
        )
        foreach ($d in $deps) { try { Add-AppxPackage -Path $d -ErrorAction Stop } catch {} }   # já instalada = erro inofensivo
        Add-AppxPackage -Path (Get-KDownload 'https://aka.ms/getwinget' (Join-Path $dir 'winget.msixbundle')) -ErrorAction Stop
    } catch { Write-KLog "Não deu pra instalar o winget: $($_.Exception.Message)" Erro }
    if (Get-KCaminhoWinget) { Write-KLog 'winget instalado' OK; return $true }
    Write-KLog 'Instale o "Instalador de Aplicativos" pela Microsoft Store e tente de novo.' Aviso
    try { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' } catch {}
    $false
}

function Get-KCodigoWinget([int]$Codigo) {
    $hex = '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes($Codigo), 0)
    $r = switch ($hex) {
        '0x00000000' { 'OK' }
        '0x8A15002B' { 'Atual' }          # nenhuma atualização aplicável
        '0x8A150061' { 'JaInstalado' }
        '0x8A150109' { 'Reinicio' }       # instalado, falta reiniciar
        '0x8A15010A' { 'Reinicio' }
        '0x00000BC2' { 'Reinicio' }       # 3010 do MSI
        '0x00000669' { 'Reinicio' }       # 1641
        '0x8A150014' { 'NaoEncontrado' }  # desinstalar algo que não está instalado
        '0x8A150010' { 'SemInstalador' }  # não há instalador pro escopo pedido (ex.: só existe por usuário)
        '0x8A15007D' { 'EscopoUsuario' }  # instalado só pro usuário: admin não consegue desinstalar
        default      { 'Erro' }
    }
    [pscustomobject]@{ Resultado = $r; Hex = $hex }
}

function Invoke-KWinget {
    param(
        [Parameter(Mandatory)][ValidateSet('install', 'uninstall', 'upgrade')][string]$Acao,
        [string]$Pacote,             # vazio + upgrade = atualizar tudo
        [string]$Fonte = 'winget',
        [string]$Escopo,
        [string]$Custom,
        [string]$Override
    )
    $wg = Get-KCaminhoWinget
    if (-not $wg) { return [pscustomobject]@{ Resultado = 'Erro'; Hex = 'sem winget'; Saida = @() } }
    $a = @($Acao)
    if ($Pacote) {
        $a += '--id', "`"$Pacote`"", '--exact'
        if ($Acao -ne 'uninstall' -and $Fonte) { $a += '--source', $Fonte }
        if ($Escopo) { $a += '--scope', $Escopo }
        if ($Acao -eq 'install' -and $Override) { $a += '--override', "`"$Override`"" }
        elseif ($Acao -eq 'install' -and $Custom) { $a += '--custom', "`"$Custom`"" }
    } else { $a += '--all' }
    $a += '--silent', '--disable-interactivity', '--accept-source-agreements'
    if ($Acao -ne 'uninstall') { $a += '--accept-package-agreements' }
    $r = Invoke-KNativo $wg $a -Utf8 -TimeoutMin 45
    $c = Get-KCodigoWinget $r.Codigo
    [pscustomobject]@{ Resultado = $c.Resultado; Hex = $c.Hex; Saida = $r.Saida }
}

# Pacote instalado só pro usuário não sai com o winget elevado (0x8A15007D):
# roda o winget como o usuário logado, sem elevação, por uma tarefa agendada temporária.
function Invoke-KWingetComoUsuario {
    param([Parameter(Mandatory)][string[]]$Argumentos)
    $usuario = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $usuario) { Write-KLog 'Nenhum usuário logado pra rodar o winget sem elevação' Aviso; return $null }
    $saida = Join-Path $env:PUBLIC "kbench-winget-$PID.txt"
    $nome = "K-Bench winget $PID"
    $cmd = "/c `"`"%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe`" $($Argumentos -join ' ') > `"$saida`" 2>&1`""
    try {
        $acao = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $cmd
        $princ = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $nome -Action $acao -Principal $princ -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $nome -ErrorAction Stop
        $limite = (Get-Date).AddMinutes(20)
        Start-Sleep -Seconds 2
        while ((Get-ScheduledTask -TaskName $nome).State -in 'Running', 'Queued' -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 700 }
        $cod = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32](Get-ScheduledTaskInfo -TaskName $nome).LastTaskResult), 0)
        if (Test-Path $saida) {
            foreach ($l in Get-Content $saida -Encoding UTF8) {
                $l = $l.Trim()
                if ($l -and $l.Length -gt 2 -and $l -notmatch '[█▒]|\d\s?[KMG]B\s/\s|^\s*[-\\|/]\s*$') { Write-KLog $l Detalhe }
            }
        }
        Get-KCodigoWinget $cod
    } catch {
        Write-KLog "Não deu pra rodar como usuário: $($_.Exception.Message)" Erro
        $null
    } finally {
        Unregister-ScheduledTask -TaskName $nome -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item $saida -Force -ErrorAction SilentlyContinue
    }
}

# Ids instalados que o winget reconhece (winget export: JSON, não depende do idioma)
function Get-KPacotesInstalados {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $wg = Get-KCaminhoWinget
    if (-not $wg) { return , $set }
    $arq = Join-Path $env:TEMP "kbench-winget-$PID.json"
    Remove-Item $arq -ErrorAction SilentlyContinue
    Invoke-KNativo $wg @('export', '-o', "`"$arq`"", '--accept-source-agreements', '--disable-interactivity') -Utf8 -SemLog | Out-Null
    if (Test-Path $arq) {
        try {
            $j = Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($s in $j.Sources) { foreach ($pk in $s.Packages) { [void]$set.Add($pk.PackageIdentifier) } }
        } catch {}
        Remove-Item $arq -ErrorAction SilentlyContinue
    }
    , $set
}

function Get-KOfficeInstalado {
    $ids = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -Name ProductReleaseIds -ErrorAction SilentlyContinue).ProductReleaseIds
    @("$ids" -split ',' | Where-Object { $_ })
}

function Test-KRecursoAtivo([string]$Nome) {
    $f = Get-CimInstance Win32_OptionalFeature -Filter "Name='$Nome'" -ErrorAction SilentlyContinue
    [bool]($f -and $f.InstallState -eq 1)
}

# ── Situação ───────────────────────────────────────────────────
function Get-KSituacaoProgramas {
    $temWinget = [bool](Get-KCaminhoWinget)
    $inst = Get-KPacotesInstalados
    $office = Get-KOfficeInstalado
    foreach ($p in Get-KProgramas) {
        $pacotes = @($p.Pacote -split ',')
        $n = switch ($p.Fonte) {
            'odt'  { [int]($office -contains $p.Pacote) }
            'feat' { [int](Test-KRecursoAtivo $p.Pacote) }
            default {
                if ($p.Arquivo -and (Test-Path ([Environment]::ExpandEnvironmentVariables($p.Arquivo)))) { $pacotes.Count }
                else { @($pacotes | Where-Object { $inst.Contains($_) }).Count }
            }
        }
        $sit = if ($n -ge $pacotes.Count) { 'Instalado' } elseif ($n -gt 0) { 'Parcial' }
               elseif ($p.Fonte -in 'winget', 'msstore' -and -not $temWinget) { 'Sem winget' } else { 'Não instalado' }
        $o = $p.PSObject.Copy()
        $o | Add-Member NoteProperty Situacao $sit
        $o | Add-Member NoteProperty Instalado ($sit -eq 'Instalado')
        $o
    }
}

# ── Microsoft 365 (ODT) ────────────────────────────────────────
function Invoke-KOffice {
    param([Parameter(Mandatory)][string]$Produto, [switch]$Remover)
    $dir = Join-Path $KB.Raiz 'cache\odt'
    try { $setup = Get-KDownload 'https://officecdn.microsoft.com/pr/wsus/setup.exe' (Join-Path $dir 'setup.exe') -Assinatura }
    catch { Write-KLog "Office Deployment Tool: $($_.Exception.Message)" Erro; return $false }

    $cfg = Join-Path $dir 'config.xml'
    $xml = if ($Remover) {
        '<Configuration><Remove All="TRUE"/><Display Level="None" AcceptEULA="TRUE"/></Configuration>'
    } else {
        # Sem OneDrive/Teams/Skype/Access/Publisher; idioma do Windows (português se não achar)
        @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="$Produto">
      <Language ID="MatchOS" Fallback="pt-br"/>
      <ExcludeApp ID="Access"/><ExcludeApp ID="Groove"/><ExcludeApp ID="Lync"/><ExcludeApp ID="OneDrive"/>
      <ExcludeApp ID="Publisher"/><ExcludeApp ID="Teams"/><ExcludeApp ID="Bing"/>
    </Product>
  </Add>
  <Updates Enabled="TRUE" Channel="Current"/>
  <Display Level="None" AcceptEULA="TRUE"/>
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE"/>
</Configuration>
"@
    }
    Set-Content -LiteralPath $cfg -Value $xml -Encoding UTF8
    Write-KLog "$(if ($Remover) { 'Removendo' } else { 'Baixando e instalando' }) o Microsoft 365 (pode levar 10-30 min)" Info
    $r = Invoke-KNativo $setup @('/configure', "`"$cfg`"") -TimeoutMin 120
    $tem = (Get-KOfficeInstalado) -contains $Produto
    if ($Remover) { -not (Get-KOfficeInstalado) } else {
        if ($tem) { Write-KLog 'Microsoft 365 instalado. Abra o Word e entre com a conta do cliente pra ativar.' OK }
        else { Write-KLog "Microsoft 365 não instalou (código $($r.Codigo)). Detalhes em %TEMP%\<PC>-*.log do Office." Erro }
        $tem
    }
}

# ── Instalar / desinstalar ─────────────────────────────────────
function Get-KProgramaPorId([string]$Id) {
    $p = Get-KProgramas | Where-Object Id -eq $Id
    if (-not $p) { Write-KLog "Programa desconhecido: $Id (veja -ListarProgramas)" Erro }
    $p
}

function Install-KPrograma {
    param([Parameter(Mandatory)]$Programa)
    $p = if ($Programa -is [string]) { Get-KProgramaPorId $Programa } else { $Programa }
    if (-not $p) { return 'Erro' }
    Write-KLog "Instalando $($p.Nome)" Info
    switch ($p.Fonte) {
        'odt' { return $(if (Invoke-KOffice $p.Pacote) { 'OK' } else { 'Erro' }) }
        'feat' {
            try {
                $r = Enable-WindowsOptionalFeature -Online -FeatureName $p.Pacote -All -NoRestart -ErrorAction Stop
                Write-KLog "$($p.Nome): instalado" OK
                return $(if ($r.RestartNeeded) { 'Reinicio' } else { 'OK' })
            } catch { Write-KLog "$($p.Nome): $($_.Exception.Message)" Erro; return 'Erro' }
        }
    }
    $final = 'OK'
    foreach ($pk in $p.Pacote -split ',') {
        # Pra máquina toda (vale pra todas as contas e o admin consegue desinstalar depois);
        # se o pacote só tem instalador por usuário, instala assim mesmo
        if ($p.Fonte -eq 'winget') {
            $r = Invoke-KWinget install $pk $p.Fonte -Escopo machine -Custom $p.Custom -Override $p.Override
            if ($r.Resultado -eq 'SemInstalador') { Write-KLog "$pk só instala por usuário" Detalhe; $r = Invoke-KWinget install $pk $p.Fonte -Custom $p.Custom -Override $p.Override }
        } else { $r = Invoke-KWinget install $pk $p.Fonte }
        switch ($r.Resultado) {
            { $_ -in 'OK', 'JaInstalado', 'Atual' } { break }
            'Reinicio' { if ($final -eq 'OK') { $final = 'Reinicio' } }
            default { $final = 'Erro'; Write-KLog "$pk`: falhou ($($r.Hex))" Erro }
        }
    }
    if ($final -ne 'Erro') { Write-KLog "$($p.Nome): instalado$(if ($final -eq 'Reinicio') { ' (falta reiniciar)' })" OK }
    $final
}

function Uninstall-KPrograma {
    param([Parameter(Mandatory)]$Programa)
    $p = if ($Programa -is [string]) { Get-KProgramaPorId $Programa } else { $Programa }
    if (-not $p) { return 'Erro' }
    if ($p.SemDesinstalar) { Write-KLog "$($p.Nome) não tem desinstalador: fica como está" Aviso; return 'Ignorado' }
    Write-KLog "Desinstalando $($p.Nome)" Info
    switch ($p.Fonte) {
        'odt' { return $(if (Invoke-KOffice $p.Pacote -Remover) { 'OK' } else { 'Erro' }) }
        'feat' {
            try { Disable-WindowsOptionalFeature -Online -FeatureName $p.Pacote -NoRestart -ErrorAction Stop | Out-Null; Write-KLog "$($p.Nome): removido" OK; return 'OK' }
            catch { Write-KLog "$($p.Nome): $($_.Exception.Message)" Erro; return 'Erro' }
        }
    }
    $final = 'OK'
    $pacotes = @($p.Pacote -split ','); [array]::Reverse($pacotes)
    foreach ($pk in $pacotes) {
        $r = Invoke-KWinget uninstall $pk $p.Fonte
        if ($r.Resultado -eq 'EscopoUsuario') {
            Write-KLog 'Instalado só pro usuário: desinstalando sem elevação' Detalhe
            $u = Invoke-KWingetComoUsuario @('uninstall', '--id', "`"$pk`"", '--exact', '--silent', '--disable-interactivity', '--accept-source-agreements')
            if ($u) { $r = $u }
        }
        if ($r.Resultado -notin 'OK', 'NaoEncontrado', 'Reinicio') { $final = 'Erro'; Write-KLog "$pk`: falhou ($($r.Hex))" Erro }
    }
    if ($final -eq 'OK') { Write-KLog "$($p.Nome): desinstalado" OK }
    $final
}

function Update-KProgramas {
    Write-KLog 'Atualizando todos os programas (winget upgrade --all)' Info
    if (-not (Install-KWinget)) { return }
    $r = Invoke-KWinget upgrade
    switch ($r.Resultado) {
        { $_ -in 'OK', 'Atual' } { Write-KLog 'Programas atualizados' OK }
        'Reinicio' { Write-KLog 'Programas atualizados (reinicie pra concluir)' OK }
        default { Write-KLog "Alguns programas não atualizaram ($($r.Hex)). Veja as linhas acima." Aviso }
    }
}

function Invoke-KProgramas {
    param([string[]]$Instalar = @(), [string[]]$Desinstalar = @())
    $cat = @(Get-KProgramas)
    $ordem = @{}; for ($i = 0; $i -lt $cat.Count; $i++) { $ordem[$cat[$i].Id] = $i }   # runtimes primeiro
    $precisaWinget = @($cat | Where-Object { $_.Id -in ($Instalar + $Desinstalar) -and $_.Fonte -in 'winget', 'msstore' })
    if ($precisaWinget -and -not (Install-KWinget)) { return }

    $res = @{ OK = 0; Erro = 0; Reinicio = 0 }
    foreach ($id in $Desinstalar | Sort-Object { $ordem[$_] }) { $r = Uninstall-KPrograma $id; if ($r -eq 'Erro') { $res.Erro++ } elseif ($r -eq 'OK') { $res.OK++ } }
    $total = @($Instalar).Count; $n = 0
    foreach ($id in $Instalar | Sort-Object { $ordem[$_] }) {
        $n++
        Write-KProgresso 'Programas' "$n de $total"
        $r = Install-KPrograma $id
        switch ($r) { 'OK' { $res.OK++ } 'Reinicio' { $res.OK++; $res.Reinicio++ } default { $res.Erro++ } }
    }
    $msg = "$($res.OK) concluído(s)$(if ($res.Erro) { ", $($res.Erro) com erro" })"
    Write-KLog "Programas: $msg" $(if ($res.Erro) { 'Aviso' } else { 'OK' })
    if ($res.Reinicio) { Write-KLog 'Reinicie o PC pra concluir algumas instalações.' Aviso }
}
