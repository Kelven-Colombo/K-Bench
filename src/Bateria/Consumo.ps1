# ============================================================
#  Medidor de consumo (W) em tempo real + teste guiado.
#  Separa o "piso" da máquina (parada) do gasto do uso (vídeo, navegador).
# ============================================================

function Get-KLeituraBateria {
    $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $b) { return $null }
    [pscustomobject]@{
        Hora        = Get-Date
        NaTomada    = [bool]$b.PowerOnline
        DescargaW   = if ($b.Discharging -and $b.DischargeRate -gt 0) { [math]::Round($b.DischargeRate / 1000, 2) } else { 0 }
        RestanteMWh = [double]$b.RemainingCapacity
    }
}

function Get-KBrilho {
    (Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue | Select-Object -First 1).CurrentBrightness
}

function Set-KBrilho([int]$Pct) {
    $m = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]0; Brightness = [byte]$Pct } -ErrorAction SilentlyContinue | Out-Null }
}

# Mede por N segundos. Duas fontes independentes:
#  - a taxa de descarga (W) que o controlador mede na corrente: é o consumo real;
#  - a queda da "carga restante" (mWh): é a estimativa do medidor da bateria.
# Se a carga cai bem mais rápido que a energia que saiu, o medidor está descalibrado
# (a % despenca e a previsão de tempo enlouquece, mesmo com consumo normal).
function Measure-KConsumo {
    param(
        [int]$Segundos = 120,
        [int]$Intervalo = 5,
        [string]$Rotulo = 'Medição',
        [System.Collections.Generic.List[object]]$Amostras
    )
    $ini = Get-KLeituraBateria
    if (-not $ini) { Write-KLog 'Bateria não encontrada' Erro; return $null }
    if ($ini.NaTomada) { Write-KLog 'Está na tomada: tire o carregador pra medir' Aviso; return $null }

    $cpuAntes = @{}; Get-Process | ForEach-Object { $cpuAntes["$($_.Id)"] = $_.CPU }
    $gpuAcordada = 0; $n = 0
    $taxas = New-Object System.Collections.Generic.List[double]
    # A carga restante muda em degraus: só vale medir entre dois momentos em que ela mudou
    $degraus = New-Object System.Collections.Generic.List[object]
    $ultimaCarga = $ini.RestanteMWh
    $energiaMWh = 0.0; $tAnt = $ini.Hora; $wAnt = $ini.DescargaW
    $fim = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $fim) {
        Start-Sleep -Seconds $Intervalo
        $l = Get-KLeituraBateria
        if ($l.NaTomada) { Write-KLog 'Carregador conectado no meio da medição: parei' Aviso; return $null }
        $g = Get-KGpuDedicada
        $n++; if ($g -and $g.Acordada) { $gpuAcordada++ }
        if ($l.DescargaW -gt 0) { $taxas.Add($l.DescargaW) }
        $energiaMWh += (($wAnt + $l.DescargaW) / 2) * 1000 * ($l.Hora - $tAnt).TotalHours
        $tAnt = $l.Hora; $wAnt = $l.DescargaW
        if ($l.RestanteMWh -ne $ultimaCarga) { $degraus.Add($l); $ultimaCarga = $l.RestanteMWh }
        if ($null -ne $Amostras) { $Amostras.Add([pscustomobject]@{ Fase = $Rotulo; Hora = $l.Hora.ToString('HH:mm:ss'); W = $l.DescargaW; RestanteMWh = $l.RestanteMWh; GpuAcordada = [bool]($g -and $g.Acordada) }) }
        $falta = [math]::Max(0, [math]::Round(($fim - (Get-Date)).TotalSeconds))
        Write-KProgresso "$Rotulo`: $($l.DescargaW) W agora · faltam $falta s"
    }
    $horas = ((Get-Date) - $ini.Hora).TotalHours
    $pelaCarga = $null; $gastoMWh = 0
    if ($degraus.Count -ge 3) {
        $p = $degraus[0]; $u = $degraus[$degraus.Count - 1]
        $h = ($u.Hora - $p.Hora).TotalHours; $gastoMWh = $p.RestanteMWh - $u.RestanteMWh
        if ($h -gt 0 -and $gastoMWh -gt 0) { $pelaCarga = [math]::Round($gastoMWh / 1000 / $h, 1) }
    }
    $mediaTaxa = if ($taxas.Count) { [math]::Round(($taxas | Measure-Object -Average).Average, 1) }

    $nucleos = [Environment]::ProcessorCount
    $top = Get-Process | Where-Object { $cpuAntes.ContainsKey("$($_.Id)") -and $null -ne $_.CPU -and $_.Name -ne 'Idle' } |
        ForEach-Object { [pscustomobject]@{ Nome = $_.Name; Seg = $_.CPU - $cpuAntes["$($_.Id)"] } } |
        Group-Object Nome | ForEach-Object { [pscustomobject]@{ Nome = $_.Name; Pct = ($_.Group | Measure-Object Seg -Sum).Sum / $Segundos / $nucleos * 100 } } |
        Sort-Object Pct -Descending | Where-Object Pct -ge 0.5 | Select-Object -First 5

    # A queda de carga é a medida mais fiel; a taxa do controlador serve quando a carga quase não mexe
    # Consumo = taxa do controlador (corrente real); a queda de carga só entra se o controlador não informar
    $w = if ($mediaTaxa) { $mediaTaxa } else { $pelaCarga }
    $quedaMWh = $ini.RestanteMWh - $ultimaCarga
    [pscustomobject]@{
        Rotulo = $Rotulo; W = $w; TaxaControlador = $mediaTaxa; PelaCarga = $pelaCarga
        EnergiaMWh = [math]::Round($energiaMWh); QuedaCargaMWh = $quedaMWh
        CargaPct = [math]::Round($ultimaCarga / [math]::Max(1, (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity) * 100)
        Minutos = [math]::Round($horas * 60, 1); Brilho = Get-KBrilho
        GpuAcordadaPct = if ($n) { [math]::Round($gpuAcordada / $n * 100) } else { 0 }
        Top = @($top | ForEach-Object { '{0} {1:N1}%' -f $_.Nome, $_.Pct })
    }
}

