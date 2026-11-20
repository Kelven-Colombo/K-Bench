# ============================================================
#  Bateria e energia (notebooks)
#  Diagnóstico: saúde, consumo real, suspensão, desligamentos
#  incompletos, plano de energia, GPU dedicada, quem acorda o PC.
#  Correções: cada uma guarda o valor anterior e pode ser desfeita.
# ============================================================

# ── Plano de energia (independente do idioma) ──────────────────
# powercfg /qh imprime o valor atual AC e DC como os dois últimos "0x..." da saída
function Get-KPowerSetting {
    param([Parameter(Mandatory)][string]$Sub, [Parameter(Mandatory)][string]$Set)
    $txt = powercfg.exe /qh scheme_current $Sub $Set 2>$null | Out-String
    $hex = @([regex]::Matches($txt, '0x([0-9a-fA-F]{8})') | ForEach-Object { [Convert]::ToInt64($_.Groups[1].Value, 16) })
    if ($hex.Count -lt 2) { return $null }
    [pscustomobject]@{ AC = $hex[-2]; DC = $hex[-1] }
}

function Set-KPowerSetting {
    param([Parameter(Mandatory)][string]$Sub, [Parameter(Mandatory)][string]$Set, $AC, $DC)
    # powercfg escreve erro no stderr e segue; aqui qualquer falha vira exceção (quem chama registra "falhou")
    $rodar = {
        param([string[]]$a)
        $saida = (& powercfg.exe @a 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "powercfg $($a[0]) $Set`: $saida" }
    }
    if ($null -ne $AC) { & $rodar @('/setacvalueindex', 'scheme_current', $Sub, $Set, "$AC") }
    if ($null -ne $DC) { & $rodar @('/setdcvalueindex', 'scheme_current', $Sub, $Set, "$DC") }
    & $rodar @('/setactive', 'scheme_current')
}

# Modo de energia (Configurações > Sistema > Energia). O Windows ignora escrita direta no registro;
# o caminho certo é a API que a própria tela de Configurações usa (Windows 11 / 10 recente).
function Initialize-KPowrProf {
    if ('KBench.PowrProf' -as [type]) { return $true }
    try {
        Add-Type -Namespace KBench -Name PowrProf -MemberDefinition @'
[DllImport("powrprof.dll")] public static extern uint PowerGetUserConfiguredDCPowerMode(out Guid mode);
[DllImport("powrprof.dll")] public static extern uint PowerSetUserConfiguredDCPowerMode(ref Guid mode);
[DllImport("powrprof.dll")] public static extern uint PowerGetUserConfiguredACPowerMode(out Guid mode);
'@ -ErrorAction Stop
        $true
    } catch { $false }
}

function Get-KGuidEficiencia { '961cc777-2547-4f9d-8174-7d86181b8a7a' }   # modo "Melhor eficiência energética"

function Get-KOverlayEnergia {
    if (Initialize-KPowrProf) {
        try {
            $dc = [guid]::Empty; $ac = [guid]::Empty
            if ([KBench.PowrProf]::PowerGetUserConfiguredDCPowerMode([ref]$dc) -eq 0 -and
                [KBench.PowrProf]::PowerGetUserConfiguredACPowerMode([ref]$ac) -eq 0) {
                $f = { param($g) if ($g -eq [guid]::Empty) { '' } else { "$g" } }
                return [pscustomobject]@{ AC = (& $f $ac); DC = (& $f $dc) }
            }
        } catch {}
    }
    $k = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction SilentlyContinue
    [pscustomobject]@{ AC = "$($k.ActiveOverlayAcPowerScheme)"; DC = "$($k.ActiveOverlayDcPowerScheme)" }
}

function Set-KOverlayEnergiaDC([string]$Guid) {
    if (-not (Initialize-KPowrProf)) { throw 'API de modo de energia indisponível nesta versão do Windows' }
    $g = if ($Guid) { [guid]$Guid } else { [guid]::Empty }   # vazio = Equilibrado
    $rc = [KBench.PowrProf]::PowerSetUserConfiguredDCPowerMode([ref]$g)
    if ($rc -ne 0) { throw "PowerSetUserConfiguredDCPowerMode retornou $rc" }
}

function Get-KNomeOverlay([string]$Guid) {
    switch ($Guid) {
        '961cc777-2547-4f9d-8174-7d86181b8a7a' { 'Melhor eficiência' }
        'ded574b5-45a0-4f42-8737-46345c09c238' { 'Melhor desempenho' }
        ''                                     { 'Equilibrado' }
        '00000000-0000-0000-0000-000000000000' { 'Equilibrado' }
        default                                { "Personalizado ($Guid)" }
    }
}

# ── Relatório de bateria do Windows (XML) ──────────────────────
function Get-KRelatorioBateriaXml {
    param([int]$Dias = 14)
    $arq = Join-Path $env:TEMP "kbench-bateria-$PID.xml"
    powercfg.exe /batteryreport /xml /output "$arq" /duration $Dias 2>$null | Out-Null
    if (-not (Test-Path $arq)) { return $null }
    try { [xml](Get-Content $arq -Raw -Encoding UTF8) } finally { Remove-Item $arq -Force -ErrorAction SilentlyContinue }
}

function Get-KMediana([double[]]$v) {
    if (-not $v) { return $null }
    $s = $v | Sort-Object
    $m = [int][math]::Floor($s.Count / 2)
    if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 }
}

# ── GPU dedicada ───────────────────────────────────────────────
function Get-KGpuDedicada {
    # Dispositivo de vídeo da NVIDIA/AMD (não Intel, não virtual) + estado de energia atual (D0 = acordada, D3 = dormindo)
    $dev = Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue |
           Where-Object { $_.FriendlyName -match 'NVIDIA|Radeon RX|Radeon Pro' } | Select-Object -First 1
    if (-not $dev) { return $null }
    $pd = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName DEVPKEY_Device_PowerData -ErrorAction SilentlyContinue).Data
    $estado = if ($pd -and $pd.Length -ge 8) { [BitConverter]::ToInt32($pd, 4) } else { 0 }
    [pscustomobject]@{ Nome = $dev.FriendlyName; Estado = "D$([math]::Max(0, $estado - 1))"; Acordada = ($estado -eq 1) }
}

function Get-KProcessosNaGpuDedicada {
    # Contadores de GPU por processo; a GPU NVIDIA é a que tem motor "OFA" (Optical Flow) ou "VR"
    $motores = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue |
               ForEach-Object {
                   if ($_.Name -match 'pid_(\d+)_luid_(0x\w+?_0x\w+?)_phys_\d+_eng_\d+_engtype_(\w*)') {
                       [pscustomobject]@{ Pid = [int]$Matches[1]; Luid = $Matches[2]; Tipo = $Matches[3] }
                   }
               }
    $luid = ($motores | Where-Object { $_.Tipo -match '^(OFA|VR)' } | Select-Object -First 1).Luid
    if (-not $luid) { return @() }
    $pids = $motores | Where-Object Luid -eq $luid | Select-Object -ExpandProperty Pid -Unique
    foreach ($p in $pids) {
        $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
        if ($proc -and $proc.Name -notin 'System', 'Idle') { $proc.Name }
    }
}

