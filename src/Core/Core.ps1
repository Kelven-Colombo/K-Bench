# ============================================================
#  Core: estado global, log, admin, Windows, comandos nativos
# ============================================================

if (-not $global:KB) {
    $global:KB = [hashtable]::Synchronized(@{
        Versao     = '1.0.1'
        Raiz       = Join-Path $env:ProgramData 'K-Bench'
        LogFile    = $null
        LogSink    = $null      # ConcurrentQueue quando a GUI está ativa
        Silencioso = $false
    })
    $KB.LogDir = Join-Path $KB.Raiz 'logs'
}

# ── Log ────────────────────────────────────────────────────────
function Start-KLog {
    param([string]$Tag = 'kbench')
    New-Item -ItemType Directory -Path $KB.LogDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $KB.LogFile = Join-Path $KB.LogDir "$($env:COMPUTERNAME)_${stamp}_$Tag.log"
    $win = Get-KWindows
    Write-KLog "K-Bench $($KB.Versao) | $env:COMPUTERNAME | $($win.Nome) $($win.Versao) (build $($win.Build).$($win.UBR)) | $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
    $KB.LogFile
}

function Write-KLog {
    param(
        [Parameter(Position = 0)][string]$Mensagem = '',
        [Parameter(Position = 1)][ValidateSet('Info','OK','Aviso','Erro','Titulo','Detalhe')][string]$Nivel = 'Info'
    )
    $linha = switch ($Nivel) {
        'Titulo'  { "`r`n===[ $Mensagem ]===" }
        'OK'      { "  [OK] $Mensagem" }
        'Aviso'   { "  [!]  $Mensagem" }
        'Erro'    { "  [X]  $Mensagem" }
        'Detalhe' { "       $Mensagem" }
        default   { "  $Mensagem" }
    }
    if ($KB.LogFile) {
        try { Add-Content -LiteralPath $KB.LogFile -Value $linha -Encoding UTF8 -ErrorAction Stop } catch {}
    }
    if ($KB.LogSink) {
        $KB.LogSink.Enqueue([pscustomobject]@{ Tipo = 'Log'; Nivel = $Nivel; Texto = $linha })
    } else {
        $cor = @{ OK = 'Green'; Aviso = 'Yellow'; Erro = 'Red'; Titulo = 'Cyan'; Detalhe = 'Gray'; Info = 'White' }[$Nivel]
        Write-Host $linha -ForegroundColor $cor
    }
}

# Progresso (barra do DISM, % do SFC...): vai pra barra de status, não pro arquivo
function Write-KProgresso {
    param([string]$Atividade, [string]$Texto)
    if ($KB.LogSink) {
        $KB.LogSink.Enqueue([pscustomobject]@{ Tipo = 'Progresso'; Nivel = 'Info'; Texto = "$Atividade  $Texto" })
    } else {
        Write-Progress -Activity $Atividade -Status $Texto
    }
}

# ── Ambiente ───────────────────────────────────────────────────
function Test-KAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-KWindows {
    $cv    = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuildNumber
    [pscustomobject]@{
        Build  = $build
        UBR    = $cv.UBR
        Win11  = $build -ge 22000
        Nome   = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }  # ProductName mente no 11
        Versao = $cv.DisplayVersion
        Edicao = $cv.EditionID
    }
}

function Test-KNaBateria {
    $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    [bool]($b -and $b.BatteryStatus -eq 1)   # 1 = descarregando
}

function Test-KReinicioPendente {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
}

function Get-KEspacoLivreGB {
    param([string]$Letra = $env:SystemDrive.TrimEnd(':'))
    [math]::Round((Get-Volume -DriveLetter $Letra).SizeRemaining / 1GB, 2)
}

# ── Comandos nativos (DISM, SFC, netsh...) ─────────────────────
# Captura a saída linha a linha pro log; linhas de progresso (xx%) vão só pra barra de status.
function Invoke-KNativo {
    param(
        [Parameter(Mandatory)][string]$Arquivo,
        [string[]]$Argumentos = @(),
        [switch]$Unicode,          # sfc escreve UTF-16 quando redirecionado
        [switch]$Utf8,             # winget
        [switch]$SemLog,
        [int]$TimeoutMin = 0
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Arquivo
    $psi.Arguments              = $Argumentos -join ' '
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = if ($Unicode) { [Text.Encoding]::Unicode } elseif ($Utf8) { [Text.Encoding]::UTF8 }
                                  else { [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }

    $p      = [Diagnostics.Process]::Start($psi)
    $errTsk = $p.StandardError.ReadToEndAsync()
    $saida  = New-Object System.Collections.Generic.List[string]
    $nome   = [IO.Path]::GetFileNameWithoutExtension($Arquivo).ToUpper()
    $limite = if ($TimeoutMin -gt 0) { (Get-Date).AddMinutes($TimeoutMin) } else { [datetime]::MaxValue }

    while ($null -ne ($l = $p.StandardOutput.ReadLine())) {
        $l = $l.Replace([string][char]0, '').TrimEnd()
        if (-not $l.Trim()) { continue }
        # barra do winget (█▒, "2 MB / 10 MB", girador -\|/) também é progresso
        if ($l.Length -lt 90 -and ($l -match '\d{1,3}([.,]\d+)?\s?%' -or $l -match '[█▒]|\d\s?[KMG]B\s/\s' -or $l -match '^\s*[-\\|/]\s*$')) {
            Write-KProgresso $nome $l.Trim()
            continue
        }
        $saida.Add($l)
        if (-not $SemLog) { Write-KLog $l.Trim() Detalhe }
        if ((Get-Date) -gt $limite) {
            try { $p.Kill() } catch {}
            Write-KLog "$nome excedeu $TimeoutMin min e foi encerrado" Aviso
            break
        }
    }
    $p.WaitForExit()
    $err = $errTsk.Result
    if ($err -and $err.Trim() -and -not $SemLog) { Write-KLog $err.Trim() Detalhe }

    [pscustomobject]@{ Codigo = $p.ExitCode; Saida = $saida.ToArray(); Erro = $err }
}

# ── Download (só de URL oficial; -Assinatura exige executável assinado pela Microsoft) ──
function Get-KDownload {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Destino, [switch]$Assinatura)
    New-Item -ItemType Directory -Path (Split-Path $Destino) -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'   # a barra do Invoke-WebRequest deixa o download 10x mais lento no PS 5.1
    Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing -ErrorAction Stop
    if ($Assinatura) {
        $s = Get-AuthenticodeSignature -LiteralPath $Destino
        if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            Remove-Item -LiteralPath $Destino -Force -ErrorAction SilentlyContinue
            throw "assinatura digital inválida em $(Split-Path $Destino -Leaf); arquivo descartado"
        }
    }
    $Destino
}

# ── Ponto de restauração ───────────────────────────────────────
function New-KPontoRestauracao {
    param([string]$Descricao = 'K-Bench')
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqAntiga = (Get-ItemProperty $k -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        # O Windows bloqueia mais de 1 ponto a cada 24h; libera só durante a criação
        Set-ItemProperty $k -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord
        Checkpoint-Computer -Description $Descricao -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-KLog "Ponto de restauração criado: $Descricao" OK
        $true
    } catch {
        Write-KLog "Não foi possível criar ponto de restauração: $($_.Exception.Message)" Aviso
        $false
    } finally {
        if ($null -ne $freqAntiga) { Set-ItemProperty $k -Name SystemRestorePointCreationFrequency -Value $freqAntiga -Type DWord }
        else { Remove-ItemProperty $k -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
    }
}
