# ============================================================
#  Renderiza cada página da GUI em PNG, fora da tela, com dados reais
#  (diagnósticos só de leitura). Útil pra revisar o visual sem abrir a janela.
#    powershell -STA -ExecutionPolicy Bypass -File .\tools\Preview-KGui.ps1 -Saida C:\temp\kbench
# ============================================================
param([string]$Saida = (Join-Path $env:TEMP 'kbench-preview'), [switch]$SemDados, [switch]$DriversOnline)

$raiz = Split-Path $PSScriptRoot
foreach ($a in Get-ChildItem (Join-Path $raiz 'src') -Recurse -Filter *.ps1 | Sort-Object FullName) { . $a.FullName }
$KXaml = Get-Content (Join-Path $raiz 'gui\MainWindow.xaml') -Raw -Encoding UTF8
New-Item -ItemType Directory -Path $Saida -Force | Out-Null
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Invoke-KPump {
    $f = New-Object Windows.Threading.DispatcherFrame
    [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke('Background', [Windows.Threading.DispatcherOperationCallback]{ param($x) $x.Continue = $false; $null }, $f) | Out-Null
    [Windows.Threading.Dispatcher]::PushFrame($f)
}

# Dados
$diag = $null; $bat = $null; $corr = $null
if (-not $SemDados) {
    $diag = Get-KDiagnostico 6>$null
    $bat  = Get-KDiagBateriaEnergia
    $corr = @(Get-KSituacaoCorrecoes)
    $tw = @(Get-KSituacaoTweaks)
    $pr = @(Get-KSituacaoProgramas)
    $script:KApps = @(Get-KAppsInstalados)
}

# Monta a janela como a GUI faz (sem ShowDialog)
$KB.LogSink = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
[xml]$xml = $KXaml
$janela = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xml))
$script:KUi = @{ Janela = $janela }
foreach ($n in $xml.SelectNodes('//*[@Name]')) { $script:KUi[$n.GetAttribute('Name')] = $janela.FindName($n.GetAttribute('Name')) }
$ui = $script:KUi
$win = Get-KWindows
$ui.TxtMaquina.Text = "$env:COMPUTERNAME`n$($win.Nome) $($win.Versao)"
$ui.TxtVersao.Text = "K-Bench $($KB.Versao)"

$p = $true
foreach ($e in Get-KEtapasManutencao) { $l = New-KLinhaInterruptor $e.Nome $e.Descricao $e $e.Rapida -Primeira $p; $p = $false; [void]$ui.PnlEtapas.Children.Add($l.Linha) }
$p = $true
foreach ($r in Get-KReparos) { $l = New-KLinhaInterruptor $r.Nome $r.Descricao $r.Id $false $(if ($r.Reinicio) { 'Reinício' }) '#FF9F0A' $p; $p = $false; [void]$ui.PnlReparos.Children.Add($l.Linha) }
$ordem = @{ Critico = 0; Atencao = 1; Info = 2; OK = 3 }
if ($diag) { $ui.DgAchados.ItemsSource = @($diag | Sort-Object { $ordem[$_.Status] }); Set-KContagem $diag }
if ($bat)  { $ui.DgBateria.ItemsSource = @($bat | Sort-Object { $ordem[$_.Status] }) }
if ($corr) { Update-KListaEnergia $corr }
if ($tw) { Update-KListaTweaks $tw }
if ($script:KApps) { Set-KFiltroApps }
if (-not $SemDados) { Update-KListaPerfis 'mc'; Update-KListaImpressorasInstaladas; Update-KCartaoFabricante; $script:KDrivers = @(Get-KSituacaoDrivers -Todos -Online:$DriversOnline); $script:KDrvOnline = [bool]$DriversOnline; Show-KDrivers }
if ($pr) { Update-KListaProgramas $pr; $script:KInterruptoresProgramas | Where-Object IsEnabled | Select-Object -First 3 | ForEach-Object { $_.IsChecked = $true } }
$ui.TxtLog.Text = "  K-Bench $($KB.Versao) | prévia`r`n`r`n===[ Diagnóstico ]===`r`n  [OK] Exemplo de linha de log`r`n  [!]  Exemplo de aviso"

$janela.WindowStartupLocation = 'Manual'; $janela.Left = -5000; $janela.Top = 0
$janela.ShowInTaskbar = $false; $janela.ShowActivated = $false
$janela.Show()
foreach ($pg in 'Diagnostico', 'Manutencao', 'Reparos', 'Tweaks', 'Programas', 'Desinstalar', 'Drivers', 'Impressoras', 'Perfis', 'Bateria') {
    $ui["Nav$pg"].IsChecked = $true
    foreach ($q in 'PgDiagnostico', 'PgManutencao', 'PgReparos', 'PgTweaks', 'PgProgramas', 'PgDesinstalar', 'PgDrivers', 'PgImpressoras', 'PgPerfis', 'PgBateria') { $ui[$q].Visibility = if ($q -eq "Pg$pg") { 'Visible' } else { 'Collapsed' } }
    $janela.UpdateLayout(); Invoke-KPump; Invoke-KPump
    $c = $janela.Content
    $c.Background = $janela.Background   # sem isso o texto sobre área transparente sai apagado no PNG
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$c.ActualWidth), ([int]$c.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($c)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create((Join-Path $Saida "$pg.png")); $enc.Save($fs); $fs.Close()
    Write-Host "OK: $Saida\$pg.png"
}
$janela.Close()