# Serviços em segundo plano conhecidos por gastar bateria/acordar a GPU sem necessidade.
# Alvo: Manual (inicia quando um app pedir) ou Disabled (quando o fabricante religa sozinho mesmo em manual).
function Get-KServicosGastoes {
    @(
        [pscustomobject]@{ Nome = 'PresentMonSharedService'; Alvo = 'Manual';   Motivo = 'Telemetria de FPS da Intel; fica com a GPU dedicada aberta' }
        [pscustomobject]@{ Nome = 'ESRV_SVC_QUEENCREEK';     Alvo = 'Disabled'; Motivo = 'Coleta de uso da Intel (SUR/Driver Assistant); acorda a CPU, costuma travar e religa sozinho em manual' }
        # O SurSvc abre o esrv.exe por conta própria mesmo com o serviço acima desativado
        [pscustomobject]@{ Nome = 'SystemUsageReportSvc_QUEENCREEK'; Alvo = 'Disabled'; Motivo = 'Relatório de uso da Intel (SUR); reabre o esrv.exe mesmo com o Energy Server desativado' }
    )
}

# ── Análise de 60 s (powercfg /energy) ─────────────────────────
# O HTML tem classes fixas (error/warning/info-log-entry, detail-name), então dá pra ler em qualquer idioma.
function Get-KUltimaAnaliseEnergia {
    Get-ChildItem $KB.LogDir -Filter '*_energia_*.html' -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -gt (Get-Date).AddDays(-7) |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Read-KAnaliseEnergia {
    param([Parameter(Mandatory)][string]$Arquivo)
    $h = [IO.File]::ReadAllText($Arquivo)
    $re = '<div class="log-entry">\s*<div class="\s*(\w+)-log-entry\s*">\s*<div class="log-entry-header">(.*?)</div>(.*?)</div>\s*</div>\s*</div>'
    foreach ($m in [regex]::Matches($h, $re, 'Singleline')) {
        $vals = @([regex]::Matches($m.Groups[3].Value, '<span class="detail-name">.*?</span></td>\s*<td>(.*?)</td>', 'Singleline') |
                  ForEach-Object { [Net.WebUtility]::HtmlDecode($_.Groups[1].Value).Trim() })
        $tipo = 'Outro'; $caminho = $null; $disp = $null
        if ($vals.Count -ge 3 -and $vals[0] -match '^\d+$' -and $vals[1] -match '^\d+$' -and $vals[2] -match '\.exe$') {
            $tipo = 'Timer'; $caminho = $vals[2]
        } elseif ($vals | Where-Object { $_ -match '^USB\\VID_' }) {
            $tipo = 'USB'; $disp = $vals | Where-Object { $_ -match '^USB\\VID_' } | Select-Object -First 1
        }
        [pscustomobject]@{
            Severidade = $m.Groups[1].Value; Titulo = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value).Trim()
            Tipo = $tipo; Caminho = $caminho; Dispositivo = $disp; Valores = $vals
        }
    }
}

# Processos que pedem timer de 1 ms (impedem a CPU de entrar em repouso profundo), ligados a serviço ou tarefa de logon
function Get-KAgentesTimer {
    $arq = Get-KUltimaAnaliseEnergia
    if (-not $arq) { return $null }
    $timers = @(Read-KAnaliseEnergia $arq.FullName | Where-Object Tipo -eq 'Timer' | Sort-Object Caminho -Unique |
                Where-Object { (Split-Path $_.Caminho -Leaf) -notin 'powershell.exe', 'pwsh.exe', 'dwm.exe', 'audiodg.exe', 'svchost.exe' })
    $exes = @($timers | ForEach-Object { Split-Path $_.Caminho -Leaf } | Sort-Object -Unique)
    $servicos = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    $tarefas  = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }
    $agentes = foreach ($exe in $exes) {
        $nomeBase = [IO.Path]::GetFileNameWithoutExtension($exe)
        $svc = @($servicos | Where-Object { $_.PathName -match [regex]::Escape($exe) })
        $tsk = @($tarefas | Where-Object { ($_.Actions.Execute -join ' ') -match [regex]::Escape($nomeBase) })
        $caminho = if ($svc) { ($svc[0].PathName -replace '^"([^"]+)".*$', '$1' -replace '^(\S+\.exe).*$', '$1') }
        if (-not $caminho) { $caminho = (Get-Process -Name $nomeBase -ErrorAction SilentlyContinue | Select-Object -First 1).Path }
        $empresa = if ($caminho -and (Test-Path $caminho)) { (Get-Item $caminho).VersionInfo.CompanyName }
        [pscustomobject]@{
            Exe = $exe; Empresa = $empresa; Auxiliar = $false
            CaminhoAnalise = ($timers | Where-Object { (Split-Path $_.Caminho -Leaf) -eq $exe } | Select-Object -First 1).Caminho
            Servicos = @($svc | ForEach-Object { [pscustomobject]@{ Nome = $_.Name; Exibicao = $_.DisplayName; StartMode = $_.StartMode } })
            Tarefas  = @($tsk | ForEach-Object { [pscustomobject]@{ Caminho = $_.TaskPath; Nome = $_.TaskName; Estado = "$($_.State)" } })
            Corrigivel = [bool]($svc -or $tsk) -and ($empresa -notmatch 'Microsoft')
        }
    }
    # Auxiliares de usuário (ex.: AcerQAAgent\AQAUserPS.exe) são abertos pelo serviço: vão junto com ele
    $bases = @($agentes | Where-Object Corrigivel | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Exe) })
    foreach ($a in $agentes | Where-Object { -not $_.Corrigivel }) {
        if ($bases | Where-Object { $a.CaminhoAnalise -match "\\$([regex]::Escape($_))\\" }) { $a.Auxiliar = $true }
    }
    [pscustomobject]@{ Arquivo = $arq.FullName; Data = $arq.LastWriteTime; Agentes = @($agentes) }
}