function Get-KFasesTesteConsumo {
    @(
        [pscustomobject]@{ Id = 'Parado';    Nome = 'Parado na área de trabalho'; Limite = 7;  Instrucao = 'Feche TODOS os programas (inclusive o navegador), deixe só a área de trabalho e não mexa no note.' }
        [pscustomobject]@{ Id = 'Video';     Nome = 'Vídeo no YouTube';           Limite = 11; Instrucao = 'Abra um vídeo no YouTube em 1080p, em tela cheia, e deixe tocando.' }
        [pscustomobject]@{ Id = 'Navegacao'; Nome = 'Navegação leve';             Limite = 12; Instrucao = 'Use como no dia a dia: navegador com suas abas, rolando páginas, sem vídeo.' }
    )
}

# Teste guiado: brilho fixo em 40% (restaurado no fim), preparo entre as fases e veredito.
function Invoke-KTesteConsumo {
    param([int]$SegundosFase = 120, [int]$Preparo = 30, [string[]]$Fases = @('Parado', 'Video', 'Navegacao'))
    $l = Get-KLeituraBateria
    if (-not $l) { Write-KLog 'Este PC não tem bateria' Erro; return }
    if ($l.NaTomada) { Write-KLog 'Tire o carregador antes de começar o teste de consumo' Aviso; return }

    Write-KLog 'Teste de consumo' Titulo
    Write-KLog "Cada fase mede $([math]::Round($SegundosFase / 60, 1)) min com o brilho em 40%. Entre as fases você tem $Preparo s pra se preparar (siga as instruções aqui no log)." Detalhe
    $brilhoAntes = Get-KBrilho
    if ($null -ne $brilhoAntes) { Set-KBrilho 40 }
    $amostras = New-Object System.Collections.Generic.List[object]
    $res = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($f in Get-KFasesTesteConsumo | Where-Object { $Fases -contains $_.Id }) {
            Write-KLog "$($f.Nome): $($f.Instrucao)" Aviso
            for ($s = $Preparo; $s -gt 0; $s -= 5) { Write-KProgresso "Prepare: $($f.Nome) · começa em $s s"; Start-Sleep -Seconds ([math]::Min(5, $s)) }
            Write-KLog "Medindo: $($f.Nome)…" Info
            $m = Measure-KConsumo -Segundos $SegundosFase -Rotulo $f.Nome -Amostras $amostras
            if (-not $m) { break }
            $m | Add-Member Limite $f.Limite
            $m | Add-Member Id $f.Id
            $res.Add($m)
            Write-KLog ("{0}: {1} W (controlador {2} W, pela carga {3} W){4}" -f $f.Nome, $m.W, $m.TaxaControlador, $m.PelaCarga, $(if ($m.Top) { " · CPU: $($m.Top -join ', ')" })) $(if ($m.W -gt $f.Limite) { 'Aviso' } else { 'OK' })
        }
    } finally {
        if ($null -ne $brilhoAntes) { Set-KBrilho $brilhoAntes }
    }
    if ($amostras.Count) {
        New-Item -ItemType Directory -Path $KB.LogDir -Force | Out-Null
        $csv = Join-Path $KB.LogDir ("$($env:COMPUTERNAME)_consumo_{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
        $amostras | Export-Csv $csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        Write-KLog "Amostras: $csv" Detalhe
    }
    $achados = @(foreach ($m in $res) { Get-KVereditoConsumo $m }) + @(Get-KVereditoMedidor $res)
    foreach ($a in $achados) { Write-KLog "[$($a.Status)] $($a.Item): $($a.Detalhe)$(if ($a.Recomendacao) { " → $($a.Recomendacao)" })" $(if ($a.Status -in 'Critico', 'Atencao') { 'Aviso' } else { 'Info' }) }
    $achados
}

