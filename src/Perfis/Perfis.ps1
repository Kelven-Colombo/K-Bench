# ============================================================
#  Perfis: uma receita = ajustes + drivers + programas + impressoras + manutenção.
#  Os três padrão (Meu, MC, Clientes) vivem no código; editar um deles
#  grava uma cópia em C:\ProgramData\K-Bench\perfis\<id>.json, que passa
#  a valer no lugar. Exportar/importar = levar o .json no pendrive.
# ============================================================

function Get-KPastaPerfis { Join-Path $KB.Raiz 'perfis' }

function New-KPerfil {
    param([string]$Id, [string]$Nome, [string]$Descricao = '', [string[]]$Tweaks = @(), [string[]]$Programas = @(),
          [string[]]$Drivers = @(), [bool]$Scanner = $true, [object[]]$Lembradas = @(), [string]$Manutencao = 'Nenhuma', [bool]$ContasNovas = $true,
          [bool]$AtualizarDrivers = $false)
    [pscustomobject]@{
        Id = $Id; Nome = $Nome; Descricao = $Descricao
        Tweaks = @($Tweaks | Sort-Object -Unique); Programas = @($Programas | Sort-Object -Unique)
        Impressoras = [pscustomobject]@{ Drivers = @($Drivers); Scanner = $Scanner; Lembradas = @($Lembradas) }
        Manutencao = $Manutencao; ContasNovas = $ContasNovas; AtualizarDrivers = $AtualizarDrivers
        Padrao = $false; Modificado = $false
    }
}

function Get-KPerfisPadrao {
    $tw = @(Get-KTweaks)
    $nivel = { param([string[]]$n) @($tw | Where-Object { $_.Nivel -in $n } | ForEach-Object Id) }
    $preset = { param([string[]]$p) @(Get-KProgramas | Where-Object { @($_.Presets | Where-Object { $_ -in $p }).Count } | ForEach-Object Id) }

    $meu = New-KPerfil 'meu' 'Meu' 'Configuração pessoal do técnico.' `
        -Tweaks ((& $nivel 'Seguro', 'Recomendado') + 'SemVisaoTarefas', 'MouseSemAceleracao', 'ModoEscuro', 'SemTeclasAderencia', 'NumLock',
                  'AppsSegundoPlano', 'OutlookNovo', 'VincularCelular', 'WuSemDrivers') `
        -Programas ((& $preset 'Runtimes', 'Tecnico', 'Dev') + 'Firefox', 'VLC', 'NanaZip')
    $mc = New-KPerfil 'mc' 'MC Serviços' 'PCs da loja: documentos, consultas online, design e gráfica rápida. Impressoras da rede.' `
        -Tweaks ((& $nivel 'Seguro', 'Recomendado') + 'NumLock', 'SemTeclasAderencia') `
        -Programas (& $preset 'MC', 'Runtimes') -Drivers 'EpsonL3250' -AtualizarDrivers $true
    $cli = New-KPerfil 'clientes' 'Clientes' 'Formatação de cliente: debloat leve, programas básicos, Microsoft 365 e runtimes.' `
        -Tweaks (@(& $nivel 'Seguro', 'Recomendado') | Where-Object { $_ -notin 'RemoverOneDrive', 'ServicosManual' }) `
        -Programas ((& $preset 'Basico', 'Runtimes') + 'M365Pessoal') -AtualizarDrivers $true
    foreach ($p in $meu, $mc, $cli) { $p.Padrao = $true; $p }
}

# Lê um perfil de JSON, completando campos que faltem (arquivo de versão antiga ou feito à mão)
function ConvertFrom-KPerfilJson([string]$Texto) {
    $j = $Texto | ConvertFrom-Json
    $imp = $j.Impressoras
    $p = New-KPerfil -Id "$($j.Id)" -Nome "$($j.Nome)" -Descricao "$($j.Descricao)" -Tweaks @($j.Tweaks | Where-Object { $_ }) `
        -Programas @($j.Programas | Where-Object { $_ }) -Drivers @($imp.Drivers | Where-Object { $_ }) `
        -Scanner $(if ($null -ne $imp.Scanner) { [bool]$imp.Scanner } else { $true }) -Lembradas @($imp.Lembradas | Where-Object { $_ }) `
        -Manutencao $(if ($j.Manutencao) { "$($j.Manutencao)" } else { 'Nenhuma' }) -ContasNovas $(if ($null -ne $j.ContasNovas) { [bool]$j.ContasNovas } else { $true }) `
        -AtualizarDrivers ([bool]$j.AtualizarDrivers)
    if (-not $p.Id) { $p.Id = (ConvertTo-KChaveNome $p.Nome) }
    $p
}

