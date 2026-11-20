# ============================================================
#  Diagnóstico: explica POR QUE o PC está lento/instável
#  Cada verificação devolve "achados" com status e recomendação.
#  Status: OK | Info | Atencao | Critico
# ============================================================

function New-KAchado {
    param(
        [string]$Categoria, [string]$Item,
        [ValidateSet('OK','Info','Atencao','Critico')][string]$Status = 'Info',
        [string]$Detalhe = '', [string]$Recomendacao = ''
    )
    [pscustomobject]@{
        Status = $Status; Categoria = $Categoria; Item = $Item
        Detalhe = $Detalhe; Recomendacao = $Recomendacao
    }
}

# Padrões de programas que costumam pesar ou vir "de brinde" (nome exibido em Programas e Recursos)
function Get-KBloatPadroes { @(
    'McAfee', 'Norton', 'Avast', 'AVG ', 'Avira', 'Segurazo', 'ByteFence', 'Total ?AV', 'PC Matic',
    'WildTangent', 'Booking\.com', 'ExpressVPN', 'Dropbox Promotion', 'Amazon Alexa',
    'Driver ?Booster', 'DriverPack', 'Driver Easy', 'DriverMax', 'Driver Genius', 'Snappy Driver',
    'CCleaner', 'Advanced SystemCare', 'IObit', 'Wise Care', 'Glary', 'Auslogics', 'Restoro', 'Reimage', 'Fortect', 'Outbyte',
    'Wave Browser', 'OneLaunch', 'Web ?Companion', 'Shift Browser', 'Baidu', '360 Total', 'Opera GX',
    'PC App Store', 'WebDiscover', 'Yandex', 'Ask Toolbar'
) }

function Get-KProgramasInstalados {
    $chaves = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $chaves -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName } |
        Select-Object DisplayName, DisplayVersion, Publisher -Unique
}

# ── Verificações ───────────────────────────────────────────────
function Get-KDiagSistema {
    $cs  = Get-CimInstance Win32_ComputerSystem
    $bio = Get-CimInstance Win32_BIOS
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $win = Get-KWindows
    New-KAchado 'Sistema' 'Máquina' Info "$($cs.Manufacturer) $($cs.Model) | Série: $($bio.SerialNumber)"
    New-KAchado 'Sistema' 'Processador' Info ($cpu.Name.Trim())
    if ($win.Win11) {
        New-KAchado 'Sistema' 'Windows' OK "$($win.Nome) $($win.Versao) $($win.Edicao) (build $($win.Build).$($win.UBR))"
    } else {
        New-KAchado 'Sistema' 'Windows' Atencao "$($win.Nome) $($win.Versao) (build $($win.Build))" `
            'Windows 10 está sem suporte desde out/2025. Atualizar pro 11 se o hardware permitir.'
    }
}

function Get-KDiagMemoria {
    $os    = Get-CimInstance Win32_OperatingSystem
    $totGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $usoPc = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100)
    $commit = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue).PercentCommittedBytesInUse

    $status = if ($totGB -le 4.5) { 'Critico' } elseif ($totGB -le 8.5) { 'Atencao' } else { 'OK' }
    $rec    = switch ($status) {
        'Critico' { 'Pouca RAM pro Windows 11. Upgrade pra 8 GB (ideal 16 GB) é o que mais vai ajudar.' }
        'Atencao' { '8 GB é o mínimo confortável. Com navegador + Office, 16 GB faz diferença.' }
    }
    New-KAchado 'Desempenho' 'Memória RAM' $status "$totGB GB instalados | $usoPc% em uso agora" $rec

    if ($commit -ge 85) {
        New-KAchado 'Desempenho' 'Pressão de memória' Atencao "$commit% da memória comprometida (RAM + paginação)" `
            'O PC está usando o disco como memória. Feche programas na inicialização ou aumente a RAM.'
    }
}