# ── Diagnóstico ────────────────────────────────────────────────
function Get-KDiagBateriaEnergia {
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $bat) {
        return New-KAchado 'Bateria' 'Bateria' Info 'Nenhuma bateria encontrada (desktop?)'
    }
    $achados = New-Object System.Collections.Generic.List[object]
    $add = { param($a) if ($a) { $achados.Add($a) } }
    $naTomada = $bat.BatteryStatus -ne 1

    # Relatório do Windows
    $xml = Get-KRelatorioBateriaXml
    $ns = $null
    if ($xml) {
        $ns = New-Object Xml.XmlNamespaceManager $xml.NameTable
        $ns.AddNamespace('b', 'http://schemas.microsoft.com/battery/2012')
        $b = $xml.BatteryReport.Batteries.Battery | Select-Object -First 1

        # 1. Saúde
        $design = [double]$b.DesignCapacity; $full = [double]$b.FullChargeCapacity
        if ($design -gt 0) {
            $saude = [math]::Round($full / $design * 100)
            $st = if ($saude -lt 60) { 'Critico' } elseif ($saude -lt 80) { 'Atencao' } else { 'OK' }
            $rec = if ($st -ne 'OK') { 'A bateria perdeu capacidade de verdade; só a troca recupera autonomia.' }
            & $add (New-KAchado 'Bateria' 'Saúde' $st ("{0}% da capacidade original ({1:N1} de {2:N1} Wh) | {3} ciclos" -f $saude, ($full / 1000), ($design / 1000), $b.CycleCount) $rec)
        }

        # 2. Limite de carga: Acer = estado real na BIOS; outros = deduz pelo histórico (fica parada em ~60/80% na tomada)
        $acer = Get-KLimiteCarga
        if ($acer -and $acer.TemLimite) {
            $det = "Limite de 80%: $(if ($acer.LimiteAtivo) { 'ligado' } else { 'desligado' })$(if ($acer.Calibrando) { ' | calibração em andamento' })"
            & $add (New-KAchado 'Bateria' 'Limite de carga (Acer)' Info $det $(if ($acer.LimiteAtivo) { 'Liga/desliga na aba Bateria do K-Bench (sem app da Acer). Com ele sempre ligado o medidor da % se perde: faça uma calibração por mês ou carregue até 100% de vez em quando.' }))
        }
        $usos = @($xml.BatteryReport.RecentUsage.UsageEntry)
        $pctAc = @($usos | Where-Object { $_.Ac -eq '1' -and [double]$_.FullChargeCapacity -gt 0 } |
                   ForEach-Object { [math]::Round([double]$_.ChargeCapacity / [double]$_.FullChargeCapacity * 100) })
        if ($pctAc.Count -ge 5) {
            $max = ($pctAc | Measure-Object -Maximum).Maximum
            $noTeto = @($pctAc | Where-Object { $_ -ge $max - 1 }).Count
            if ($max -le 85 -and $noTeto -ge 3 -and -not ($acer -and $acer.TemLimite)) {
                & $add (New-KAchado 'Bateria' 'Limite de carga' Info "Ativo: na tomada a carga para em ~$max%" `
                    "Protege a bateria (bom pra quem usa mais na tomada), mas a autonomia útil cai ~$(100 - $max)%. Se precisar de carga total, desative no app do fabricante (ex.: NitroSense/Acer Care Center, Lenovo Vantage) antes de sair.")
            }
        }

        # 3. Consumo real na bateria (W) a partir das descargas registradas
        $watts = New-Object System.Collections.Generic.List[double]
        $wattsDepois = New-Object System.Collections.Generic.List[double]
        $marco = Get-KMarcoCorrecoes
        foreach ($d in @($xml.BatteryReport.EnergyDrains.Drain)) {
            $ini = [datetime]$d.StartTimestamp
            $h = ([datetime]$d.EndTimestamp - $ini).TotalHours
            $e = [double]$d.StartChargeCapacity - [double]$d.EndChargeCapacity
            if ($h -lt (10 / 60) -or $h -gt 12 -or $e -le 0) { continue }
            $w = $e / 1000 / $h
            if ($w -lt 2) { continue }   # abaixo de 2 W não é uso real (hibernado/desligado contado como "ativo")
            $watts.Add($w)
            if ($marco -and $ini -ge $marco) { $wattsDepois.Add($w) }
        }
        # Antes x depois das correções do K-Bench
        if ($marco) {
            $wattsAntes = @($watts | Select-Object -First ($watts.Count - $wattsDepois.Count))
            if ($wattsDepois.Count -ge 2) {
                $mD = Get-KMediana $wattsDepois.ToArray()
                $mA = if ($wattsAntes.Count) { Get-KMediana $wattsAntes } else { 0 }
                $dif = if ($mA -gt 0) { [math]::Round(($mD - $mA) / $mA * 100) } else { $null }
                $st = if ($mD -gt 11) { 'Atencao' } else { 'OK' }
                & $add (New-KAchado 'Energia' 'Consumo depois das correções' $st ("{0:N1} W em {1} descargas desde {2:dd/MM}{3}" -f $mD, $wattsDepois.Count, $marco, $(if ($null -ne $dif) { " (antes: {0:N1} W, {1}{2}%)" -f $mA, $(if ($dif -gt 0) { '+' }), $dif })))
            } else {
                & $add (New-KAchado 'Energia' 'Consumo depois das correções' Info ("Correções aplicadas em {0:dd/MM HH:mm}; ainda há {1} descarga(s) na bateria depois disso" -f $marco, $wattsDepois.Count) 'Use alguns dias na bateria (30 min ou mais de cada vez) e rode o diagnóstico de novo pra comparar.')
            }
        }
        if ($watts.Count -ge 2) {
            $med = Get-KMediana $watts.ToArray()
            $min = ($watts | Measure-Object -Minimum).Minimum; $max = ($watts | Measure-Object -Maximum).Maximum
            $autonomia = if ($med -gt 0) { [math]::Round($full / 1000 / $med, 1) }
            $st = if ($med -gt 18) { 'Critico' } elseif ($med -gt 11) { 'Atencao' } else { 'OK' }
            $det = "Mediana {0:N1} W (mín {1:N1} W, máx {2:N1} W) em {3} descargas → ~{4} h com carga total" -f $med, $min, $max, $watts.Count, $autonomia
            $rec = @()
            if ($st -ne 'OK') { $rec += 'Consumo alto pra uso leve (o normal pra notebook Intel H em repouso é ~6-10 W). Aplique as correções de turbo/modo de energia e veja os processos e a GPU abaixo.' }
            if ($max -gt 2.5 * $min) { $rec += 'O consumo varia muito entre usos: é isso que faz a estimativa de tempo "ficar louca".' }
            & $add (New-KAchado 'Energia' 'Consumo na bateria' $st $det ($rec -join ' '))
        }

        # 4. Perda durante a suspensão (na bateria)
        $susp = @($usos | Where-Object { $_.EntryType -eq 'Suspend' -and $_.Ac -eq '0' -and [double]$_.Duration -ge 36000000000 })  # >= 1h
        if ($susp.Count) {
            $taxas = $susp | ForEach-Object {
                $h = [double]$_.Duration / 36000000000
                [double]$_.Discharge / [double]$_.FullChargeCapacity * 100 / $h
            }
            $taxa = [math]::Round((Get-KMediana @($taxas)), 2)
            $cs = $xml.BatteryReport.SystemInformation.ConnectedStandby -eq '1'
            $lim = if ($cs) { 2 } else { 1.2 }
            $st = if ($taxa -gt $lim * 2) { 'Critico' } elseif ($taxa -gt $lim) { 'Atencao' } else { 'OK' }
            $rec = if ($st -ne 'OK') { 'Perda alta dormindo. Ative "hibernar depois de" na bateria e impeça a rede/USB de acordar o PC.' }
            & $add (New-KAchado 'Suspensão' 'Perda dormindo (bateria)' $st ("{0}%/h em {1} suspensões ({2})" -f $taxa, $susp.Count, $(if ($cs) { 'Modern Standby' } else { 'S3 clássico' })) $rec)
        }
    } else {
        & $add (New-KAchado 'Bateria' 'Relatório do Windows' Info 'powercfg /batteryreport falhou')
    }

    # 5. Desligamentos/suspensões que não terminaram (Kernel-Power 41 com o estado que estava em andamento)
    $estados = @{ '0' = 'em uso'; '4' = 'suspensão (S3)'; '5' = 'hibernação'; '6' = 'desligamento' }
    $kp = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue |
            ForEach-Object {
                $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
                [pscustomobject]@{ Data = $_.TimeCreated; Sleep = "$($d.SleepInProgress)"; Bug = "$($d.BugcheckCode)"; Botao = "$($d.PowerButtonTimestamp)" }
            })
    $fastStartup = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled -eq 1
    $marcoFs = Get-KMarcoCorrecoes -Id FastStartup
    $kpDepois = if ($marcoFs) { @($kp | Where-Object Data -gt $marcoFs) } else { $null }
    if ($marcoFs -and $kp.Count -and -not $kpDepois.Count) {
        $ultimo = ($kp | Sort-Object Data -Descending | Select-Object -First 1).Data
        & $add (New-KAchado 'Suspensão' 'Desligamentos incompletos' OK ("Nenhum desde a correção ({0:dd/MM}). Antes: {1} em 30 dias, o último em {2:dd/MM HH:mm}" -f $marcoFs, $kp.Count, $ultimo))
    } elseif ($kp.Count) {
        $grupos = $kp | Group-Object Sleep | ForEach-Object { "$($_.Count)x durante $(if ($estados[$_.Name]) { $estados[$_.Name] } else { "estado $($_.Name)" })" }
        $noDeslig = @($kp | Where-Object Sleep -eq '6').Count
        $noSono   = @($kp | Where-Object { $_.Sleep -in '4', '5' }).Count
        $rec = @()
        if ($noDeslig) { $rec += "O desligamento não está terminando$(if ($fastStartup) { ' (Inicialização Rápida ativa: o "desligar" na verdade hiberna o sistema)' }). O PC pode ficar ligado de tela apagada, esquentando e gastando bateria. Desative a Inicialização Rápida." }
        if ($noSono)   { $rec += 'Falha ao entrar/voltar da suspensão: geralmente driver de vídeo, chipset ou BIOS. Atualize-os.' }
        & $add (New-KAchado 'Suspensão' 'Desligamentos incompletos' Critico "$($kp.Count) em 30 dias: $($grupos -join ', ')" ($rec -join ' '))
    } else {
        & $add (New-KAchado 'Suspensão' 'Desligamentos incompletos' OK 'Nenhum em 30 dias')
    }
    if ($fastStartup) {
        & $add (New-KAchado 'Suspensão' 'Inicialização Rápida' $(if ($kp.Count) { 'Atencao' } else { 'Info' }) 'Ativa' `
            'Em notebook costuma causar desligamento incompleto, drivers em estado ruim após "desligar" e gasto escondido. Desative se houver problemas.')
    }

    # 6. Plano de energia na bateria
    $tampa = Get-KPowerSetting sub_buttons LIDACTION
    if ($tampa) {
        $acoes = @{ 0 = 'não faz nada'; 1 = 'suspende'; 2 = 'hiberna'; 3 = 'desliga' }
        $st = if ($tampa.DC -eq 0) { 'Critico' } else { 'OK' }
        $rec = if ($st -ne 'OK') { 'Fechar a tampa na bateria não faz nada: o notebook fica ligado na mochila, esquenta e descarrega.' }
        if ($st -ne 'OK' -and (Get-KCorrecoesIgnoradas) -contains 'Tampa') {
            $s15 = Get-KPowerSetting sub_sleep STANDBYIDLE
            $st = if ($s15 -and $s15.DC -gt 0) { 'Info' } else { 'Atencao' }
            $rec = if ($st -eq 'Info') { "Escolha sua. Com a tampa fechada e o PC parado, ele suspende sozinho em $([math]::Round($s15.DC / 60)) min na bateria." } else { 'Escolha sua, mas a suspensão automática na bateria está desligada: com a tampa fechada ele não dorme nunca. Ative "Suspender após 15 min".' }
        }
        & $add (New-KAchado 'Plano de energia' 'Fechar a tampa' $st "Na bateria: $($acoes[[int]$tampa.DC]) | Na tomada: $($acoes[[int]$tampa.AC])" $rec)
    }
    $boost = Get-KPowerSetting sub_processor PERFBOOSTMODE
    if ($boost) {
        $nomes = @{ 0 = 'desativado'; 1 = 'ativado'; 2 = 'agressivo'; 3 = 'eficiente'; 4 = 'eficiente agressivo'; 5 = 'agressivo garantido'; 6 = 'eficiente agressivo garantido' }
        $st = if ($boost.DC -in 1, 2, 5, 6) { 'Atencao' } else { 'OK' }
        $rec = if ($st -ne 'OK') { 'Turbo agressivo na bateria faz o processador disparar de frequência à toa: esquenta e drena. Na bateria, turbo desligado rende muito mais autonomia.' }
        & $add (New-KAchado 'Plano de energia' 'Turbo do processador' $st "Na bateria: $($nomes[[int]$boost.DC]) | Na tomada: $($nomes[[int]$boost.AC])" $rec)
    }
    $epp = Get-KPowerSetting sub_processor PERFEPP
    if ($epp) {
        $st = if ($epp.DC -lt 60) { 'Atencao' } else { 'OK' }
        $rec = if ($st -ne 'OK') { 'Preferência do processador puxada pra desempenho na bateria. Pra economia, use 70 ou mais.' }
        & $add (New-KAchado 'Plano de energia' 'Preferência de energia (EPP)' $st "Na bateria: $($epp.DC) | Na tomada: $($epp.AC)  (0 = desempenho, 100 = economia)" $rec)
    }
    $ov = Get-KOverlayEnergia
    $st = if ($ov.DC -eq (Get-KGuidEficiencia)) { 'OK' } else { 'Atencao' }
    $rec = if ($st -ne 'OK') { 'Na bateria, o modo "Melhor eficiência energética" (Configurações > Energia) reduz o consumo sem você precisar lembrar.' }
    & $add (New-KAchado 'Plano de energia' 'Modo de energia' $st "Na bateria: $(Get-KNomeOverlay $ov.DC) | Na tomada: $(Get-KNomeOverlay $ov.AC)" $rec)

    $susp = Get-KPowerSetting sub_sleep STANDBYIDLE
    $hib  = Get-KPowerSetting sub_sleep HIBERNATEIDLE
    $hibOn = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled -eq 1
    if ($susp -and $hib) {
        $fmt = { param($s) if ($s -eq 0) { 'nunca' } else { "$([math]::Round($s / 60)) min" } }
        $st = if ($susp.DC -eq 0 -or -not $hibOn -or $hib.DC -eq 0) { 'Atencao' } else { 'OK' }
        $rec = if ($st -ne 'OK') { 'Na bateria, suspender após ~15-30 min e hibernar após ~1-2 h evita chegar com a bateria zerada.' }
        & $add (New-KAchado 'Plano de energia' 'Suspender / hibernar (bateria)' $st "Suspender: $(& $fmt $susp.DC) | Hibernar: $(if ($hibOn) { & $fmt $hib.DC } else { 'hibernação desativada' })" $rec)
    }
    $tela = Get-KPowerSetting sub_video VIDEOIDLE
    if ($tela -and ($tela.DC -eq 0 -or $tela.DC -gt 600)) {
        & $add (New-KAchado 'Plano de energia' 'Tela apaga (bateria)' Atencao "Na bateria: $(if ($tela.DC -eq 0) { 'nunca' } else { "$([math]::Round($tela.DC / 60)) min" })" `
            'A tela é o maior consumo depois do processador. Na bateria, 5 min parado já é suficiente.')
    }
    $wake = Get-KPowerSetting sub_sleep RTCWAKE
    if ($wake -and $wake.DC -ne 0) {
        & $add (New-KAchado 'Plano de energia' 'Timers de ativação' Atencao 'Permitidos na bateria' 'Tarefas (Windows Update, manutenção) podem acordar o notebook na mochila. Desative na bateria.')
    }

    # 7. Quem acorda o PC
    $armados = @(powercfg.exe /devicequery wake_armed 2>$null | Where-Object { $_ -and $_ -notmatch '^\s*$|^NONE$|^NENHUM' })
    if ($armados) {
        $rede = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $armados -contains $_.InterfaceDescription }).InterfaceDescription
        $st = if ($rede) { 'Atencao' } else { 'Info' }
        $rec = if ($rede) { 'A placa de rede pode acordar o notebook sozinha (Wake-on-LAN). Raramente é necessário em notebook.' }
        & $add (New-KAchado 'Suspensão' 'Dispositivos que acordam o PC' $st ($armados -join ', ') $rec)
    }
    $wakes = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1; StartTime = (Get-Date).AddDays(-14) } -ErrorAction SilentlyContinue |
               ForEach-Object { $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }; $d.WakeSourceText } |
               Where-Object { $_ })
    if ($wakes) {
        & $add (New-KAchado 'Suspensão' 'Origens de ativação (14 dias)' Info (($wakes | Group-Object | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ', '))
    }

    # 8. GPU dedicada
    $gpu = Get-KGpuDedicada
    if ($gpu) {
        $procs = @(Get-KProcessosNaGpuDedicada | Sort-Object -Unique)
        $det = "$($gpu.Nome): $(if ($gpu.Acordada) { 'ACORDADA (D0)' } else { "dormindo ($($gpu.Estado))" })$(if ($procs) { " | processos usando: $($procs -join ', ')" })"
        $st = if ($gpu.Acordada -and -not $naTomada) { 'Critico' } elseif ($procs) { 'Atencao' } else { 'OK' }
        $rec = if ($procs) { 'Cada processo com a GPU dedicada aberta pode mantê-la acordada (+5 a 15 W). Feche-os na bateria ou configure-os pra usar a GPU integrada (Configurações > Sistema > Tela > Elementos gráficos).' }
        & $add (New-KAchado 'GPU' 'GPU dedicada' $st $det $rec)
    }
    $pref = Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -ErrorAction SilentlyContinue
    if ($pref) {
        $alto = @($pref.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and "$($_.Value)" -match 'GpuPreference=2' } | ForEach-Object { Split-Path $_.Name -Leaf })
        if ($alto) { & $add (New-KAchado 'GPU' 'Apps forçados na GPU dedicada' Info ($alto -join ', ') 'Normal pra jogos; se for app comum (navegador, Discord), volte pra "Deixar o Windows decidir".') }
    }

    # 9. Serviços que gastam à toa
    $gastoes = Get-KServicosGastoes | ForEach-Object {
        $s = Get-Service $_.Nome -ErrorAction SilentlyContinue
        if ($s -and "$($s.StartType)" -ne 'Disabled' -and ("$($s.StartType)" -ne $_.Alvo -or $s.Status -eq 'Running')) { "$($s.DisplayName) ($($_.Motivo))" }
    }
    if ($gastoes) { & $add (New-KAchado 'Processos' 'Serviços que gastam à toa' Atencao ($gastoes -join ' | ') 'Podem ficar em manual/desativados sem perder nada importante (correção disponível).') }

    # 9b. Quem impede a CPU de dormir (timer de 1 ms) e USB que não suspende, pela última Análise de 60 s
    $ag = Get-KAgentesTimer
    if (-not $ag) {
        & $add (New-KAchado 'Processos' 'Quem impede a CPU de dormir' Info 'Ainda não analisado' 'Rode a "Análise de 60 s" (de preferência na bateria e sem usar o PC) pra ver quais programas não deixam o processador repousar.')
    } else {
        $ruins = @($ag.Agentes | Where-Object Corrigivel | Where-Object { ($_.Servicos | Where-Object StartMode -eq 'Auto') -or ($_.Tarefas | Where-Object Estado -ne 'Disabled') })
        $outros = @($ag.Agentes | Where-Object { -not $_.Corrigivel -and -not $_.Auxiliar } | ForEach-Object Exe)
        if ($ruins) {
            & $add (New-KAchado 'Processos' 'Quem impede a CPU de dormir' Critico ("Pedem timer de 1 ms o tempo todo: {0} (análise de {1:dd/MM HH:mm})" -f ((@($ruins) + @($ag.Agentes | Where-Object Auxiliar) | ForEach-Object { $_.Exe }) -join ', '), $ag.Data) `
                'Com timer de 1 ms o processador acorda 1000x por segundo e não entra em repouso profundo: gasta e esquenta parado. A correção "Agentes que impedem a CPU de dormir" coloca esses serviços em manual (com desfazer).')
        } else {
            & $add (New-KAchado 'Processos' 'Quem impede a CPU de dormir' $(if ($outros) { 'Info' } else { 'OK' }) $(if ($outros) { "Sem agentes de fabricante; pedem timer: $($outros -join ', ') (análise de $($ag.Data.ToString('dd/MM HH:mm')))" } else { 'Ninguém segurando o timer na última análise' }) `
                $(if ($outros) { 'Navegador tocando vídeo/áudio e jogos pedem timer enquanto estão abertos; é normal.' }))
        }
        $usb = @(Read-KAnaliseEnergia $ag.Arquivo | Where-Object Tipo -eq 'USB' | ForEach-Object Dispositivo | Sort-Object -Unique)
        if ($usb) {
            $nomes = foreach ($u in $usb) {
                $id = ($u -split '\\')[0..1] -join '\'
                $dev = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object InstanceId -like "$id*" | Select-Object -First 1
                if ($dev) { "$($dev.FriendlyName) ($id)" } else { $id }
            }
            & $add (New-KAchado 'Energia' 'USB que não suspende' Atencao ($nomes -join ', ') `
                'Esse dispositivo impede o USB de economizar energia (comum em receptor de teclado/mouse sem fio). Na bateria, desconecte o receptor se não estiver usando.')
        }
    }

    # 10. Quem está usando CPU agora (amostra de 5 s)
    $a = @{}; Get-Process | ForEach-Object { $a[$_.Id] = $_.CPU }
    Start-Sleep -Seconds 5
    $nucleos = [Environment]::ProcessorCount
    $top = Get-Process | Where-Object { $a.ContainsKey($_.Id) -and $_.Name -ne 'Idle' } | ForEach-Object {
               [pscustomobject]@{ Nome = $_.Name; Pct = (($_.CPU - $a[$_.Id]) / 5 / $nucleos * 100) } } |
           Group-Object Nome | ForEach-Object { [pscustomobject]@{ Nome = $_.Name; Pct = ($_.Group | Measure-Object Pct -Sum).Sum } } |
           Sort-Object Pct -Descending | Where-Object Pct -ge 1 | Select-Object -First 6
    if ($top) {
        $tot = ($top | Measure-Object Pct -Sum).Sum
        $st = if ($tot -gt 15) { 'Atencao' } else { 'Info' }
        $rec = if ($st -ne 'OK') { 'CPU ocupada em repouso impede o processador de dormir. Feche ou desative o que não precisa.' }
        & $add (New-KAchado 'Processos' 'Usando CPU agora' $st (($top | ForEach-Object { '{0} {1:N1}%' -f $_.Nome, $_.Pct }) -join ', ') $(if ($st -eq 'Atencao') { $rec }))
    }

    & $add (New-KAchado 'Bateria' 'Fonte de energia' Info $(if ($naTomada) { "Na tomada ($($bat.EstimatedChargeRemaining)%). Pra medir consumo de verdade, analise de novo na bateria." } else { "Na bateria ($($bat.EstimatedChargeRemaining)%)" }))
    $achados.ToArray()   # um por um no pipeline; quem chama usa @(...)
}

