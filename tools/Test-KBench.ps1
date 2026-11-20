# ============================================================
#  Verificação rápida pra desenvolvimento (não altera o sistema):
#  sintaxe, codificação, XAML, injeção no runspace, diagnóstico e build.
#    powershell -ExecutionPolicy Bypass -File .\tools\Test-KBench.ps1
# ============================================================
param([string]$Saida = (Join-Path $env:TEMP 'kbench-teste'))

$raiz = Split-Path $PSScriptRoot
$falhas = 0
function Test-Passo($nome, [scriptblock]$teste) {
    try { $r = & $teste; Write-Host "  [OK] $nome $(if ($r) { "- $r" })" -ForegroundColor Green }
    catch { $script:falhas++; Write-Host "  [X]  $nome - $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host "`n== K-Bench: testes ==" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $Saida -Force | Out-Null

$ps1 = Get-ChildItem $raiz -Recurse -Filter *.ps1 | Where-Object FullName -notmatch '\\dist\\'
Test-Passo 'Sintaxe dos .ps1' {
    foreach ($a in $ps1) {
        $e = $null
        [Management.Automation.Language.Parser]::ParseFile($a.FullName, [ref]$null, [ref]$e) | Out-Null
        if ($e) { throw "$($a.Name):$($e[0].Extent.StartLineNumber) $($e[0].Message)" }
    }
    "$($ps1.Count) arquivos"
}
Test-Passo 'UTF-8 com BOM (acentos no PS 5.1)' {
    $sem = $ps1 | Where-Object { $b = [IO.File]::ReadAllBytes($_.FullName); -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }
    if ($sem) { throw "sem BOM: $($sem.Name -join ', ')" }
}

foreach ($a in Get-ChildItem (Join-Path $raiz 'src') -Recurse -Filter *.ps1 | Sort-Object FullName) { . $a.FullName }
$KB.LogDir = $Saida
$KXaml = Get-Content (Join-Path $raiz 'gui\MainWindow.xaml') -Raw -Encoding UTF8

Test-Passo 'XAML carrega' {
    Add-Type -AssemblyName PresentationFramework
    [xml]$x = $KXaml
    $j = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    $nomes = $x.SelectNodes('//*[@Name]') | ForEach-Object { $_.GetAttribute('Name') }
    $faltando = $nomes | Where-Object { -not $j.FindName($_) }
    if ($faltando) { throw "não encontrados: $faltando" }
    "$(@($nomes).Count) controles"
}

Test-Passo 'Funções no runspace da GUI' {
    $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    Get-ChildItem function: | Where-Object { $_.Name -match '^\w+-K' } | ForEach-Object {
        $iss.Commands.Add((New-Object Management.Automation.Runspaces.SessionStateFunctionEntry $_.Name, $_.Definition)) }
    $iss.Variables.Add((New-Object Management.Automation.Runspaces.SessionStateVariableEntry 'KB', $KB, ''))
    $rs = [runspacefactory]::CreateRunspace($iss); $rs.Open()
    $p = [powershell]::Create(); $p.Runspace = $rs
    $r = $p.AddScript('Get-KDiagSistema; Get-KReparos | Measure-Object | % Count').Invoke()
    $rs.Dispose()
    if ($p.Streams.Error) { throw $p.Streams.Error[0] }
    if (-not $r) { throw 'sem retorno' }
    "$($r.Count) objetos"
}

$achados = $null
Test-Passo 'Diagnóstico completo' {
    $t = Measure-Command { $script:achados = Get-KDiagnostico 6>$null }
    $info = @($script:achados | Where-Object { $_.Detalhe -like 'Não foi possível*' })
    $info | ForEach-Object { Write-Host "       falhou: $($_.Item) - $($_.Detalhe)" -ForegroundColor Yellow }
    "$(@($script:achados).Count) achados em $([math]::Round($t.TotalSeconds))s"
}
Test-Passo 'Diagnóstico de bateria/energia' {
    $b = @(Get-KDiagBateriaEnergia)
    $falhou = @($b | Where-Object { $_.Detalhe -like 'Não foi possível*' })
    if (-not $b) { throw 'sem achados' }
    "$($b.Count) achados$(if ($falhou) { ", $($falhou.Count) sem verificar" })"
}
Test-Passo 'Situação dos programas' {
    $s = @(Get-KSituacaoProgramas)
    if ($s.Count -ne @(Get-KProgramas).Count) { throw 'contagem não bate' }
    $dup = @(Get-KProgramas | Group-Object Id | Where-Object Count -gt 1)
    if ($dup) { throw "Id repetido: $($dup.Name -join ', ')" }
    "$(@($s | Where-Object Instalado).Count) instalado(s) de $($s.Count)"
}
Test-Passo 'Programas instalados (desinstalador)' {
    $a = @(Get-KAppsInstalados)
    if (-not $a) { throw 'lista vazia' }
    $perigo = @($a | Where-Object { $_.Pasta -and (Test-KPastaProtegida $_.Pasta) })
    if ($perigo) { throw "pasta protegida como pasta de programa: $($perigo[0].Pasta)" }
    "$($a.Count) programas, $(@($a | Where-Object Pasta).Count) com pasta conhecida"
}
Test-Passo 'Drivers (inventário, sem internet)' {
    $m = Get-KFabricante
    $d = @(Get-KSituacaoDrivers -Todos)
    if (-not $d) { throw 'nenhum dispositivo lido' }
    if ((Get-KVersaoNvidia '32.0.16.2124') -ne '621.24') { throw 'conversão de versão NVIDIA errada' }
    "$($m.Marca) $($m.Modelo)  ·  $($d.Count) dispositivos, $(@($d | Where-Object { -not $_.Oculto }).Count) visíveis, $(@($d | Where-Object Problema).Count) com problema"
}
Test-Passo 'Perfis padrão' {
    $ids = @(Get-KTweaks | ForEach-Object Id) + @(Get-KProgramas | ForEach-Object Id)
    $mods = @(Get-KModelosImpressora | ForEach-Object Id)
    foreach ($p in Get-KPerfisPadrao) {
        $x = @(@($p.Tweaks) + @($p.Programas) | Where-Object { $_ -notin $ids }) + @($p.Impressoras.Drivers | Where-Object { $_ -notin $mods })
        if ($x) { throw "perfil $($p.Id) com Id inexistente: $($x -join ', ')" }
        $j = ConvertFrom-KPerfilJson (ConvertTo-KPerfilJson $p)
        if (@($j.Tweaks).Count -ne @($p.Tweaks).Count -or @($j.Programas).Count -ne @($p.Programas).Count) { throw "JSON de $($p.Id) não volta igual" }
    }
    ((Get-KPerfisPadrao | ForEach-Object { "$($_.Nome): $(Get-KResumoPerfil $_)" }) -join ' | ')
}
Test-Passo 'Situação das correções de energia' {
    $s = @(Get-KSituacaoCorrecoes)
    if ($s.Count -ne @(Get-KCorrecoesEnergia).Count) { throw 'contagem não bate' }
    "$(@($s | Where-Object Recomendada).Count) recomendada(s) de $($s.Count)"
}
Test-Passo 'Relatório HTML' { Export-KRelatorioHtml -Achados $achados -Caminho (Join-Path $Saida 'diagnostico.html') 6>$null }
Test-Passo 'Build' { & (Join-Path $raiz 'build.ps1') -Saida (Join-Path $Saida 'kbench.ps1') 6>$null; 'dist gerado' }

if ($falhas) { Write-Host "`n$falhas falha(s)" -ForegroundColor Red; exit 1 }
Write-Host "`nTudo OK. Saída em $Saida" -ForegroundColor Green