function Get-KPerfis {
    $padrao = @(Get-KPerfisPadrao)
    $salvos = @{}
    foreach ($f in Get-ChildItem (Get-KPastaPerfis) -Filter *.json -ErrorAction SilentlyContinue) {
        try { $p = ConvertFrom-KPerfilJson (Get-Content $f.FullName -Raw -Encoding UTF8); $salvos[$p.Id] = $p }
        catch { Write-KLog "Perfil inválido ignorado: $($f.Name)" Aviso }
    }
    foreach ($p in $padrao) {
        if ($salvos[$p.Id]) { $s = $salvos[$p.Id]; $s.Padrao = $true; $s.Modificado = $true; $s; $salvos.Remove($p.Id) } else { $p }
    }
    $salvos.Values | Sort-Object Nome
}

function Get-KPerfil([Parameter(Mandatory)][string]$IdOuArquivo) {
    if ($IdOuArquivo -match '\.json$') {
        if (-not (Test-Path $IdOuArquivo)) { Write-KLog "Arquivo de perfil não encontrado: $IdOuArquivo" Erro; return }
        return ConvertFrom-KPerfilJson (Get-Content $IdOuArquivo -Raw -Encoding UTF8)
    }
    $p = Get-KPerfis | Where-Object { $_.Id -eq $IdOuArquivo -or $_.Nome -eq $IdOuArquivo } | Select-Object -First 1
    if (-not $p) { Write-KLog "Perfil desconhecido: $IdOuArquivo (veja -ListarPerfis)" Erro }
    $p
}

function ConvertTo-KPerfilJson($Perfil) {
    [ordered]@{
        Id = $Perfil.Id; Nome = $Perfil.Nome; Descricao = $Perfil.Descricao
        Tweaks = @($Perfil.Tweaks); Programas = @($Perfil.Programas)
        Impressoras = [ordered]@{ Drivers = @($Perfil.Impressoras.Drivers); Scanner = [bool]$Perfil.Impressoras.Scanner
                                  Lembradas = @($Perfil.Impressoras.Lembradas | ForEach-Object { [ordered]@{ Mac = $_.Mac; Nome = $_.Nome; Modelo = $_.Modelo } }) }
        Manutencao = $Perfil.Manutencao; ContasNovas = [bool]$Perfil.ContasNovas; AtualizarDrivers = [bool]$Perfil.AtualizarDrivers
    } | ConvertTo-Json -Depth 5
}

function Save-KPerfil([Parameter(Mandatory)]$Perfil) {
    New-Item -ItemType Directory -Path (Get-KPastaPerfis) -Force | Out-Null
    if (-not $Perfil.Id) { $Perfil.Id = ConvertTo-KChaveNome $Perfil.Nome }
    Set-Content -LiteralPath (Join-Path (Get-KPastaPerfis) "$($Perfil.Id).json") -Value (ConvertTo-KPerfilJson $Perfil) -Encoding UTF8
}

# Perfil padrão: volta ao original. Perfil criado: some.
function Remove-KPerfil([Parameter(Mandatory)][string]$Id) {
    Remove-Item -LiteralPath (Join-Path (Get-KPastaPerfis) "$Id.json") -ErrorAction SilentlyContinue
}

# O que está neste PC agora (bom pra montar o perfil "Meu" a partir da própria máquina)
function Get-KCapturaPC {
    $tw = @(Get-KSituacaoTweaks | Where-Object { $_.Situacao -in 'Aplicado pelo K-Bench', 'Já está assim' } | ForEach-Object Id)
    $pr = @(Get-KSituacaoProgramas | Where-Object { $_.Instalado -and -not $_.SemDesinstalar } | ForEach-Object Id)
    $inst = @(Get-KImpressorasInstaladas)
    $drv = @(Get-KModelosImpressora | Where-Object { $m = $_.Modelo; @($inst | Where-Object Driver -eq $m).Count } | ForEach-Object Id)
    $lem = @($inst | Where-Object { $_.Mac } | ForEach-Object { [pscustomobject]@{ Mac = $_.Mac; Nome = $_.Nome; Modelo = $_.Driver } })
    [pscustomobject]@{ Tweaks = $tw; Programas = $pr; Drivers = $drv; Lembradas = $lem }
}