function Get-KDiagDiscoSistema {
    $letra = $env:SystemDrive.TrimEnd(':')
    $num   = (Get-Partition -DriveLetter $letra | Get-Disk).Number
    $pd    = Get-PhysicalDisk | Where-Object DeviceId -eq "$num" | Select-Object -First 1
    $tipo  = if ($pd.MediaType -eq 'HDD') { 'HDD' }
             elseif ($pd.MediaType -eq 'SSD' -or $pd.BusType -eq 'NVMe') { 'SSD' }
             else { "$($pd.MediaType)" }
    $desc  = "$($pd.FriendlyName) | $tipo | $($pd.BusType) | $([math]::Round($pd.Size / 1GB)) GB"
    if ($tipo -eq 'HDD') {
        New-KAchado 'Desempenho' 'Disco do sistema' Critico $desc `
            'Windows em HD mecânico é a causa nº 1 de lentidão. Trocar por SSD resolve mais que qualquer limpeza.'
    } else {
        New-KAchado 'Desempenho' 'Disco do sistema' OK $desc
    }
}

function Get-KDiagEspaco {
    Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.Size -gt 0 } |
        Sort-Object DriveLetter | ForEach-Object {
            $livre = [math]::Round($_.SizeRemaining / 1GB, 1)
            $pct   = [math]::Round($_.SizeRemaining / $_.Size * 100)
            $st    = if ($pct -lt 10 -or $livre -lt 10) { 'Critico' } elseif ($pct -lt 15) { 'Atencao' } else { 'OK' }
            $rec   = if ($st -ne 'OK') { 'Pouco espaço deixa o Windows lento e quebra atualizações. Rode a manutenção e revise Downloads/arquivos grandes.' }
            New-KAchado 'Armazenamento' "Espaço em $($_.DriveLetter):" $st "$livre GB livres de $([math]::Round($_.Size / 1GB, 1)) GB ($pct%)" $rec
        }
}

function Get-KDiagUptime {
    $boot  = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $dias  = [math]::Round(((Get-Date) - $boot).TotalDays, 1)
    $fast  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled -eq 1
    $det   = "Ligado há $dias dia(s) (desde $($boot.ToString('dd/MM HH:mm')))$(if ($fast) { ' | Inicialização Rápida ATIVA' })"
    if ($dias -gt 7) {
        $rec = 'Reinicie (Reiniciar, não Desligar).' + $(if ($fast) { ' Com Inicialização Rápida, "Desligar" não zera o sistema; considere desativá-la.' })
        New-KAchado 'Desempenho' 'Tempo ligado' Atencao $det $rec
    } else {
        New-KAchado 'Desempenho' 'Tempo ligado' OK $det
    }
}

function Get-KDiagEnergia {
    $saida = (powercfg.exe /getactivescheme) -join ' '
    $guid  = if ($saida -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $Matches[1] }
    $nome  = if ($saida -match '\((.+)\)') { $Matches[1] } else { $guid }
    $notebook = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') {
        New-KAchado 'Desempenho' 'Plano de energia' Atencao "Economia de energia ($nome)" `
            'O processador fica limitado. Use Equilibrado (ou Alto desempenho em desktop).'
    } else {
        New-KAchado 'Desempenho' 'Plano de energia' OK "$nome$(if ($notebook) { ' | notebook' })"
    }
}