# ── Correções ──────────────────────────────────────────────────
# Tipo 'power': ajustes do plano (só na bateria = DC). Valores anteriores ficam salvos pra desfazer.
function Get-KCorrecoesEnergia {
    @(
        [pscustomobject]@{ Id = 'Tampa'; Nome = 'Fechar a tampa suspende (bateria)'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_buttons'; Set = 'LIDACTION'; DC = 1 })
            Descricao = 'Na bateria, fechar a tampa coloca o notebook pra dormir. Na tomada continua como está (útil com monitor externo).' }
        [pscustomobject]@{ Id = 'FastStartup'; Nome = 'Desativar Inicialização Rápida'; Tipo = 'faststartup'; Ajustes = @()
            Descricao = 'O "Desligar" passa a desligar de verdade. Resolve desligamento incompleto, drivers em estado ruim e gasto escondido. O boot fica alguns segundos mais lento.' }
        [pscustomobject]@{ Id = 'Agentes'; Nome = 'Agentes que impedem a CPU de dormir'; Tipo = 'agentes'; Ajustes = @()
            Descricao = 'Serviços e tarefas de fabricante que pedem timer de 1 ms o tempo todo (vistos na Análise de 60 s). Ficam em manual/desativados. Se algum atalho ou recurso do app do fabricante parar, desligue esta correção.' }
        [pscustomobject]@{ Id = 'Turbo'; Nome = 'Turbo desligado na bateria'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_processor'; Set = 'PERFBOOSTMODE'; DC = 0 })
            Descricao = 'Maior ganho de autonomia e temperatura em notebook Intel/AMD de alto desempenho. Na tomada o turbo continua normal.' }
        [pscustomobject]@{ Id = 'Epp'; Nome = 'Processador priorizando economia (bateria)'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_processor'; Set = 'PERFEPP'; DC = 70 }, @{ Sub = 'sub_processor'; Set = 'PERFEPP1'; DC = 70 })
            Descricao = 'Preferência de energia (EPP) em 70 na bateria: o processador sobe de frequência só quando precisa.' }
        [pscustomobject]@{ Id = 'ModoEficiencia'; Nome = 'Modo "Melhor eficiência" na bateria'; Tipo = 'overlay'; Ajustes = @()
            Descricao = 'Ao tirar da tomada, o Windows entra sozinho no modo de energia mais econômico.' }
        [pscustomobject]@{ Id = 'Tela'; Nome = 'Tela apaga após 5 min parado (bateria)'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_video'; Set = 'VIDEOIDLE'; DC = 300 })
            Descricao = 'A tela é o que mais gasta depois do processador. Na tomada continua como está.' }
        [pscustomobject]@{ Id = 'Hibernar'; Nome = 'Hibernar após 1 h dormindo (bateria)'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_sleep'; Set = 'HIBERNATEIDLE'; DC = 3600 })
            Descricao = 'Se ficar suspenso na bateria por 1 h, hiberna (consumo zero). Evita chegar com bateria zerada. Ativa a hibernação se estiver desligada.' }
        [pscustomobject]@{ Id = 'Suspender'; Nome = 'Suspender após 15 min parado (bateria)'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_sleep'; Set = 'STANDBYIDLE'; DC = 900 })
            Descricao = 'Dorme sozinho se esquecido ligado na bateria.' }
        [pscustomobject]@{ Id = 'WakeTimers'; Nome = 'Sem timers de ativação na bateria'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_sleep'; Set = 'RTCWAKE'; DC = 0 })
            Descricao = 'Tarefas agendadas não acordam o notebook na mochila.' }
        [pscustomobject]@{ Id = 'Aspm'; Nome = 'Economia do PCIe e USB (bateria)'; Tipo = 'power'
            Ajustes = @(@{ Sub = 'sub_pciexpress'; Set = 'ASPM'; DC = 2 }, @{ Sub = '2a737441-1930-4402-8d77-b2bebba308a3'; Set = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; DC = 1 })
            Descricao = 'Link PCIe em economia máxima e suspensão seletiva de USB na bateria.' }
        [pscustomobject]@{ Id = 'WakeRede'; Nome = 'Rede não acorda o PC'; Tipo = 'wakerede'; Ajustes = @()
            Descricao = 'Impede que a placa de rede acorde o notebook (Wake-on-LAN).' }
        [pscustomobject]@{ Id = 'Servicos'; Nome = 'Serviços da Intel que gastam à toa'; Tipo = 'servicos'; Ajustes = @()
            Descricao = 'PresentMon (Intel) em manual; Energy Server (Intel SUR) desativado, porque ele religa sozinho em manual.' }
    )
}