function Get-KResumoPerfil($Perfil) {
    $i = $Perfil.Impressoras
    $partes = @("$(@($Perfil.Tweaks).Count) ajustes", "$(@($Perfil.Programas).Count) programas")
    $ni = @($i.Drivers).Count + @($i.Lembradas).Count
    if ($ni) { $partes += "$(@($i.Lembradas).Count) impressora(s), $(@($i.Drivers).Count) driver(s)" }
    if ($Perfil.AtualizarDrivers) { $partes += 'atualiza drivers' }
    if ($Perfil.Manutencao -ne 'Nenhuma') { $partes += "manutenção $($Perfil.Manutencao.ToLower())" }
    $partes -join '  ·  '
}

# ── Aplicar ────────────────────────────────────────────────────
function Invoke-KPerfil {
    param([Parameter(Mandatory)]$Perfil, [string[]]$Modulos = @('Tweaks', 'Drivers', 'Programas', 'Impressoras', 'Manutencao'))
    $p = $Perfil
    Write-KLog "Perfil $($p.Nome)" Titulo
    Write-KLog (Get-KResumoPerfil $p) Detalhe
    $inicio = Get-Date
    New-KPontoRestauracao "K-Bench - perfil $($p.Nome)" | Out-Null

    if ($Modulos -contains 'Tweaks' -and @($p.Tweaks).Count) {
        Write-KLog 'Ajustes' Titulo
        $pend = @(Get-KSituacaoTweaks | Where-Object { $_.Pendente -and $_.Id -in $p.Tweaks } | ForEach-Object Id)
        if ($pend) { Invoke-KTweaks -Aplicar $pend -TodosUsuarios ([bool]$p.ContasNovas) } else { Write-KLog 'Todos os ajustes do perfil já estão aplicados' OK }
    }
    if ($Modulos -contains 'Drivers' -and $p.AtualizarDrivers) {
        Write-KLog 'Drivers' Titulo
        $up = @(Get-KSituacaoDrivers -Online | Where-Object Situacao -eq 'Atualização')
        if ($up) { Install-KAtualizacoesDrivers $up } else { Write-KLog 'Drivers em dia (Windows Update e NVIDIA)' OK }
        $sem = @(Get-KDispositivos | Where-Object Problema -eq 28)
        if ($sem) { Write-KLog "Ainda sem driver: $(($sem | ForEach-Object Nome) -join ', '). Veja a página Drivers (fabricante do PC)." Aviso }
    }
    if ($Modulos -contains 'Programas' -and @($p.Programas).Count) {
        Write-KLog 'Programas' Titulo
        $falta = @(Get-KSituacaoProgramas | Where-Object { -not $_.Instalado -and $_.Id -in $p.Programas } | ForEach-Object Id)
        if ($falta) { Invoke-KProgramas -Instalar $falta } else { Write-KLog 'Todos os programas do perfil já estão instalados' OK }
    }
    $imp = $p.Impressoras
    if ($Modulos -contains 'Impressoras' -and (@($imp.Drivers).Count -or @($imp.Lembradas).Count)) {
        Write-KLog 'Impressoras' Titulo
        foreach ($id in $imp.Drivers) {
            $m = Get-KModelosImpressora | Where-Object Id -eq $id
            if (-not $m) { continue }
            if (Install-KDriverImpressora $m.Modelo -Ipp $false) { if ($imp.Scanner) { Install-KScannerImpressora $m.Modelo | Out-Null } }
        }
        if (@($imp.Lembradas).Count) {
            $achadas = @(Find-KImpressorasRede)
            foreach ($l in $imp.Lembradas) {
                $a = $achadas | Where-Object { $_.Mac -eq $l.Mac } | Select-Object -First 1
                if (-not $a) { Write-KLog "$($l.Nome): não está na rede agora (ligada? mesma rede?)" Aviso; continue }
                if ($a.Instalada) { Write-KLog "$($l.Nome): já configurada ($($a.InstaladaComo))" OK; continue }
                Add-KImpressoraRede $a -Nome $l.Nome -Scanner ([bool]$imp.Scanner) | Out-Null
            }
            $novas = @($achadas | Where-Object { -not $_.Instalada -and $_.Mac -notin @($imp.Lembradas | ForEach-Object Mac) })
            if ($novas) { Write-KLog "Também na rede (não estão no perfil): $(($novas | ForEach-Object { "$($_.Modelo) $($_.Host)" }) -join '; '). Adicione pela aba Impressoras." Info }
        }
    }
    if ($Modulos -contains 'Manutencao' -and $p.Manutencao -in 'Rapida', 'Completa') {
        Invoke-KManutencao -Modo $p.Manutencao
    }
    $min = [int]((Get-Date) - $inicio).TotalMinutes
    Write-KLog "Perfil $($p.Nome) aplicado em $min min" OK
    if (Test-KReinicioPendente) { Write-KLog 'Reinicie o PC pra concluir.' Aviso }
}
