# ============================================================
#  Bateria Acer sem NitroSense / Care Center.
#  A BIOS expõe a classe WMI root\wmi\BatteryControl ({79772EC5-04B1-4bfd-843C-61E7F77B6CC9}),
#  a mesma usada pelos apps da Acer (e pelo driver acer-wmi-battery do Linux):
#    função 1 = "modo saúde" (para de carregar em 80%)
#    função 2 = calibração (a BIOS carrega, descarrega e recarrega com o carregador ligado)
#  A configuração fica gravada na BIOS/EC: vale mesmo sem nenhum programa rodando.
# ============================================================

function Get-KBatteryControl {
    if (-not (Get-CimClass -Namespace root\wmi -ClassName BatteryControl -ErrorAction SilentlyContinue)) { return $null }
    Get-CimInstance -Namespace root\wmi -ClassName BatteryControl -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-KLimiteCarga {
    $bc = Get-KBatteryControl
    if (-not $bc) { return $null }   # não é Acer (ou falta admin)
    try {
        $r = Invoke-CimMethod -InputObject $bc -MethodName GetBatteryHealthControlStatus -ErrorAction Stop -Arguments @{
            uBatteryNo = [byte]1; uFunctionQuery = [byte]1; uReserved = [byte[]](0, 0) }
    } catch { return $null }
    $st = @($r.uFunctionStatus)
    [pscustomobject]@{
        TemLimite     = [bool]($r.uFunctionList -band 1)
        TemCalibracao = [bool]($r.uFunctionList -band 2)
        LimiteAtivo   = ($st.Count -ge 1 -and $st[0] -eq 1)
        Calibrando    = ($st.Count -ge 2 -and $st[1] -eq 1)
    }
}

function Set-KFuncaoBateriaAcer {
    param([Parameter(Mandatory)][ValidateSet(1, 2)][int]$Funcao, [Parameter(Mandatory)][bool]$Ativo)
    $bc = Get-KBatteryControl
    if (-not $bc) { throw 'controle de bateria da Acer não encontrado (precisa de administrador)' }
    $r = Invoke-CimMethod -InputObject $bc -MethodName SetBatteryHealthControl -ErrorAction Stop -Arguments @{
        uBatteryNo = [byte]1; uFunctionMask = [byte]$Funcao; uFunctionStatus = [byte][int]$Ativo; uReservedIn = [byte[]](0, 0, 0, 0, 0) }
    if ($r.uReturn -ne 0) { throw "a BIOS recusou (código $($r.uReturn))" }
}

function Set-KLimiteCarga {
    param([Parameter(Mandatory)][bool]$Ativo)
    try {
        Set-KFuncaoBateriaAcer 1 $Ativo
        $s = Get-KLimiteCarga
        if ($s.LimiteAtivo -ne $Ativo) { throw 'a BIOS aceitou o comando mas o estado não mudou' }
        Write-KLog "Limite de carga em 80%: $(if ($Ativo) { 'ligado' } else { 'desligado (carrega até 100%)' })" OK
        $true
    } catch {
        Write-KLog "Limite de carga: falhou - $($_.Exception.Message)" Erro
        $false
    }
}

# Calibração: precisa do carregador. O limite de 80% é desligado durante o processo
# e volta ao estado anterior quando a calibração é encerrada pelo K-Bench.
function Start-KCalibracaoBateria {
    $s = Get-KLimiteCarga
    if (-not $s -or -not $s.TemCalibracao) { Write-KLog 'Esta BIOS não oferece calibração de bateria' Aviso; return $false }
    $l = Get-KLeituraBateria
    if ($l -and -not $l.NaTomada) { Write-KLog 'Ligue o carregador antes de calibrar' Aviso; return $false }
    try {
        $estado = Get-KEstadoBateriaAcer
        $estado.LimiteAntes = $s.LimiteAtivo
        $estado.Inicio = (Get-Date).ToString('s')
        Save-KEstadoBateriaAcer $estado
        if ($s.LimiteAtivo) { Set-KFuncaoBateriaAcer 1 $false }
        Set-KFuncaoBateriaAcer 2 $true
        Write-KLog 'Calibração iniciada: deixe na tomada; a BIOS vai carregar até 100%, descarregar e carregar de novo (várias horas).' OK
        Write-KLog 'Pode usar o note de leve, sem desligar o carregador. Quando a carga voltar a 100% depois de descer, encerre aqui no K-Bench.' Detalhe
        $true
    } catch {
        Write-KLog "Calibração: falhou - $($_.Exception.Message)" Erro
        $false
    }
}

function Stop-KCalibracaoBateria {
    try {
        Set-KFuncaoBateriaAcer 2 $false
        $estado = Get-KEstadoBateriaAcer
        if ($estado.LimiteAntes) { Set-KFuncaoBateriaAcer 1 $true; Write-KLog 'Limite de 80% religado (estava ligado antes da calibração)' Detalhe }
        Save-KEstadoBateriaAcer @{}
        Write-KLog 'Calibração encerrada' OK
        $true
    } catch {
        Write-KLog "Encerrar calibração: falhou - $($_.Exception.Message)" Erro
        $false
    }
}

function Get-KEstadoBateriaAcer {
    $arq = Join-Path $KB.Raiz 'estado\bateria-acer.json'
    $h = @{}
    if (Test-Path $arq) { try { (Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } } catch {} }
    $h
}

function Save-KEstadoBateriaAcer([hashtable]$Estado) {
    $dir = Join-Path $KB.Raiz 'estado'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'bateria-acer.json'), ($Estado | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
}