function Get-KEstadoEnergia {
    $arq = Join-Path $KB.Raiz 'estado\energia.json'
    $h = @{}
    if (Test-Path $arq) {
        try {
            (Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
        } catch {}
    }
    $h
}

function Save-KEstadoEnergia([hashtable]$Estado) {
    $dir = Join-Path $KB.Raiz 'estado'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'energia.json'), ($Estado | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
}

# Correções que o técnico desligou de propósito: deixam de ser recomendadas (até ele ligar de novo)
function Get-KCorrecoesIgnoradas {
    $arq = Join-Path $KB.Raiz 'estado\energia-ignoradas.json'
    # ConvertFrom-Json no PS 5.1 devolve o array inteiro como um objeto só: o ForEach desmonta
    if (Test-Path $arq) { try { Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ } } catch {} }
}

function Set-KCorrecaoIgnorada {
    param([Parameter(Mandatory)][string]$Id, [bool]$Ignorar = $true)
    $lista = [Collections.Generic.List[string]]@(Get-KCorrecoesIgnoradas | Where-Object { $_ -ne $Id })
    if ($Ignorar) { $lista.Add($Id) }
    $dir = Join-Path $KB.Raiz 'estado'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'energia-ignoradas.json'), (ConvertTo-Json @($lista) -Compress), (New-Object Text.UTF8Encoding $false))
}