function Get-KDiagInicializacao {
    $itens = New-Object System.Collections.Generic.List[string]
    # Registro: Run (HKLM, WOW64, HKCU) respeitando o que foi desativado no Gerenciador de Tarefas
    $fontes = @(
        @{ Run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Aprov = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        @{ Run = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprov = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
        @{ Run = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Aprov = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    )
    foreach ($f in $fontes) {
        $run = Get-ItemProperty $f.Run -ErrorAction SilentlyContinue
        if (-not $run) { continue }
        $aprov = Get-ItemProperty $f.Aprov -ErrorAction SilentlyContinue
        foreach ($p in $run.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            $bin = if ($aprov) { $aprov.($p.Name) }
            if ($bin -is [byte[]] -and ($bin[0] % 2) -eq 1) { continue }   # ímpar = desativado
            if ($p.Name -in 'SecurityHealth') { continue }                  # componente do próprio Windows
            $itens.Add($p.Name)
        }
    }
    # Pastas Inicializar (comum + usuário atual)
    foreach ($pasta in "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
                       "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup") {
        Get-ChildItem $pasta -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' |
            ForEach-Object { $itens.Add($_.BaseName) }
    }
    $n = $itens.Count
    $st = if ($n -gt 12) { 'Critico' } elseif ($n -gt 7) { 'Atencao' } else { 'OK' }
    $rec = if ($st -ne 'OK') { 'Muitos programas abrindo junto com o Windows. Desative os desnecessários (Gerenciador de Tarefas > Aplicativos de inicialização).' }
    $lista = ($itens | Select-Object -First 12) -join ', '
    if ($n -gt 12) { $lista += " e mais $($n - 12)" }
    New-KAchado 'Inicialização' 'Programas na inicialização' $st "$n ativo(s): $lista" $rec

    # Tarefas agendadas de terceiros que rodam no logon/boot
    $tarefas = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' -and
        ($_.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' })
    }
    if ($tarefas) {
        New-KAchado 'Inicialização' 'Tarefas agendadas (logon/boot)' Info "$(@($tarefas).Count): $(($tarefas.TaskName | Select-Object -First 15) -join ', ')"
    }

    # Serviços de terceiros em automático
    $svc = Get-CimInstance Win32_Service -Filter "StartMode='Auto'" |
           Where-Object { $_.PathName -and $_.PathName -notmatch '\\Windows\\|Windows Defender|Microsoft' }
    if ($svc) {
        New-KAchado 'Inicialização' 'Serviços de terceiros (automático)' Info "$(@($svc).Count): $(($svc.DisplayName | Select-Object -First 15) -join ', ')"
    }
}

function Get-KDiagSeguranca {
    $avs = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    $terceiros = @($avs | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' })
    if ($terceiros.Count -gt 1) {
        New-KAchado 'Segurança' 'Antivírus' Critico "Mais de um antivírus: $($terceiros.displayName -join ', ')" `
            'Dois antivírus brigam entre si e deixam tudo lento. Mantenha só um (o Defender já é suficiente).'
    } elseif ($terceiros.Count -eq 1) {
        $nome = $terceiros[0].displayName
        $st   = if ($nome -match 'McAfee|Norton|Avast|AVG|Segurazo|Total ?AV') { 'Atencao' } else { 'Info' }
        $rec  = if ($st -eq 'Atencao') { 'Geralmente vem de fábrica em versão de teste e pesa bastante. Se o cliente não paga, desinstale e deixe o Defender.' }
        New-KAchado 'Segurança' 'Antivírus' $st "$nome (terceiro)" $rec
    }

    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.AMRunningMode -eq 'Normal') {
            $idade = $mp.AntivirusSignatureAge
            if (-not $mp.RealTimeProtectionEnabled) {
                New-KAchado 'Segurança' 'Microsoft Defender' Critico 'Proteção em tempo real DESATIVADA' 'Reative a proteção em tempo real.'
            } elseif ($idade -gt 7) {
                New-KAchado 'Segurança' 'Microsoft Defender' Atencao "Assinaturas com $idade dias" 'Atualize o Windows/Defender.'
            } else {
                New-KAchado 'Segurança' 'Microsoft Defender' OK "Ativo, assinaturas de $idade dia(s)"
            }
        }
    } catch {}
}

function Get-KDiagBloatware {
    $regex = '(' + ((Get-KBloatPadroes) -join '|') + ')'
    $achados = @(Get-KProgramasInstalados | Where-Object { $_.DisplayName -match $regex })
    if ($achados) {
        New-KAchado 'Programas' 'Bloatware / otimizadores' Atencao ($achados.DisplayName -join ', ') `
            'Programas de teste, "otimizadores" e atualizadores de driver de terceiros pesam e às vezes causam problemas. Avalie desinstalar.'
    } else {
        New-KAchado 'Programas' 'Bloatware / otimizadores' OK 'Nenhum conhecido encontrado'
    }
}

# ── SMART (smartctl) ───────────────────────────────────────────
function Find-KSmartctl {
    $candidatos = @(
        (Join-Path $KB.Raiz 'tools\smartctl.exe'),
        "$env:ProgramFiles\smartmontools\bin\smartctl.exe",
        "${env:ProgramFiles(x86)}\smartmontools\bin\smartctl.exe"
    )
    $c = $candidatos | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $c) { $c = (Get-Command smartctl.exe -ErrorAction SilentlyContinue).Source }
    $c
}

function Get-KDiagSmart {
    $smartctl = Find-KSmartctl
    if (-not $smartctl) {
        # Sem smartctl: o que o Windows sabe
        Get-PhysicalDisk | ForEach-Object {
            $st = if ($_.HealthStatus -eq 'Healthy') { 'OK' } else { 'Critico' }
            New-KAchado 'Saúde dos discos' $_.FriendlyName $st "Status do Windows: $($_.HealthStatus)"
        }
        New-KAchado 'Saúde dos discos' 'SMART detalhado' Info 'smartctl não instalado' `
            'Para veredito real (setores realocados, desgaste do SSD): winget install smartmontools.smartmontools'
        return
    }

    $scan = & $smartctl --scan -j 2>$null | Out-String | ConvertFrom-Json
    foreach ($dev in $scan.devices) {
        $j = & $smartctl -a -j -d $dev.type $dev.name 2>$null | Out-String | ConvertFrom-Json
        if (-not $j -or -not $j.model_name) { continue }
        $nome  = "$($j.model_name) ($([math]::Round($j.user_capacity.bytes / 1GB)) GB)"
        $info  = @()
        $probs = @()
        $nivel = 'OK'

        if ($j.temperature.current)     { $info += "Temp: $($j.temperature.current)°C" }
        if ($j.power_on_time.hours)     { $info += "Horas ligado: $($j.power_on_time.hours)" }
        if ($j.smart_status -and -not $j.smart_status.passed) { $nivel = 'Critico'; $probs += 'SMART reprovado' }

        $nv = $j.nvme_smart_health_information_log
        if ($nv) {
            $info += "Desgaste: $($nv.percentage_used)%"
            if ($nv.critical_warning -ne 0)                     { $nivel = 'Critico'; $probs += "aviso crítico ($($nv.critical_warning))" }
            if ($nv.percentage_used -ge 90)                     { $nivel = 'Critico'; $probs += 'vida útil quase no fim' }
            elseif ($nv.percentage_used -ge 70 -and $nivel -ne 'Critico') { $nivel = 'Atencao'; $probs += 'desgaste alto' }
            if ($nv.available_spare -lt $nv.available_spare_threshold) { $nivel = 'Critico'; $probs += 'reserva esgotada' }
            if ($nv.media_errors -gt 0 -and $nivel -ne 'Critico') { $nivel = 'Atencao'; $probs += "$($nv.media_errors) erro(s) de mídia" }
        }

        $attrs = $j.ata_smart_attributes.table
        if ($attrs) {
            $raw = { param($id) ($attrs | Where-Object id -eq $id | Select-Object -First 1).raw.value }
            $realoc   = & $raw 5
            $pendente = & $raw 197
            $incorr   = & $raw 198
            $vida     = ($attrs | Where-Object { $_.id -in 231, 233, 169, 177, 202 -and $_.name -match 'Life|Wear|Media_Wearout' } | Select-Object -First 1).value
            if ($null -ne $realoc)   { $info += "Realocados: $realoc" }
            if ($null -ne $pendente) { $info += "Pendentes: $pendente" }
            if ($vida)               { $info += "Vida restante: $vida%" }
            if ($pendente -gt 0 -or $incorr -gt 0) { $nivel = 'Critico'; $probs += 'setores pendentes/incorrigíveis' }
            elseif ($realoc -gt 0 -and $nivel -ne 'Critico') { $nivel = if ($realoc -gt 50) { 'Critico' } else { 'Atencao' }; $probs += 'setores realocados' }
        }

        $rec = switch ($nivel) {
            'Critico' { 'Disco com defeito ou no fim da vida. FAÇA BACKUP AGORA e troque o disco.' }
            'Atencao' { 'Disco dando sinais de desgaste. Garanta backup e acompanhe.' }
        }
        $det = (@($probs) + $info) -join ' | '
        New-KAchado 'Saúde dos discos' $nome $nivel $det $rec
    }
}

# ── Eventos e estabilidade ─────────────────────────────────────
function Get-KDiagEventos {
    param([int]$Dias = 30)
    $desde = (Get-Date).AddDays(-$Dias)
    $contar = {
        param($filtro)
        @(Get-WinEvent -FilterHashtable $filtro -ErrorAction SilentlyContinue).Count
    }

    $kp = & $contar @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $desde }
    if ($kp) { New-KAchado 'Estabilidade' 'Desligamentos inesperados' Atencao "$kp em $Dias dias (Kernel-Power 41)" `
                   'Travamento, queda de energia ou fonte/bateria fraca. Se for frequente, verifique fonte, temperatura e memória.' }

    $bsod = & $contar @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $desde }
    $dumps = @(Get-ChildItem "$env:SystemRoot\Minidump" -Filter *.dmp -ErrorAction SilentlyContinue | Where-Object LastWriteTime -gt $desde).Count
    $telas = [math]::Max($bsod, $dumps)
    if ($telas) { New-KAchado 'Estabilidade' 'Telas azuis' Critico "$telas em $Dias dias (dumps em $env:SystemRoot\Minidump)" `
                      'Analise os dumps (WinDbg/BlueScreenView). Causas comuns: driver, memória, disco. Agende o teste de memória.' }
    else { New-KAchado 'Estabilidade' 'Telas azuis' OK "Nenhuma em $Dias dias" }

    $whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $desde } -ErrorAction SilentlyContinue)
    $wheaErr = @($whea | Where-Object Level -le 2).Count
    if ($wheaErr) { New-KAchado 'Hardware' 'Erros de hardware (WHEA)' Critico "$wheaErr erro(s) em $Dias dias" `
                        'Erro reportado pelo próprio hardware (CPU, memória, PCIe). Verifique temperatura, overclock/XMP e memória.' }
    elseif ($whea.Count) { New-KAchado 'Hardware' 'Erros de hardware (WHEA)' Atencao "$($whea.Count) aviso(s) corrigido(s) em $Dias dias" }

    $disco = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7, 51, 153; StartTime = $desde } -ErrorAction SilentlyContinue |
               Where-Object ProviderName -match 'disk|stor|nvme|iaStor|amd_sata')
    $badBlock = @($disco | Where-Object Id -eq 7).Count
    if ($badBlock) { New-KAchado 'Hardware' 'Erros de disco' Critico "$badBlock bloco(s) defeituoso(s) registrado(s) (evento 7)" 'Faça backup e verifique o SMART.' }
    elseif ($disco.Count) { New-KAchado 'Hardware' 'Erros de disco' Atencao "$($disco.Count) erro(s)/nova(s) tentativa(s) de E/S (eventos 51/153)" `
                                'Pode ser cabo/porta SATA, disco ou driver de armazenamento.' }
}

function Get-KDiagConfiabilidade {
    param([int]$Dias = 30)
    $idx = Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue |
           Sort-Object TimeGenerated -Descending | Select-Object -First 1
    if ($idx) {
        $v  = [math]::Round($idx.SystemStabilityIndex, 1)
        $st = if ($v -lt 3) { 'Critico' } elseif ($v -lt 6) { 'Atencao' } else { 'OK' }
        New-KAchado 'Estabilidade' 'Índice de estabilidade' $st "$v de 10 (Monitor de Confiabilidade)"
    }
    $dmtf = [Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date).AddDays(-$Dias))
    $falhas = Get-CimInstance Win32_ReliabilityRecords -Filter "SourceName='Application Error' AND TimeGenerated > '$dmtf'" -ErrorAction SilentlyContinue |
              Group-Object ProductName | Sort-Object Count -Descending | Select-Object -First 5
    if ($falhas) {
        $tot = ($falhas | Measure-Object Count -Sum).Sum
        $st  = if ($tot -gt 20) { 'Atencao' } else { 'Info' }
        New-KAchado 'Estabilidade' 'Apps que mais travam' $st (($falhas | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ', ')
    }
}

function Get-KDiagDrivers {
    $codigos = @{ 1 = 'não configurado'; 10 = 'não inicia'; 18 = 'reinstalar driver'; 22 = 'desativado';
                  28 = 'SEM DRIVER'; 31 = 'driver com erro'; 43 = 'parou de responder'; 45 = 'desconectado' }
    $prob = Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigManagerErrorCode -notin 22, 45 }
    if ($prob) {
        $lista = $prob | ForEach-Object {
            $nome = if ($_.Name) { $_.Name } else { $_.DeviceID }
            $cod  = $_.ConfigManagerErrorCode
            "$nome [$(if ($codigos[[int]$cod]) { $codigos[[int]$cod] } else { "código $cod" })]"
        }
        New-KAchado 'Drivers' 'Dispositivos com problema' Atencao ($lista -join ' | ') `
            'Instale/atualize os drivers (Windows Update opcionais ou site do fabricante).'
    } else {
        New-KAchado 'Drivers' 'Dispositivos com problema' OK 'Todos os dispositivos funcionando'
    }
}