# Compara a energia que saiu de verdade com o quanto a "carga restante" caiu
function Get-KVereditoMedidor($Medicoes) {
    $e = ($Medicoes | Measure-Object EnergiaMWh -Sum).Sum
    $q = ($Medicoes | Measure-Object QuedaCargaMWh -Sum).Sum
    if ($e -lt 100 -or $q -lt 200) { return }   # pouco dado pra concluir
    $razao = [math]::Round($q / $e, 1)
    $pct = ($Medicoes | Select-Object -Last 1).CargaPct
    $det = 'A carga caiu {0} mWh, mas só saíram {1} mWh da bateria ({2:N1}x mais) | carga em {3}%' -f $q, $e, $razao, $pct
    if ($razao -ge 1.5) {
        $rec = 'A maior parte da queda não é consumo: é o medidor da bateria (a % cai rápido demais e a previsão de tempo enlouquece). ' +
               'Calibre: desative o limite de carga de 80% (app da Acer/BIOS), carregue até 100% e deixe mais 2 h na tomada; use na bateria até desligar sozinho; carregue até 100% sem interromper. ' +
               'Com o limite de 80% sempre ligado o medidor nunca vê a carga cheia e vai se perdendo. Se depois de calibrar a diferença continuar, a bateria (alguma célula) está fraca de verdade, mesmo com o Windows dizendo 98%.'
        if ($pct -le 20) { $rec += ' Obs.: medido com pouca carga, onde o medidor corrige mais; repita o teste entre 50% e 80% pra confirmar.' }
        New-KAchado 'Teste de consumo' 'Medidor da bateria' $(if ($razao -ge 2.5) { 'Critico' } else { 'Atencao' }) $det $rec
    } else {
        New-KAchado 'Teste de consumo' 'Medidor da bateria' OK $det
    }
}

function Get-KVereditoConsumo($m) {
    $cap = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1).FullChargedCapacity
    $horas = if ($cap -and $m.W -gt 0) { ' → ~{0:N1} h com carga total' -f ($cap / 1000 / $m.W) }
    $det = '{0} W em {1} min, brilho {2}%{3}{4}' -f $m.W, $m.Minutos, $m.Brilho, $horas, $(if ($m.Top) { " | CPU: $($m.Top -join ', ')" })
    if ($m.GpuAcordadaPct -gt 0) { $det += " | GPU NVIDIA acordada em $($m.GpuAcordadaPct)% do tempo" }
    $st = if ($m.W -gt $m.Limite * 1.4) { 'Critico' } elseif ($m.W -gt $m.Limite) { 'Atencao' } else { 'OK' }
    $rec = switch ($m.Id) {
        'Parado' {
            if ($st -ne 'OK') {
                if ($m.GpuAcordadaPct -gt 20) { 'A GPU NVIDIA não está dormindo com o PC parado: veja os processos na GPU dedicada e o driver NVIDIA.' }
                elseif ($m.Top) { 'Parado e mesmo assim gastando: algum processo em segundo plano (veja a lista de CPU) não deixa o processador repousar.' }
                else { 'Piso alto sem processo culpado: suspeite de driver de plataforma (chipset, Intel DTT/IPF, vídeo Intel), BIOS ou hardware (tela, SSD, Wi-Fi). Atualize os drivers pelo site da Acer/Intel e repita.' }
            }
        }
        'Video' { if ($st -ne 'OK') { 'Vídeo gastando demais: confira se o driver de vídeo Intel está atualizado (decodificação por hardware) e use o modo de economia do navegador.' } }
        'Navegacao' { if ($st -ne 'OK') { 'Navegador pesado: ative o "Economia de energia" (chrome://settings/performance), feche abas e extensões que ficam rodando.' } }
    }
    New-KAchado 'Teste de consumo' $(switch ($m.Id) { 'Parado' { 'Parado (piso da máquina)' } 'Video' { 'Vídeo' } default { 'Navegação' } }) $st $det $rec
}