# Data da primeira correção aplicada (marco pra comparar antes/depois)
function Get-KMarcoCorrecoes {
    param([string]$Id)
    $e = Get-KEstadoEnergia
    $datas = foreach ($k in $e.Keys) { if (-not $Id -or $k -eq $Id) { try { [datetime]$e[$k].Data } catch {} } }
    $datas | Sort-Object | Select-Object -First 1
}

# A correção ainda é necessária? (olha o estado REAL do Windows, não só o que o K-Bench registrou)
function Test-KCorrecaoNecessaria {
    param([Parameter(Mandatory)]$Correcao)
    $c = $Correcao
    switch ($c.Tipo) {
        'power' {
            $p = $false
            foreach ($a in $c.Ajustes) {
                $v = Get-KPowerSetting $a.Sub $a.Set
                if (-not $v) { continue }
                $p = $p -or $(switch ($c.Id) {
                    'Hibernar'  { $v.DC -eq 0 -or $v.DC -gt 7200 }
                    'Suspender' { $v.DC -eq 0 -or $v.DC -gt 1800 }
                    'Tela'      { $v.DC -eq 0 -or $v.DC -gt 600 }
                    'Epp'       { $v.DC -lt 60 }
                    default     { $v.DC -ne $a.DC }
                })
            }
            if ($c.Id -eq 'Hibernar' -and (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled -ne 1) { $p = $true }
            $p
        }
        'faststartup' { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled -eq 1 }
        'overlay'     { (Get-KOverlayEnergia).DC -ne (Get-KGuidEficiencia) }
        'wakerede'    {
            $armados = @(powercfg.exe /devicequery wake_armed 2>$null)
            [bool](Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $armados -contains $_.InterfaceDescription })
        }
        'servicos'    {
            [bool](Get-KServicosGastoes | Where-Object {
                $s = Get-Service $_.Nome -ErrorAction SilentlyContinue
                $s -and "$($s.StartType)" -ne $_.Alvo -and -not ($_.Alvo -eq 'Manual' -and "$($s.StartType)" -eq 'Disabled')
            })
        }
        'agentes'     {
            $ag = Get-KAgentesTimer
            [bool]($ag -and ($ag.Agentes | Where-Object Corrigivel | Where-Object {
                ($_.Servicos | Where-Object StartMode -eq 'Auto') -or ($_.Tarefas | Where-Object Estado -ne 'Disabled')
            }))
        }
    }
}