function Get-KDiagBateria {
    if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) { return }
    $full   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity
    $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1).DesignedCapacity
    if ($full -and $design) {
        $saude = [math]::Round($full / $design * 100, 1)
        $st    = if ($saude -lt 60) { 'Critico' } elseif ($saude -lt 80) { 'Atencao' } else { 'OK' }
        $rec   = if ($st -eq 'Critico') { 'Bateria bem gasta. Considere a troca.' }
        New-KAchado 'Hardware' 'Bateria' $st "Capacidade: $full de $design mWh de fábrica ($saude%)" $rec
    } else {
        New-KAchado 'Hardware' 'Bateria' Info 'Capacidade não disponível (rode como administrador)'
    }
}

function Get-KDiagPendencias {
    if (Test-KReinicioPendente) {
        New-KAchado 'Sistema' 'Reinicialização pendente' Atencao 'Há atualizações/reparos esperando reinício' 'Reinicie o PC.'
    }
}

# ── Orquestrador ───────────────────────────────────────────────
function Get-KDiagnostico {
    Write-KLog 'Diagnóstico' Titulo
    $etapas = [ordered]@{
        'Sistema'           = { Get-KDiagSistema }
        'Memória'           = { Get-KDiagMemoria }
        'Disco do sistema'  = { Get-KDiagDiscoSistema }
        'Espaço'            = { Get-KDiagEspaco }
        'SMART'             = { Get-KDiagSmart }
        'Tempo ligado'      = { Get-KDiagUptime }
        'Energia'           = { Get-KDiagEnergia }
        'Inicialização'     = { Get-KDiagInicializacao }
        'Segurança'         = { Get-KDiagSeguranca }
        'Bloatware'         = { Get-KDiagBloatware }
        'Eventos'           = { Get-KDiagEventos }
        'Confiabilidade'    = { Get-KDiagConfiabilidade }
        'Drivers'           = { Get-KDiagDrivers }
        'Bateria'           = { Get-KDiagBateria }
        'Pendências'        = { Get-KDiagPendencias }
    }
    $achados = New-Object System.Collections.Generic.List[object]
    foreach ($nome in $etapas.Keys) {
        Write-KProgresso 'Diagnóstico' $nome
        try {
            foreach ($a in @(& $etapas[$nome])) { if ($a) { $achados.Add($a) } }
        } catch {
            $achados.Add((New-KAchado 'Diagnóstico' $nome Info "Não foi possível verificar: $($_.Exception.Message)"))
        }
    }

    $ordem = @{ Critico = 0; Atencao = 1; Info = 2; OK = 3 }
    foreach ($a in $achados | Sort-Object { $ordem[$_.Status] }) {
        $nivel = @{ Critico = 'Erro'; Atencao = 'Aviso'; Info = 'Info'; OK = 'OK' }[$a.Status]
        Write-KLog "$($a.Categoria) > $($a.Item): $($a.Detalhe)" $nivel
        if ($a.Recomendacao) { Write-KLog "→ $($a.Recomendacao)" Detalhe }
    }
    $cont = { param($s) @($achados | Where-Object Status -eq $s).Count }
    Write-KLog ("Resumo: {0} crítico(s), {1} atenção, {2} ok" -f (& $cont 'Critico'), (& $cont 'Atencao'), (& $cont 'OK')) Info
    , $achados.ToArray()
}