# Situação de cada correção: precisa? já está? foi aplicada pelo K-Bench? pegou de verdade?
function Get-KSituacaoCorrecoes {
    $estado = Get-KEstadoEnergia
    $ignoradas = @(Get-KCorrecoesIgnoradas)
    $temBateria = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    foreach ($c in Get-KCorrecoesEnergia) {
        $precisa  = [bool](Test-KCorrecaoNecessaria $c)
        $aplicada = $estado.ContainsKey($c.Id)
        $situacao = if ($aplicada -and $precisa) { 'Não pegou' } elseif ($aplicada) { 'Aplicada pelo K-Bench' } elseif ($precisa) { 'Recomendada' } else { 'Já está OK' }
        if ($c.Id -eq 'Agentes' -and -not $aplicada -and -not $precisa -and -not (Get-KUltimaAnaliseEnergia)) { $situacao = 'Rode a Análise de 60 s' }
        if ($situacao -eq 'Recomendada' -and $ignoradas -contains $c.Id) { $situacao = 'Ignorada'; $precisa = $false }
        [pscustomobject]@{
            Id = $c.Id; Nome = $c.Nome; Descricao = $c.Descricao
            Recomendada = [bool]($precisa -and $temBateria)
            Aplicada = $aplicada
            Situacao = $situacao
        }
    }
}

function Invoke-KCorrecaoEnergia {
    param([Parameter(Mandatory)][string]$Id)
    $c = Get-KCorrecoesEnergia | Where-Object Id -eq $Id
    if (-not $c) { Write-KLog "Correção desconhecida: $Id" Erro; return }
    $estado = Get-KEstadoEnergia
    $reaplicar = $estado.ContainsKey($Id)
    if ($reaplicar -and -not (Test-KCorrecaoNecessaria $c)) { Write-KLog "$($c.Nome): já aplicada" Info; return }

    # Ao reaplicar, mantém o "antes" original (é ele que o desfazer precisa)
    $antes = @{ Data = (Get-Date).ToString('s') }
    try {
        switch ($c.Tipo) {
            'power' {
                $antes.Ajustes = @(foreach ($a in $c.Ajustes) {
                    $v = Get-KPowerSetting $a.Sub $a.Set
                    if ($v) { @{ Sub = $a.Sub; Set = $a.Set; DC = $v.DC } }
                })
                if ($Id -eq 'Hibernar') {
                    $antes.HibernateEnabled = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
                    if ($antes.HibernateEnabled -ne 1) { powercfg.exe /hibernate on | Out-Null }
                }
                foreach ($a in $c.Ajustes) { Set-KPowerSetting $a.Sub $a.Set -DC $a.DC }
            }
            'faststartup' {
                $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
                $antes.HiberbootEnabled = (Get-ItemProperty $k -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
                Set-ItemProperty $k -Name HiberbootEnabled -Value 0 -Type DWord
            }
            'overlay' {
                $antes.Overlay = (Get-KOverlayEnergia).DC
                Set-KOverlayEnergiaDC (Get-KGuidEficiencia)
                if ((Get-KOverlayEnergia).DC -ne (Get-KGuidEficiencia)) { throw 'o Windows não aceitou o modo de energia' }
            }
            'wakerede' {
                $armados = @(powercfg.exe /devicequery wake_armed 2>$null)
                $rede = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $armados -contains $_.InterfaceDescription }).InterfaceDescription
                foreach ($r in $rede) { powercfg.exe /devicedisablewake "$r" | Out-Null; Write-KLog "Wake desativado: $r" Detalhe }
                $antes.Dispositivos = $rede
            }
            'servicos' {
                $antes.Servicos = @(foreach ($s in Get-KServicosGastoes) {
                    $svc = Get-Service $s.Nome -ErrorAction SilentlyContinue
                    if (-not $svc -or "$($svc.StartType)" -eq $s.Alvo) { continue }
                    try {
                        Set-Service $s.Nome -StartupType $s.Alvo -ErrorAction Stop
                        Stop-Service $s.Nome -Force -ErrorAction SilentlyContinue
                        @{ Nome = $s.Nome; StartType = "$($svc.StartType)" }
                        Write-KLog "$($svc.DisplayName): $(if ($s.Alvo -eq 'Disabled') { 'desativado' } else { 'manual' })" Detalhe
                    } catch { Write-KLog "$($svc.DisplayName): não foi possível alterar ($($_.Exception.Message))" Aviso }
                })
            }
            'agentes' {
                $ag = Get-KAgentesTimer
                if (-not $ag) { throw 'rode a Análise de 60 s primeiro (é ela que mostra quem impede a CPU de dormir)' }
                $antes.Servicos = @(); $antes.Tarefas = @()
                foreach ($a in $ag.Agentes | Where-Object Corrigivel) {
                    foreach ($s in $a.Servicos | Where-Object StartMode -eq 'Auto') {
                        try {
                            Set-Service $s.Nome -StartupType Manual -ErrorAction Stop
                            Stop-Service $s.Nome -Force -ErrorAction SilentlyContinue
                            $antes.Servicos += @{ Nome = $s.Nome; StartType = 'Automatic' }
                            Write-KLog "$($s.Exibicao): manual" Detalhe
                        } catch { Write-KLog "$($s.Exibicao): não foi possível alterar ($($_.Exception.Message))" Aviso }
                    }
                    foreach ($t in $a.Tarefas | Where-Object Estado -ne 'Disabled') {
                        try {
                            Disable-ScheduledTask -TaskPath $t.Caminho -TaskName $t.Nome -ErrorAction Stop | Out-Null
                            $antes.Tarefas += @{ Caminho = $t.Caminho; Nome = $t.Nome }
                            Write-KLog "Tarefa desativada: $($t.Nome)" Detalhe
                        } catch { Write-KLog "Tarefa $($t.Nome): $($_.Exception.Message)" Aviso }
                    }
                }
                foreach ($a in $ag.Agentes | Where-Object { $_.Corrigivel -or $_.Auxiliar }) {
                    Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($a.Exe)) -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                }
                if ($reaplicar) {   # junta com o que já tinha sido desativado antes
                    $antes.Servicos = @($estado[$Id].Servicos) + $antes.Servicos
                    $antes.Tarefas  = @($estado[$Id].Tarefas) + $antes.Tarefas
                }
                if (-not ($antes.Servicos + $antes.Tarefas)) { throw 'nenhum serviço ou tarefa pra desativar' }
            }
        }
        if ($reaplicar -and $c.Tipo -ne 'agentes') { $antes = $estado[$Id] }
        $estado[$Id] = $antes
        Save-KEstadoEnergia $estado
        if ((Get-KCorrecoesIgnoradas) -contains $Id) { Set-KCorrecaoIgnorada $Id $false }
        Write-KLog "$($c.Nome): aplicada" OK
        if ($Id -eq 'FastStartup') { Write-KLog 'Vale a partir do próximo desligamento.' Detalhe }
    } catch {
        Write-KLog "$($c.Nome): falhou - $($_.Exception.Message)" Erro
    }
}

function Undo-KCorrecaoEnergia {
    param([Parameter(Mandatory)][string]$Id)
    $c = Get-KCorrecoesEnergia | Where-Object Id -eq $Id
    $estado = Get-KEstadoEnergia
    if (-not $estado.ContainsKey($Id)) { Write-KLog "$($c.Nome): não foi aplicada pelo K-Bench, nada a desfazer" Aviso; return }
    $antes = $estado[$Id]
    try {
        switch ($c.Tipo) {
            'power' {
                foreach ($a in @($antes.Ajustes)) { if ($a) { Set-KPowerSetting $a.Sub $a.Set -DC $a.DC } }
                if ($Id -eq 'Hibernar' -and $null -ne $antes.HibernateEnabled -and $antes.HibernateEnabled -ne 1) { powercfg.exe /hibernate off | Out-Null }
            }
            'faststartup' {
                $v = if ($null -ne $antes.HiberbootEnabled) { $antes.HiberbootEnabled } else { 1 }
                Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value $v -Type DWord
            }
            'overlay'  { Set-KOverlayEnergiaDC "$($antes.Overlay)" }
            'wakerede' { foreach ($r in @($antes.Dispositivos)) { if ($r) { powercfg.exe /deviceenablewake "$r" | Out-Null } } }
            { $_ -in 'servicos', 'agentes' } {
                foreach ($s in @($antes.Servicos)) {
                    if (-not $s) { continue }
                    Set-Service $s.Nome -StartupType $s.StartType -ErrorAction SilentlyContinue
                    Start-Service $s.Nome -ErrorAction SilentlyContinue
                }
                foreach ($t in @($antes.Tarefas)) {
                    if ($t) { Enable-ScheduledTask -TaskPath $t.Caminho -TaskName $t.Nome -ErrorAction SilentlyContinue | Out-Null }
                }
            }
        }
        $estado.Remove($Id)
        Save-KEstadoEnergia $estado
        Write-KLog "$($c.Nome): desfeita" OK
    } catch {
        Write-KLog "$($c.Nome): falhou ao desfazer - $($_.Exception.Message)" Erro
    }
}

# ── Ferramentas ────────────────────────────────────────────────
function Invoke-KAnaliseEnergia {
    param([int]$Segundos = 60)
    Write-KLog "Análise de eficiência energética ($Segundos s)" Titulo
    Write-KLog 'Deixe o notebook parado, de preferência na bateria e com os apps de sempre abertos.' Detalhe
    New-Item -ItemType Directory -Path $KB.LogDir -Force | Out-Null
    $arq = Join-Path $KB.LogDir ("$($env:COMPUTERNAME)_energia_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    $r = Invoke-KNativo powercfg.exe '/energy', '/output', "`"$arq`"", '/duration', $Segundos -SemLog
    if (Test-Path $arq) { Write-KLog "Relatório: $arq" OK; $arq }
    else { Write-KLog "powercfg /energy falhou (código $($r.Codigo))" Erro }
}

function Export-KRelatorioBateriaWindows {
    New-Item -ItemType Directory -Path $KB.LogDir -Force | Out-Null
    $arq = Join-Path $KB.LogDir ("$($env:COMPUTERNAME)_bateria_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    powercfg.exe /batteryreport /output "$arq" 2>$null | Out-Null
    if (Test-Path $arq) { $arq }
}

function Get-KDiagnosticoBateria {
    Write-KLog 'Bateria e energia' Titulo
    Write-KProgresso 'Bateria' 'Analisando (leva ~10 s)'
    $achados = @(Get-KDiagBateriaEnergia)
    $ordem = @{ Critico = 0; Atencao = 1; Info = 2; OK = 3 }
    foreach ($a in $achados | Sort-Object { $ordem[$_.Status] }) {
        $nivel = @{ Critico = 'Erro'; Atencao = 'Aviso'; Info = 'Info'; OK = 'OK' }[$a.Status]
        Write-KLog "$($a.Item): $($a.Detalhe)" $nivel
        if ($a.Recomendacao) { Write-KLog "→ $($a.Recomendacao)" Detalhe }
    }
    , $achados
}
