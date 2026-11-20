# ============================================================
#  GUI (WPF, tema escuro). O trabalho pesado roda num runspace
#  separado pra janela não congelar; o log chega por uma fila.
# ============================================================

function Start-KTarefaGui {
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Parametros = @{},
        [scriptblock]$AoConcluir
    )
    if ($script:KTarefa) { return }

    # Runspace novo com todas as funções do K-Bench + o estado compartilhado ($KB)
    $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    Get-ChildItem function: | Where-Object { $_.Name -match '^\w+-K' } | ForEach-Object {
        $iss.Commands.Add((New-Object Management.Automation.Runspaces.SessionStateFunctionEntry $_.Name, $_.Definition))
    }
    $iss.Variables.Add((New-Object Management.Automation.Runspaces.SessionStateVariableEntry 'KB', $KB, ''))
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Script.ToString())
    foreach ($k in $Parametros.Keys) { [void]$ps.AddParameter($k, $Parametros[$k]) }

    $script:KTarefa = @{ PS = $ps; RS = $rs; Nome = $Nome; AoConcluir = $AoConcluir; Handle = $ps.BeginInvoke() }
    Set-KGuiOcupado $true "$Nome…"
}

function Set-KGuiOcupado {
    param([bool]$Ocupado, [string]$Texto)
    $ui = $script:KUi
    foreach ($b in 'BtnManutencao', 'BtnReparos', 'BtnDiagnostico', 'BtnBateria', 'BtnEnergia', 'BtnAplicarEnergia', 'BtnRelBateria', 'BtnConsumo', 'BtnCalibrar', 'ChkLimite80', 'BtnTweaksVerificar', 'BtnTweaksAplicar', 'BtnProgVerificar', 'BtnProgAtualizar', 'BtnProgAplicar', 'BtnDesAtualizar', 'BtnDesinstalar', 'BtnRastrosRemover', 'BtnRastrosManter', 'BtnImpProcurar', 'BtnImpAdicionar', 'BtnDrvProcurar', 'BtnDrvInstalar', 'BtnDrvFabricante', 'BtnDrvBackup', 'BtnDrvRestaurar', 'BtnDrvLimpar', 'BtnPerfilAplicar', 'BtnPerfilCapturar') {
        if ($ui[$b]) { $ui[$b].IsEnabled = -not $Ocupado }
    }
    $ui.PbOcupado.Visibility = if ($Ocupado) { 'Visible' } else { 'Collapsed' }
    if ($Texto) { $ui.TxtStatus.Text = $Texto }
}

function Update-KGui {
    $ui = $script:KUi
    $item = $null
    $sb = New-Object Text.StringBuilder
    while ($KB.LogSink.TryDequeue([ref]$item)) {
        if ($item.Tipo -eq 'Progresso') { $ui.TxtStatus.Text = $item.Texto }
        else { [void]$sb.AppendLine($item.Texto) }
    }
    if ($sb.Length) { $ui.TxtLog.AppendText($sb.ToString()); $ui.TxtLog.ScrollToEnd() }

    $t = $script:KTarefa
    if ($t -and $t.Handle.IsCompleted) {
        $res = $null
        try { $res = $t.PS.EndInvoke($t.Handle) } catch { Write-KLog "Erro em $($t.Nome): $($_.Exception.Message)" Erro }
        foreach ($e in $t.PS.Streams.Error) { Write-KLog "$($t.Nome): $e" Erro }
        $t.PS.Dispose(); $t.RS.Dispose()
        $script:KTarefa = $null
        Set-KGuiOcupado $false "Concluído: $($t.Nome)"
        if ($t.AoConcluir) { & $t.AoConcluir $res }
    }
}

# Linha de lista com interruptor (título + descrição + etiqueta opcional), separada por linha fina
function New-KLinhaInterruptor {
    param([string]$Titulo, [string]$Descricao, $Tag, [bool]$Ligado, [string]$Etiqueta, [string]$CorEtiqueta = '#9A9AA0', [bool]$Primeira,
          [string]$Etiqueta2, [string]$CorEtiqueta2 = '#9A9AA0', [string]$TextoLigar, [string]$TextoDesligar)
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Style = $script:KUi.Janela.FindResource('LinhaLista')
    $cb.Tag = $Tag
    $cb.IsChecked = $Ligado
    $sp = New-Object Windows.Controls.StackPanel
    $l1 = New-Object Windows.Controls.WrapPanel   # etiqueta desce pra linha de baixo se não couber
    $t1 = New-Object Windows.Controls.TextBlock
    $t1.Text = $Titulo; $t1.FontWeight = 'SemiBold'; $t1.Margin = '0,0,8,2'
    [void]$l1.Children.Add($t1)
    foreach ($par in @(@($Etiqueta, $CorEtiqueta), @($Etiqueta2, $CorEtiqueta2))) {
        if ($par[0]) { [void]$l1.Children.Add((New-KPilula $par[0] $par[1])) }
    }
    # Pílula "Vai instalar / Vai desfazer" quando o interruptor sai do estado em que estava
    if ($TextoLigar -or $TextoDesligar) {
        $pend = New-KPilula ' ' '#0A84FF'
        $pend.Visibility = 'Collapsed'
        [void]$l1.Children.Add($pend)
        $cb.DataContext = @{ Pilula = $pend; Inicial = $Ligado; Ligar = $TextoLigar; Desligar = $TextoDesligar }
        $cb.Add_Checked({ Update-KPendente $args[0] })
        $cb.Add_Unchecked({ Update-KPendente $args[0] })
    }
    [void]$sp.Children.Add($l1)
    if ($Descricao) {
        $t2 = New-Object Windows.Controls.TextBlock
        $t2.Text = $Descricao; $t2.TextWrapping = 'Wrap'; $t2.FontSize = 13; $t2.Margin = '0,3,0,0'
        $t2.Foreground = $script:KUi.Janela.FindResource('Texto2')
        [void]$sp.Children.Add($t2)
    }
    $cb.Content = $sp

    $linha = New-Object Windows.Controls.Border
    if (-not $Primeira) { $linha.BorderBrush = $script:KUi.Janela.FindResource('Linha'); $linha.BorderThickness = '0,1,0,0' }
    $linha.Child = $cb
    @{ Linha = $linha; Interruptor = $cb }
}

function New-KPilula([string]$Texto, [string]$Cor = '#9A9AA0') {
    $bd = New-Object Windows.Controls.Border
    $bd.CornerRadius = 7; $bd.Padding = '7,1'; $bd.Margin = '0,0,6,2'; $bd.VerticalAlignment = 'Center'
    $c = [Windows.Media.ColorConverter]::ConvertFromString($Cor)
    $bd.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x38, $c.R, $c.G, $c.B))
    $te = New-Object Windows.Controls.TextBlock
    $te.Text = $Texto; $te.FontSize = 12; $te.FontWeight = 'SemiBold'
    $te.Foreground = New-Object Windows.Media.SolidColorBrush $c
    $bd.Child = $te
    $bd
}

function Update-KPendente($Cb) {
    $d = $Cb.DataContext
    if ($d -isnot [hashtable] -or -not $d.Pilula) { return }
    $lig = [bool]$Cb.IsChecked
    $txt = if ($lig) { $d.Ligar } else { $d.Desligar }
    $d.Pilula.Visibility = if ($lig -ne $d.Inicial -and $txt) { 'Visible' } else { 'Collapsed' }
    if ($txt) { $d.Pilula.Child.Text = $txt }
}

# Linha simples (sem interruptor) com destaque no hover
function New-KLinhaSimples($Conteudo, [bool]$Primeira) {
    $dentro = New-Object Windows.Controls.Border
    $dentro.CornerRadius = 8; $dentro.Padding = '10,10'; $dentro.Margin = '-10,2'
    $dentro.Background = [Windows.Media.Brushes]::Transparent
    $dentro.Child = $Conteudo
    $dentro.Add_MouseEnter({ $args[0].Background = $script:KUi.Janela.FindResource('Hover') })
    $dentro.Add_MouseLeave({ $args[0].Background = [Windows.Media.Brushes]::Transparent })
    $linha = New-Object Windows.Controls.Border
    if (-not $Primeira) { $linha.BorderBrush = $script:KUi.Janela.FindResource('Linha'); $linha.BorderThickness = '0,1,0,0' }
    $linha.Child = $dentro
    $linha
}

function Set-KContagem {
    param($Achados, [string]$Prefixo = 'TxtNum')
    $u = $script:KUi
    $u["${Prefixo}Crit"].Text = @($Achados | Where-Object Status -eq 'Critico').Count
    $u["${Prefixo}Aten"].Text = @($Achados | Where-Object Status -eq 'Atencao').Count
    $u["${Prefixo}Ok"].Text   = @($Achados | Where-Object Status -eq 'OK').Count
}

function Update-KListaEnergia {
    param($Situacoes)
    $u = $script:KUi
    $u.PnlEnergia.Children.Clear()
    $script:KInterruptoresEnergia = @()
    $primeira = $true
    foreach ($s in $Situacoes) {
        $etq, $cor = switch ($s.Situacao) {
            'Não pegou'             { 'Não pegou: aplique de novo', '#FF9F0A' }
            'Aplicada pelo K-Bench' { 'Aplicada', '#30D158' }
            'Recomendada'           { if ($s.Recomendada) { 'Recomendada', '#FF9F0A' } else { 'Opcional', '#9A9AA0' } }
            'Rode a Análise de 60 s' { 'Rode a Análise de 60 s', '#9A9AA0' }
            'Ignorada'              { 'Desligada por você', '#9A9AA0' }
            default                 { 'Já está OK', '#9A9AA0' }
        }
        $l = New-KLinhaInterruptor $s.Nome $s.Descricao $s ($s.Aplicada -or $s.Recomendada) $etq $cor $primeira -TextoLigar 'Vai aplicar' -TextoDesligar $(if ($s.Aplicada) { 'Vai desfazer' } else { 'Deixar de recomendar' })
        $primeira = $false
        [void]$u.PnlEnergia.Children.Add($l.Linha)
        $script:KInterruptoresEnergia += $l.Interruptor
    }
}

# Lista de tweaks agrupada por categoria (um cartão por categoria)
function Update-KListaTweaks {
    param($Situacoes)
    $u = $script:KUi
    $u.PnlTweaks.Children.Clear()
    $script:KInterruptoresTweaks = @()
    $corNivel = @{ 'Seguro' = '#30D158'; 'Recomendado' = '#0A84FF'; 'Agressivo' = '#FF453A'; 'Preferência' = '#BF5AF2' }
    foreach ($g in $Situacoes | Group-Object Categoria) {
        $titulo = New-Object Windows.Controls.TextBlock
        $titulo.Text = $g.Name.ToUpper(); $titulo.Style = $u.Janela.FindResource('Secao')
        [void]$u.PnlTweaks.Children.Add($titulo)
        $cartao = New-Object Windows.Controls.Border
        $cartao.Style = $u.Janela.FindResource('Cartao'); $cartao.Padding = '16,4'; $cartao.Margin = '0,0,0,18'
        $sp = New-Object Windows.Controls.StackPanel
        $primeira = $true
        foreach ($s in $g.Group) {
            $etq, $cor = switch ($s.Situacao) {
                'Aplicado pelo K-Bench' { 'Aplicado', '#30D158' }
                'Já está assim'         { 'Já está assim', '#9A9AA0' }
                'Revertido'             { 'O Windows desfez', '#FF9F0A' }
                'Parcial'               { 'Parcial', '#FF9F0A' }
                'Incompleto'            { 'Incompleto: veja o log', '#FF9F0A' }
                'Nada a fazer'          { 'Nada a fazer', '#9A9AA0' }
                'Não se aplica'         { 'Não se aplica', '#9A9AA0' }
                default                 { $null, $null }
            }
            $ligado = $s.Situacao -in 'Aplicado pelo K-Bench', 'Já está assim', 'Nada a fazer'
            $l = New-KLinhaInterruptor $s.Nome $s.Descricao $s $ligado $s.Nivel $corNivel[$s.Nivel] $primeira $etq $cor -TextoLigar 'Vai aplicar' -TextoDesligar $(if ($s.PeloKBench) { 'Vai desfazer' } else { 'Sem desfazer: não foi o K-Bench' })
            if ($s.Situacao -in 'Nada a fazer', 'Não se aplica') { $l.Interruptor.IsEnabled = $false }
            $primeira = $false
            [void]$sp.Children.Add($l.Linha)
            $script:KInterruptoresTweaks += $l.Interruptor
        }
        $cartao.Child = $sp
        [void]$u.PnlTweaks.Children.Add($cartao)
    }
    $pend = @($Situacoes | Where-Object Pendente).Count
    $u.TxtResumoTweaks.Text = "$(@($Situacoes).Count) ajustes  ·  $pend ainda não aplicado(s)  ·  cada um com desfazer"
    $script:KUi.RbNivelSeguro.IsChecked = $false; $script:KUi.RbNivelRecomendado.IsChecked = $false; $script:KUi.RbNivelAgressivo.IsChecked = $false
}

function Start-KVerificarTweaks {
    Start-KTarefaGui 'Verificando ajustes' -Script { @(Get-KSituacaoTweaks) } -AoConcluir {
        param($res)
        if ($res) { Update-KListaTweaks @($res) }
    }
}

# Lista de programas por categoria; o filtro esconde linhas e cartões vazios
function Update-KListaProgramas {
    param($Situacoes)
    $u = $script:KUi
    $u.PnlProgramas.Children.Clear()
    $script:KInterruptoresProgramas = @()
    $script:KGruposProgramas = @()
    $fonte = @{ msstore = 'Microsoft Store'; feat = 'Recurso do Windows'; odt = 'Download da Microsoft' }
    foreach ($g in $Situacoes | Group-Object Categoria) {
        $titulo = New-Object Windows.Controls.TextBlock
        $titulo.Text = $g.Name.ToUpper(); $titulo.Style = $u.Janela.FindResource('Secao')
        [void]$u.PnlProgramas.Children.Add($titulo)
        $cartao = New-Object Windows.Controls.Border
        $cartao.Style = $u.Janela.FindResource('Cartao'); $cartao.Padding = '16,4'; $cartao.Margin = '0,0,0,18'
        $sp = New-Object Windows.Controls.StackPanel
        $primeira = $true
        foreach ($s in $g.Group) {
            $etq, $cor = switch ($s.Situacao) {
                'Instalado'  { 'Instalado', '#30D158' }
                'Parcial'    { 'Instalado em parte', '#FF9F0A' }
                'Sem winget' { 'Precisa do winget', '#9A9AA0' }
                default      { $null, $null }
            }
            # Interruptor = "instalar". Tudo começa desligado; o que já está instalado fica travado (remover é na página Desinstalar)
            $l = New-KLinhaInterruptor $s.Nome $s.Descricao $s $false $etq $cor $primeira $fonte[$s.Fonte] '#9A9AA0' -TextoLigar 'Vai instalar'
            if ($s.Instalado) { $l.Interruptor.IsEnabled = $false }
            $l.Interruptor.Add_Checked({ Update-KBotaoProgramas })
            $l.Interruptor.Add_Unchecked({ Update-KBotaoProgramas })
            $primeira = $false
            [void]$sp.Children.Add($l.Linha)
            $script:KInterruptoresProgramas += $l.Interruptor
        }
        $cartao.Child = $sp
        [void]$u.PnlProgramas.Children.Add($cartao)
        $script:KGruposProgramas += @{ Titulo = $titulo; Cartao = $cartao; Painel = $sp }
    }
    $ni = @($Situacoes | Where-Object Instalado).Count
    $u.TxtResumoProgramas.Text = "$(@($Situacoes).Count) programas e runtimes  ·  $ni já instalado(s)  ·  marque o que instalar (pra remover, use Desinstalar)"
    foreach ($rb in 'RbPresetBasico', 'RbPresetMC', 'RbPresetTecnico', 'RbPresetDev', 'RbPresetRuntimes') { $u[$rb].IsChecked = $false }
    Set-KFiltroProgramas $u.TxtBuscaProg.Text
    Update-KBotaoProgramas
}

function Update-KBotaoProgramas {
    $n = @($script:KInterruptoresProgramas | Where-Object { $_.IsChecked -and $_.IsEnabled }).Count
    $script:KUi.BtnProgAplicar.Content = if ($n) { "Instalar ($n)" } else { 'Instalar selecionados' }
}

function Set-KFiltroProgramas([string]$Texto) {
    $t = $Texto.Trim()
    foreach ($g in $script:KGruposProgramas) {
        $vis = 0
        foreach ($linha in $g.Painel.Children) {
            $s = $linha.Child.Tag
            $ok = -not $t -or $s.Nome -like "*$t*" -or $s.Descricao -like "*$t*" -or $s.Pacote -like "*$t*"
            $linha.Visibility = if ($ok) { 'Visible' } else { 'Collapsed' }
            if ($ok) { $vis++ }
        }
        $g.Titulo.Visibility = if ($vis) { 'Visible' } else { 'Collapsed' }
        $g.Cartao.Visibility = $g.Titulo.Visibility
    }
}

function Start-KVerificarProgramas {
    Start-KTarefaGui 'Verificando programas' -Script { @(Get-KSituacaoProgramas) } -AoConcluir {
        param($res)
        if ($res) { Update-KListaProgramas @($res) }
    }
}

# ── Desinstalador ──
function Set-KFiltroApps {
    $u = $script:KUi
    $t = $u.TxtBuscaDes.Text.Trim()
    $u.DgApps.ItemsSource = @($script:KApps | Where-Object { -not $t -or $_.Nome -like "*$t*" -or $_.Editor -like "*$t*" })
}

function Start-KListarApps {
    Start-KTarefaGui 'Lendo programas instalados' -Script { @(Get-KAppsInstalados) } -AoConcluir {
        param($res)
        $script:KApps = @($res)
        $u = $script:KUi
        $u.TxtResumoDes.Text = "$($script:KApps.Count) programas instalados  ·  o desinstalador do programa roda primeiro, depois a caça aos rastros"
        Set-KFiltroApps
    }
}

function Show-KListaApps {
    $u = $script:KUi
    $u.PnlRastrosPagina.Visibility = 'Collapsed'
    $u.BrdApps.Visibility = 'Visible'
    $u.BtnDesinstalar.Visibility = 'Visible'
    Start-KListarApps
}

# Rastros de um ou vários programas (cada rastro traz .Programa)
function Show-KRastros {
    param($Rastros)
    $u = $script:KUi
    $Rastros = @($Rastros | Where-Object { $_ })
    if (-not $Rastros) {
        Write-KLog 'Nenhum rastro encontrado' OK
        Show-KListaApps
        return
    }
    $progs = @($Rastros | ForEach-Object Programa | Select-Object -Unique)
    $u.PnlRastros.Children.Clear()
    $script:KInterruptoresRastros = @()
    $primeira = $true
    foreach ($r in $Rastros | Sort-Object Programa, { if ($_.Confianca -eq 'Alta') { 0 } else { 1 } }, Tipo) {
        $desc = (@($(if ($progs.Count -gt 1) { $r.Programa }), $r.Tipo, $r.Tamanho, $r.Obs) | Where-Object { $_ }) -join '  ·  '
        $etq, $cor = if ($r.Confianca -eq 'Alta') { 'Rastro', '#30D158' } else { 'Revisar', '#FF9F0A' }
        $l = New-KLinhaInterruptor $r.Caminho $desc $r ($r.Confianca -eq 'Alta') $etq $cor $primeira
        $primeira = $false
        [void]$u.PnlRastros.Children.Add($l.Linha)
        $script:KInterruptoresRastros += $l.Interruptor
    }
    $total = Format-KTamanho (($Rastros | Measure-Object Bytes -Sum).Sum)
    $de = if ($progs.Count -eq 1) { $progs[0] } else { "$($progs.Count) programas" }
    $u.TxtRastrosTitulo.Text = "$($Rastros.Count) rastro(s) de $de$(if ($total) { "  ·  $total" })"
    $u.BrdApps.Visibility = 'Collapsed'
    $u.BtnDesinstalar.Visibility = 'Collapsed'
    $u.PnlRastrosPagina.Visibility = 'Visible'
}

# Procura rastros à força (programas cujo desinstalador falhou); junta com os já achados
function Start-KCacarRastros {
    param($Apps, [bool]$Forcado, $JaAchados)
    $script:KRastrosLote = @($JaAchados)
    Start-KTarefaGui 'Procurando rastros' -Parametros @{ Apps = @($Apps); Forcado = $Forcado } -Script {
        param($Apps, $Forcado)
        foreach ($a in $Apps) {
            foreach ($r in Get-KRastrosApp $a -Forcado:$Forcado) { $r | Add-Member Programa $a.Nome -Force -PassThru }
        }
    } -AoConcluir {
        param($res)
        Show-KRastros (@($script:KRastrosLote) + @($res))
    }
}

function Update-KBotaoDesinstalar {
    $n = @($script:KUi.DgApps.SelectedItems).Count
    $script:KUi.BtnDesinstalar.Content = if ($n -gt 1) { "Desinstalar ($n)" } else { 'Desinstalar' }
}

# ── Drivers ──
function Show-KDrivers {
    $u = $script:KUi
    $todos = [bool]$u.ChkDrvTodos.IsChecked
    $lista = @($script:KDrivers | Where-Object { $todos -or -not $_.Oculto } | Sort-Object Ordem, Classe, Nome)
    $u.DgDrivers.ItemsSource = $lista
    foreach ($i in $lista) { if ($i.Situacao -eq 'Atualização') { [void]$u.DgDrivers.SelectedItems.Add($i) } }
    $na = @($script:KDrivers | Where-Object Situacao -eq 'Atualização').Count
    $ns = @($script:KDrivers | Where-Object Situacao -eq 'Sem driver').Count
    $ne = @($script:KDrivers | Where-Object Situacao -eq 'Com erro').Count
    $u.TxtResumoDrv.Text = if ($script:KDrvOnline) {
        "$na atualização(ões)  ·  $ns sem driver  ·  $ne com erro  ·  fontes: Windows Update e NVIDIA"
    } else {
        "$(@($lista).Count) dispositivo(s)$(if ($ns + $ne) { "  ·  $ns sem driver, $ne com erro" })  ·  clique em Procurar atualizações (leva 1 a 3 min)"
    }
    Update-KBotaoDrivers
}

function Update-KBotaoDrivers {
    $n = @($script:KUi.DgDrivers.SelectedItems | Where-Object { $_.Situacao -eq 'Atualização' }).Count
    $script:KUi.BtnDrvInstalar.Content = if ($n) { "Atualizar ($n)" } else { 'Atualizar selecionados' }
}

function Start-KListarDrivers([bool]$Online) {
    if ($script:KTarefa) { return }
    $script:KTarefaOnline = $Online
    Start-KTarefaGui $(if ($Online) { 'Procurando drivers' } else { 'Lendo dispositivos' }) -Parametros @{ Online = $Online } -Script {
        param($Online)
        if ($Online) { Write-KLog 'Drivers' Titulo }
        @(Get-KSituacaoDrivers -Online:$Online -Todos)
    } -AoConcluir {
        param($res)
        $script:KDrivers = @($res | Where-Object { $_ -and $_.PSObject.Properties['Situacao'] })
        $script:KDrvOnline = [bool]$script:KTarefaOnline
        Show-KDrivers
    }
}

function Update-KCartaoFabricante {
    $u = $script:KUi
    $m = Get-KFabricante
    $script:KFabricante = $m
    $u.TxtDrvMaquina.Text = "$($m.Marca) $($m.Modelo)"
    $serie = if ($m.Serial) { "Série $($m.Serial)" } else { 'Sem número de série' }
    $u.TxtDrvMaquinaSub.Text = "$serie  ·  " + $(
        if ($m.Ferramenta -and $m.Ferramenta.Auto) { "$($m.Ferramenta.Nome) (oficial) instala e atualiza drivers e BIOS da marca sozinho" }
        elseif ($m.Ferramenta) { "$($m.Ferramenta.Nome) (oficial, Microsoft Store) atualiza os drivers da marca" }
        elseif ($m.Montado) { 'PC montado: drivers da placa-mãe no site do fabricante dela' }
        elseif ($m.Pagina) { "A $($m.Marca) não tem atualizador automático: a página de suporte abre com o número de série copiado" }
        else { 'Fabricante sem página conhecida: Windows Update e NVIDIA cobrem a maior parte' })
    $u.BtnDrvFabricante.Visibility = if ($m.Ferramenta) { 'Visible' } else { 'Collapsed' }
    if ($m.Ferramenta) { $u.BtnDrvFabricante.Content = $(if ($m.Ferramenta.Auto) { "Rodar $($m.Ferramenta.Nome)" } else { "Instalar $($m.Ferramenta.Nome)" }) }
    $u.BtnDrvPagina.Visibility = if ($m.Pagina) { 'Visible' } else { 'Collapsed' }
}

# ── Impressoras ──
# Gerenciador: cada impressora do PC com renomear, página de teste, padrão, driver e remover
function Update-KListaImpressorasInstaladas {
    $u = $script:KUi
    $u.PnlImpInstaladas.Children.Clear()
    $lista = @(Get-KImpressorasInstaladas | Where-Object { -not $_.Virtual })
    if (-not $lista) {
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = 'Nenhuma impressora configurada neste PC.'; $t.Foreground = $u.Janela.FindResource('Texto2'); $t.Margin = '0,10'
        [void]$u.PnlImpInstaladas.Children.Add($t)
        return
    }
    $primeira = $true
    foreach ($i in $lista) {
        $g = New-Object Windows.Controls.Grid
        [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = '*' }))
        [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
        $sp = New-Object Windows.Controls.StackPanel
        $l1 = New-Object Windows.Controls.WrapPanel
        $nome = New-Object Windows.Controls.TextBlock; $nome.Text = $i.Nome; $nome.FontWeight = 'SemiBold'; $nome.Margin = '0,0,8,2'
        $caixa = New-Object Windows.Controls.TextBox; $caixa.MinWidth = 260; $caixa.Margin = '0,0,8,2'; $caixa.Visibility = 'Collapsed'
        [void]$l1.Children.Add($nome); [void]$l1.Children.Add($caixa)
        if ($i.Padrao) { [void]$l1.Children.Add((New-KPilula 'Padrão' '#30D158')) }
        if ($i.Atualizacao) { [void]$l1.Children.Add((New-KPilula "Driver novo: $($i.VersaoNova)" '#FF9F0A')) }
        [void]$l1.Children.Add((New-KPilula $i.Tipo '#9A9AA0'))
        $onde = switch ($i.Tipo) {
            'WSD'      { 'achada pelo Windows (WSD)' }
            'EpsonNet' { "porta EpsonNet → $($i.Host)" }
            'TCP/IP'   { "porta TCP/IP → $($i.Host)" }
            'USB'      { 'cabo USB' }
            default    { $i.Porta }
        }
        $t2 = New-Object Windows.Controls.TextBlock
        $t2.Text = "$($i.Driver)$(if ($i.DriverVersao) { " $($i.DriverVersao)" })  ·  $onde$(if ($i.Mac) { "  ·  MAC $($i.Mac)" })"
        $t2.TextWrapping = 'Wrap'; $t2.FontSize = 13; $t2.Margin = '0,3,0,0'; $t2.Foreground = $u.Janela.FindResource('Texto2')
        [void]$sp.Children.Add($l1); [void]$sp.Children.Add($t2)
        [void]$g.Children.Add($sp)

        $acoes = New-Object Windows.Controls.StackPanel
        $acoes.Orientation = 'Horizontal'; $acoes.VerticalAlignment = 'Center'; $acoes.Margin = '12,0,0,0'
        [Windows.Controls.Grid]::SetColumn($acoes, 1)
        $d = @{ Imp = $i; Nome = $nome; Caixa = $caixa }
        $oficial = Get-KModeloPorNome $i.Nome
        $botoes = @()
        $botoes += , @('Renomear', 'Muda o nome que aparece na lista de impressoras', { Invoke-KRenomearLinha $args[0].Tag })
        $botoes += , @('Teste', 'Imprime a página de teste do Windows', { $n = $args[0].Tag.Imp.Nome; Start-KTarefaGui 'Página de teste' -Parametros @{ Nome = $n } -Script { param($Nome) Send-KPaginaTeste $Nome } })
        if (-not $i.Padrao) { $botoes += , @('Tornar padrão', 'Vira a impressora padrão deste usuário', { Set-KImpressoraPadrao $args[0].Tag.Imp.Nome | Out-Null; Update-KListaImpressorasInstaladas }) }
        if ($i.Atualizacao) {
            $botoes += , @('Atualizar driver', "Baixa o driver $($i.VersaoNova) do site do fabricante", { Start-KDriverLinha $args[0].Tag.Imp $args[0].Tag.Imp.Driver $true })
        } elseif ($oficial -and $i.Driver -ne $oficial.Modelo) {
            $botoes += , @('Driver oficial', "Troca o driver ($($i.Driver)) pelo oficial $($oficial.Modelo)", { Start-KDriverLinha $args[0].Tag.Imp (Get-KModeloPorNome $args[0].Tag.Imp.Nome).Modelo $false })
        }
        $botoes += , @('Remover', 'Remove a impressora (e, se quiser, o driver)', { Remove-KImpressoraLinha $args[0].Tag.Imp })
        foreach ($b in $botoes) {
            $bt = New-Object Windows.Controls.Button
            $bt.Content = $b[0]; $bt.ToolTip = $b[1]; $bt.Tag = $d
            $bt.Style = $u.Janela.FindResource('BtnMini')
            $bt.Add_Click($b[2])
            [void]$acoes.Children.Add($bt)
            if ($b[0] -eq 'Renomear') { $d.Botao = $bt }
        }
        [void]$g.Children.Add($acoes)
        $caixa.Tag = $d
        $caixa.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq 'Return') { Invoke-KRenomearLinha $s.Tag }
            if ($e.Key -eq 'Escape') { Update-KListaImpressorasInstaladas }
        })
        [void]$u.PnlImpInstaladas.Children.Add((New-KLinhaSimples $g $primeira))
        $primeira = $false
    }
}

function Invoke-KRenomearLinha($d) {
    if ($d.Caixa.Visibility -ne 'Visible') {
        $d.Caixa.Text = $d.Imp.Nome
        $d.Nome.Visibility = 'Collapsed'; $d.Caixa.Visibility = 'Visible'
        $d.Botao.Content = 'Salvar'
        [void]$d.Caixa.Focus(); $d.Caixa.SelectAll()
        return
    }
    $novo = $d.Caixa.Text.Trim()
    if ($novo -and $novo -ne $d.Imp.Nome) {
        if (Get-Printer -Name $novo -ErrorAction SilentlyContinue) { $script:KUi.TxtStatus.Text = "Já existe uma impressora chamada $novo"; return }
        Rename-KImpressora $d.Imp.Nome $novo | Out-Null
    }
    Update-KListaImpressorasInstaladas
}

function Start-KDriverLinha($Imp, [string]$Modelo, [bool]$Forcar) {
    Start-KTarefaGui "Driver de $($Imp.Nome)" -Parametros @{ Nome = $Imp.Nome; Modelo = $Modelo; Forcar = $Forcar } -Script {
        param($Nome, $Modelo, $Forcar)
        Write-KLog "Driver: $Nome" Titulo
        Set-KDriverImpressora -Nome $Nome -Modelo $Modelo -Forcar:$Forcar | Out-Null
    } -AoConcluir { Update-KListaImpressorasInstaladas }
}

function Remove-KImpressoraLinha($Imp) {
    $outras = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.DriverName -eq $Imp.Driver -and $_.Name -ne $Imp.Nome })
    $obsDriver = if ($outras) { "o driver fica, porque $($outras.Count) outra(s) impressora(s) usam ele" } else { "também tira o driver $($Imp.Driver)" }
    $msg = "Remover $($Imp.Nome)?`n`nSim  =  remove a impressora e o driver ($obsDriver)`nNão  =  remove só a impressora (o driver fica, pra adicionar de novo rapidinho)`nCancelar  =  não mexe em nada"
    $r = "$([Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Remover impressora', 'YesNoCancel', 'Question'))"
    if ($r -eq 'Cancel') { return }
    Start-KTarefaGui "Removendo $($Imp.Nome)" -Parametros @{ Nome = $Imp.Nome; Driver = ($r -eq 'Yes') } -Script {
        param($Nome, $Driver)
        Remove-KImpressora -Nome $Nome -Driver:$Driver
    } -AoConcluir { Update-KListaImpressorasInstaladas }
}

# Linha de impressora achada: interruptor + nome editável + detalhes
function New-KLinhaImpressora($Imp, [bool]$Primeira) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Style = $script:KUi.Janela.FindResource('LinhaLista')
    $cb.Tag = $Imp
    $cb.IsChecked = -not $Imp.Instalada
    $sp = New-Object Windows.Controls.StackPanel
    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = $Imp.Nome; $tb.MinWidth = 260; $tb.HorizontalAlignment = 'Left'; $tb.Margin = '0,0,0,4'
    $tb.ToolTip = 'Nome que vai aparecer na lista de impressoras'
    [void]$sp.Children.Add($tb)
    $t2 = New-Object Windows.Controls.TextBlock
    $t2.TextWrapping = 'Wrap'; $t2.FontSize = 13; $t2.Foreground = $script:KUi.Janela.FindResource('Texto2')
    $t2.Text = "$($Imp.Modelo)  ·  $($Imp.Ip)$(if ($Imp.HostFixo) { "  ·  nome na rede $($Imp.Host)" } else { '  ·  sem nome na rede: vai pelo IP' })  ·  driver: $($Imp.Driver)" +
               $(if ($Imp.NomeWsd -and $Imp.NomeWsd -ne $Imp.Modelo) { "`nNo Windows aparece como: $($Imp.NomeWsd)" } else { '' }) +
               $(if ($Imp.Instalada) { "`nJá configurada: $($Imp.InstaladaComo)" } else { '' })
    [void]$sp.Children.Add($t2)
    $cb.Content = $sp
    $linha = New-Object Windows.Controls.Border
    if (-not $Primeira) { $linha.BorderBrush = $script:KUi.Janela.FindResource('Linha'); $linha.BorderThickness = '0,1,0,0' }
    $linha.Child = $cb
    @{ Linha = $linha; Interruptor = $cb; Nome = $tb }
}

function Show-KImpressorasAchadas($Achadas) {
    $u = $script:KUi
    $u.PnlImpAchadas.Children.Clear()
    $script:KLinhasImp = @()
    $Achadas = @($Achadas | Where-Object { $_ })
    if (-not $Achadas) {
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = 'Nenhuma impressora encontrada. Confira se este PC está na mesma rede (Wi-Fi) das impressoras e se elas estão ligadas.'
        $t.TextWrapping = 'Wrap'; $t.Foreground = $u.Janela.FindResource('Texto2'); $t.Margin = '0,10'
        [void]$u.PnlImpAchadas.Children.Add($t)
        return
    }
    $p = $true
    foreach ($a in $Achadas) { $l = New-KLinhaImpressora $a $p; $p = $false; [void]$u.PnlImpAchadas.Children.Add($l.Linha); $script:KLinhasImp += $l }
    $u.TxtResumoImp.Text = "$($Achadas.Count) impressora(s) na rede  ·  $(@($Achadas | Where-Object Instalada).Count) já configurada(s) neste PC"
}

# ── Perfis ──
# Lista de seleção agrupada (ajustes/programas do editor de perfil): constrói uma vez, depois só marca
function New-KListaSelecao($Painel, $Itens, [string]$Grupo, [scriptblock]$Descricao) {
    $Painel.Children.Clear()
    $cbs = @{}
    foreach ($g in $Itens | Group-Object $Grupo) {
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = $g.Name.ToUpper(); $t.Style = $script:KUi.Janela.FindResource('Secao')
        [void]$Painel.Children.Add($t)
        $c = New-Object Windows.Controls.Border
        $c.Style = $script:KUi.Janela.FindResource('Cartao'); $c.Padding = '16,4'; $c.Margin = '0,0,0,18'
        $sp = New-Object Windows.Controls.StackPanel
        $p = $true
        foreach ($i in $g.Group) {
            $e = & $Descricao $i
            $l = New-KLinhaInterruptor $i.Nome $i.Descricao $i.Id $false $e[0] $e[1] $p
            $p = $false
            [void]$sp.Children.Add($l.Linha)
            $cbs[$i.Id] = $l.Interruptor
            $l.Interruptor.Add_Click({ Update-KResumoEditor })
        }
        $c.Child = $sp
        [void]$Painel.Children.Add($c)
    }
    $cbs
}

function Initialize-KEditorPerfil {
    if ($script:KEditor) { return }
    $u = $script:KUi
    $corNivel = @{ 'Seguro' = '#30D158'; 'Recomendado' = '#0A84FF'; 'Agressivo' = '#FF453A'; 'Preferência' = '#BF5AF2' }
    $script:KEditor = @{
        Tweaks    = New-KListaSelecao $u.PnlPfAjustes @(Get-KTweaks) 'Categoria' { param($i) @($i.Nivel, $corNivel[$i.Nivel]) }
        Programas = New-KListaSelecao $u.PnlPfProgramas @(Get-KProgramas) 'Categoria' { param($i) @($null, $null) }
    }
}

# Seção Impressoras do editor: drivers pra deixar prontos + impressoras lembradas (pelo MAC)
function Update-KEditorImpressoras($Perfil) {
    $u = $script:KUi
    $pn = $u.PnlPfImpressoras
    $pn.Children.Clear()
    $sec = { param($t) $x = New-Object Windows.Controls.TextBlock; $x.Text = $t; $x.Style = $u.Janela.FindResource('Secao'); [void]$pn.Children.Add($x) }
    $cartao = { $c = New-Object Windows.Controls.Border; $c.Style = $u.Janela.FindResource('Cartao'); $c.Padding = '16,4'; $c.Margin = '0,0,0,18'
                $s = New-Object Windows.Controls.StackPanel; $c.Child = $s; [void]$pn.Children.Add($c); $s }
    & $sec 'DRIVERS OFICIAIS (MESMO SEM A IMPRESSORA NA REDE)'
    $sp = & $cartao
    $script:KEditorDrivers = @{}
    $p = $true
    foreach ($m in Get-KModelosImpressora) {
        $l = New-KLinhaInterruptor $m.Nome "Driver + Epson Scan 2 do site da Epson ($($m.Modelo))" $m.Id (@($Perfil.Impressoras.Drivers) -contains $m.Id) -Primeira $p
        $p = $false; [void]$sp.Children.Add($l.Linha); $script:KEditorDrivers[$m.Id] = $l.Interruptor
    }
    $l = New-KLinhaInterruptor 'Instalar o scanner junto' 'Epson Scan 2 pras multifuncionais.' 'scanner' ([bool]$Perfil.Impressoras.Scanner)
    [void]$sp.Children.Add($l.Linha); $script:KEditorScanner = $l.Interruptor

    & $sec 'IMPRESSORAS DA REDE (ADICIONADAS SOZINHAS AO APLICAR)'
    $sp = & $cartao
    $script:KEditorLembradas = @()
    $p = $true
    foreach ($i in @($Perfil.Impressoras.Lembradas)) {
        $l = New-KLinhaInterruptor $i.Nome "$($i.Modelo)  ·  MAC $($i.Mac)" $i $true -Primeira $p
        $p = $false; [void]$sp.Children.Add($l.Linha); $script:KEditorLembradas += $l.Interruptor
    }
    $t = New-Object Windows.Controls.TextBlock
    $t.TextWrapping = 'Wrap'; $t.FontSize = 13; $t.Foreground = $u.Janela.FindResource('Texto2'); $t.Margin = '0,10'
    $t.Text = if ($p) { 'Nenhuma ainda. Configure as impressoras na aba Impressoras e clique em "Copiar deste PC" aqui.' }
              else { 'Reconhecidas pelo MAC: mudar de IP não atrapalha. Desligue pra tirar do perfil.' }
    [void]$sp.Children.Add($t)
}

function Show-KPerfil($Perfil) {
    Initialize-KEditorPerfil
    $u = $script:KUi
    $script:KPerfilAtual = $Perfil
    $u.TxtPerfilNome.Text = $Perfil.Nome
    $u.TxtPerfilDesc.Text = $Perfil.Descricao
    foreach ($k in $script:KEditor.Tweaks.Keys) { $script:KEditor.Tweaks[$k].IsChecked = @($Perfil.Tweaks) -contains $k }
    foreach ($k in $script:KEditor.Programas.Keys) { $script:KEditor.Programas[$k].IsChecked = @($Perfil.Programas) -contains $k }
    Update-KEditorImpressoras $Perfil
    $rb = @{ Nenhuma = 'RbPfManNenhuma'; Rapida = 'RbPfManRapida'; Completa = 'RbPfManCompleta' }[$Perfil.Manutencao]
    $u[$(if ($rb) { $rb } else { 'RbPfManNenhuma' })].IsChecked = $true
    $u.ChkPfContasNovas.IsChecked = [bool]$Perfil.ContasNovas
    $u.ChkPfDrivers.IsChecked = [bool]$Perfil.AtualizarDrivers
    $u.BtnPerfilExcluir.Content = if ($Perfil.Padrao) { 'Restaurar padrão' } else { 'Excluir' }
    $u.BtnPerfilExcluir.IsEnabled = -not $Perfil.Padrao -or $Perfil.Modificado
    Update-KResumoEditor
}

# Estado do editor → objeto de perfil
function Get-KPerfilDoEditor {
    $u = $script:KUi
    $a = $script:KPerfilAtual
    $man = foreach ($r in 'RbPfManNenhuma', 'RbPfManRapida', 'RbPfManCompleta') { if ($u[$r].IsChecked) { $u[$r].Tag } }
    $p = New-KPerfil -Id $a.Id -Nome $u.TxtPerfilNome.Text.Trim() -Descricao $u.TxtPerfilDesc.Text.Trim() `
        -Tweaks @($script:KEditor.Tweaks.Keys | Where-Object { $script:KEditor.Tweaks[$_].IsChecked }) `
        -Programas @($script:KEditor.Programas.Keys | Where-Object { $script:KEditor.Programas[$_].IsChecked }) `
        -Drivers @($script:KEditorDrivers.Keys | Where-Object { $script:KEditorDrivers[$_].IsChecked }) `
        -Scanner ([bool]$script:KEditorScanner.IsChecked) `
        -Lembradas @($script:KEditorLembradas | Where-Object IsChecked | ForEach-Object Tag) `
        -Manutencao "$(@($man)[0])" -ContasNovas ([bool]$u.ChkPfContasNovas.IsChecked) `
        -AtualizarDrivers ([bool]$u.ChkPfDrivers.IsChecked)
    $p.Padrao = $a.Padrao
    $p
}

function Update-KResumoEditor {
    if (-not $script:KPerfilAtual -or -not $script:KEditorDrivers) { return }
    $script:KUi.TxtPerfilResumo.Text = Get-KResumoPerfil (Get-KPerfilDoEditor)
}

function Update-KListaPerfis([string]$Selecionar) {
    $u = $script:KUi
    $u.PnlListaPerfis.Children.Clear()
    $script:KPerfis = @(Get-KPerfis)
    $alvo = $null
    foreach ($p in $script:KPerfis) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $u.Janela.FindResource('Nav'); $rb.GroupName = 'ListaPerfis'
        $rb.Tag = [string][char]0xE77B
        $rb.Content = "$($p.Nome)$(if ($p.Modificado) { ' •' })"
        $rb.ToolTip = if ($p.Modificado) { 'Perfil padrão com alterações suas' } elseif ($p.Padrao) { 'Perfil padrão' } else { 'Criado por você' }
        $rb.DataContext = $p
        $rb.Add_Checked({ param($s) Show-KPerfil $s.DataContext })
        [void]$u.PnlListaPerfis.Children.Add($rb)
        if ($p.Id -eq $Selecionar -or (-not $Selecionar -and -not $alvo)) { $alvo = $rb }
    }
    if ($alvo) { $alvo.IsChecked = $true }   # o Checked mostra o perfil
}

# Cartão da bateria Acer (limite de 80% e calibração pela BIOS). Some em PC que não é Acer.
function Update-KCartaoBateriaAcer {
    $u = $script:KUi
    $s = Get-KLimiteCarga
    if (-not $s -or -not $s.TemLimite) { $u.PnlBateriaAcer.Visibility = 'Collapsed'; return }
    $u.PnlBateriaAcer.Visibility = 'Visible'
    $script:KAtualizandoAcer = $true
    $u.ChkLimite80.IsChecked = $s.LimiteAtivo
    $script:KAtualizandoAcer = $false
    $u.BtnCalibrar.Visibility = if ($s.TemCalibracao) { 'Visible' } else { 'Collapsed' }
    if ($s.Calibrando) {
        $ini = (Get-KEstadoBateriaAcer).Inicio
        $u.BtnCalibrar.Content = 'Encerrar'
        $u.TxtCalibracao.Text = "Calibrando$(if ($ini) { " desde $(([datetime]$ini).ToString('dd/MM HH:mm'))" }). Deixe na tomada; encerre quando a carga voltar a 100% depois de descer."
        $u.ChkLimite80.IsEnabled = $false
    } else {
        $u.BtnCalibrar.Content = 'Calibrar'
        $u.TxtCalibracao.Text = 'Corrige a % que cai rápido demais e a previsão de tempo maluca. Na tomada, leva algumas horas.'
        $u.ChkLimite80.IsEnabled = $true
    }
}

function Set-KTituloEscuro($Janela) {
    # Barra de título escura (Windows 10 20H1+/11) e cor da legenda igual ao fundo (Windows 11)
    try {
        if (-not ('KBench.Dwm' -as [type])) {
            Add-Type -Namespace KBench -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);'
        }
        $h = (New-Object Windows.Interop.WindowInteropHelper $Janela).Handle
        $v = 1;          [void][KBench.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)   # modo escuro
        $c = 0x0020201E; [void][KBench.Dwm]::DwmSetWindowAttribute($h, 35, [ref]$c, 4)   # legenda #1E2020 (BGR)
    } catch {}
}

function Show-KGui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    $KB.LogSink = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    Start-KLog 'gui' | Out-Null

    [xml]$xml = $KXaml
    $janela = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xml))
    $script:KUi = @{ Janela = $janela }
    foreach ($n in $xml.SelectNodes('//*[@Name]')) {
        $nome = $n.GetAttribute('Name')
        $script:KUi[$nome] = $janela.FindName($nome)
    }
    $ui = $script:KUi
    $janela.Add_SourceInitialized({ Set-KTituloEscuro $script:KUi.Janela })

    $win = Get-KWindows
    $ui.TxtMaquina.Text = "$env:COMPUTERNAME`n$($win.Nome) $($win.Versao)"
    $ui.TxtVersao.Text = "K-Bench $($KB.Versao)$(if (-not (Test-KAdmin)) { '  ·  sem admin' })"

    # ── Navegação ──
    $paginas = @{ NavDiagnostico = 'PgDiagnostico'; NavManutencao = 'PgManutencao'; NavReparos = 'PgReparos'; NavBateria = 'PgBateria'; NavTweaks = 'PgTweaks'; NavProgramas = 'PgProgramas'; NavDesinstalar = 'PgDesinstalar'; NavDrivers = 'PgDrivers'; NavImpressoras = 'PgImpressoras'; NavPerfis = 'PgPerfis' }
    $script:KPaginas = $paginas
    foreach ($nav in $paginas.Keys) {
        $ui[$nav].Add_Checked({
            param($s)
            foreach ($p in $script:KPaginas.GetEnumerator()) {
                $script:KUi[$p.Value].Visibility = if ($p.Key -eq $s.Name) { 'Visible' } else { 'Collapsed' }
            }
        })
    }
    if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) { $ui.NavBateria.Content = 'Energia' }

    # ── Manutenção ──
    $primeira = $true
    foreach ($e in Get-KEtapasManutencao) {
        $l = New-KLinhaInterruptor $e.Nome $e.Descricao $e $e.Rapida -Primeira $primeira
        $primeira = $false
        [void]$ui.PnlEtapas.Children.Add($l.Linha)
    }
    $aplicarModo = {
        $completa = [bool]$script:KUi.RbCompleta.IsChecked
        foreach ($linha in $script:KUi.PnlEtapas.Children) {
            $cb = $linha.Child
            $cb.IsChecked = if ($completa) { $cb.Tag.Completa } else { $cb.Tag.Rapida }
        }
        $script:KUi.ChkAgendarDisco.IsChecked = $completa
    }
    $ui.RbRapida.Add_Checked($aplicarModo)
    $ui.RbCompleta.Add_Checked($aplicarModo)

    $ui.BtnFonte.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Imagem do Windows (*.iso;*.wim;*.esd)|*.iso;*.wim;*.esd|Todos (*.*)|*.*'
        if ($dlg.ShowDialog()) { $script:KUi.TxtFonte.Text = $dlg.FileName }
    })

    $ui.BtnManutencao.Add_Click({
        $u = $script:KUi
        $etapas = @($u.PnlEtapas.Children | ForEach-Object Child | Where-Object IsChecked | ForEach-Object { $_.Tag.Id })
        if (-not $etapas) { $u.TxtStatus.Text = 'Ative ao menos uma etapa'; return }
        $modo = if ($u.RbCompleta.IsChecked) { 'Completa' } else { 'Rapida' }
        Start-KTarefaGui "Manutenção $(if ($modo -eq 'Rapida') { 'rápida' } else { 'completa' })" -Parametros @{
            Modo = $modo; Etapas = $etapas; FonteISO = $u.TxtFonte.Text.Trim(); Agendar = [bool]$u.ChkAgendarDisco.IsChecked
        } -Script {
            param($Modo, $Etapas, $FonteISO, $Agendar)
            Invoke-KManutencao -Modo $Modo -Etapas $Etapas -FonteISO $FonteISO -AgendarReparoDisco:$Agendar
        }
    })

    # ── Reparos ──
    $primeira = $true
    foreach ($r in Get-KReparos) {
        $l = New-KLinhaInterruptor $r.Nome $r.Descricao $r.Id $false $(if ($r.Reinicio) { 'Reinício' }) '#FF9F0A' $primeira
        $primeira = $false
        [void]$ui.PnlReparos.Children.Add($l.Linha)
    }
    $ui.BtnReparos.Add_Click({
        $ids = @($script:KUi.PnlReparos.Children | ForEach-Object Child | Where-Object IsChecked | ForEach-Object Tag)
        if (-not $ids) { $script:KUi.TxtStatus.Text = 'Ative ao menos um reparo'; return }
        Start-KTarefaGui 'Reparos' -Parametros @{ Ids = $ids } -Script {
            param($Ids)
            foreach ($i in $Ids) { Invoke-KReparo $i }
            if (Test-KReinicioPendente) { Write-KLog 'Reinicie o PC pra concluir.' Aviso }
        } -AoConcluir {
            foreach ($linha in $script:KUi.PnlReparos.Children) { $linha.Child.IsChecked = $false }
        }
    })

    # ── Diagnóstico ──
    $ui.BtnDiagnostico.Add_Click({
        $script:KUi.DgAchados.ItemsSource = $null
        Start-KTarefaGui 'Diagnóstico' -Script {
            $a = Get-KDiagnostico
            [pscustomobject]@{ Achados = $a; Relatorio = (Export-KRelatorioHtml -Achados $a) }
        } -AoConcluir {
            param($res)
            $r = @($res)[0]
            if (-not $r) { return }
            $ordem = @{ Critico = 0; Atencao = 1; Info = 2; OK = 3 }
            $script:KUi.DgAchados.ItemsSource = @($r.Achados | Sort-Object { $ordem[$_.Status] })
            Set-KContagem $r.Achados
            $script:KRelatorio = $r.Relatorio
            $script:KUi.BtnRelatorio.IsEnabled = [bool]$r.Relatorio
        }
    })
    $ui.BtnRelatorio.Add_Click({ if ($script:KRelatorio) { Start-Process $script:KRelatorio } })

    # ── Otimizar ──
    $ui.NavTweaks.Add_Checked({ if (-not $script:KTweaksVerificados) { $script:KTweaksVerificados = $true; Start-KVerificarTweaks } })
    $ui.BtnTweaksVerificar.Add_Click({ Start-KVerificarTweaks })
    $marcarNivel = {
        param($s)
        $ordem = @{ 'Seguro' = 1; 'Recomendado' = 2; 'Agressivo' = 3 }
        $ate = $ordem[$s.Content]
        foreach ($cb in $script:KInterruptoresTweaks) {
            $t = $cb.Tag
            if (-not $cb.IsEnabled -or $t.Nivel -eq 'Preferência' -or -not $t.Pendente) { continue }
            $cb.IsChecked = $ordem[$t.Nivel] -le $ate
        }
    }
    $ui.RbNivelSeguro.Add_Click($marcarNivel)
    $ui.RbNivelRecomendado.Add_Click($marcarNivel)
    $ui.RbNivelAgressivo.Add_Click($marcarNivel)
    $ui.BtnTweaksAplicar.Add_Click({
        $aplicar = @(); $desfazer = @(); $semDesfazer = @()
        foreach ($cb in $script:KInterruptoresTweaks) {
            $t = $cb.Tag
            if ($cb.IsChecked -and $t.Pendente) { $aplicar += $t.Id }
            if (-not $cb.IsChecked -and $t.PeloKBench) { $desfazer += $t.Id }
            if (-not $cb.IsChecked -and -not $t.PeloKBench -and $t.Situacao -eq 'Já está assim') { $semDesfazer += $t.Nome }
        }
        if ($semDesfazer) { Write-KLog "Não foram aplicados pelo K-Bench, então não há valor anterior pra voltar: $($semDesfazer -join ', ')" Aviso }
        if (-not ($aplicar + $desfazer)) { $script:KUi.TxtStatus.Text = 'Nenhuma alteração pra aplicar'; return }
        $agressivos = @($script:KInterruptoresTweaks | Where-Object { $_.IsChecked -and $_.Tag.Pendente -and $_.Tag.Nivel -eq 'Agressivo' } | ForEach-Object { $_.Tag.Nome })
        if ($agressivos) {
            $ok = [Windows.MessageBox]::Show($script:KUi.Janela, "Ajustes agressivos marcados:`n`n- $($agressivos -join "`n- ")`n`nContinuar?", 'Otimizar', 'YesNo', 'Warning')
            if ("$ok" -ne 'Yes') { return }
        }
        Start-KTarefaGui 'Otimizações' -Parametros @{ Aplicar = $aplicar; Desfazer = $desfazer; Todos = [bool]$script:KUi.ChkContasNovas.IsChecked } -Script {
            param($Aplicar, $Desfazer, $Todos)
            Write-KLog 'Otimizações' Titulo
            if ($Aplicar) { New-KPontoRestauracao 'K-Bench - otimizações' | Out-Null }
            Invoke-KTweaks -Aplicar $Aplicar -Desfazer $Desfazer -TodosUsuarios $Todos
            @(Get-KSituacaoTweaks)
        } -AoConcluir {
            param($res)
            if ($res) { Update-KListaTweaks @($res) }
        }
    })

    # ── Programas ──
    $ui.NavProgramas.Add_Checked({ if (-not $script:KProgramasVerificados) { $script:KProgramasVerificados = $true; Start-KVerificarProgramas } })
    $ui.BtnProgVerificar.Add_Click({ Start-KVerificarProgramas })
    $ui.TxtBuscaProg.Add_TextChanged({
        $t = $script:KUi.TxtBuscaProg.Text
        $script:KUi.TxtBuscaDica.Visibility = if ($t) { 'Collapsed' } else { 'Visible' }
        if ($script:KGruposProgramas) { Set-KFiltroProgramas $t }
    })
    $marcarPreset = {
        param($rb)
        foreach ($cb in $script:KInterruptoresProgramas) {
            $s = $cb.Tag
            if ($s.Instalado -or -not $cb.IsEnabled) { continue }
            $cb.IsChecked = $s.Presets -contains $rb.Tag
        }
    }
    foreach ($rb in 'RbPresetBasico', 'RbPresetMC', 'RbPresetTecnico', 'RbPresetDev', 'RbPresetRuntimes') { $ui[$rb].Add_Click($marcarPreset) }
    $ui.BtnProgMarcar.Add_Click({
        # Só o que está aparecendo (respeita o filtro)
        foreach ($cb in $script:KInterruptoresProgramas) { if ($cb.IsEnabled -and $cb.Parent.Visibility -eq 'Visible') { $cb.IsChecked = $true } }
    })
    $ui.BtnProgDesmarcar.Add_Click({
        foreach ($cb in $script:KInterruptoresProgramas) { $cb.IsChecked = $false }
        foreach ($rb in 'RbPresetBasico', 'RbPresetMC', 'RbPresetTecnico', 'RbPresetDev', 'RbPresetRuntimes') { $script:KUi[$rb].IsChecked = $false }
    })
    $ui.BtnProgAplicar.Add_Click({
        $instalar = @($script:KInterruptoresProgramas | Where-Object { $_.IsChecked -and $_.IsEnabled } | ForEach-Object Tag)
        if (-not $instalar) { $script:KUi.TxtStatus.Text = 'Marque ao menos um programa'; return }
        $msg = "Instalar $($instalar.Count) programa(s)?`n`n- $(($instalar | Select-Object -First 15 | ForEach-Object Nome) -join "`n- ")$(if ($instalar.Count -gt 15) { "`n- e mais $($instalar.Count - 15)" })"
        if ($instalar | Where-Object Fonte -eq 'odt') { $msg += "`n`nO Microsoft 365 baixa uns 3 GB e leva de 10 a 30 min." }
        if ("$([Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Programas', 'YesNo', 'Question'))" -ne 'Yes') { return }
        Start-KTarefaGui 'Instalando programas' -Parametros @{ Instalar = @($instalar | ForEach-Object Id) } -Script {
            param($Instalar)
            Write-KLog 'Programas' Titulo
            Invoke-KProgramas -Instalar $Instalar
            @(Get-KSituacaoProgramas)
        } -AoConcluir {
            param($res)
            if ($res) { Update-KListaProgramas @($res) }
        }
    })
    $ui.BtnProgAtualizar.Add_Click({
        Start-KTarefaGui 'Atualizando programas' -Script {
            Write-KLog 'Atualizar programas' Titulo
            Update-KProgramas
        }
    })

    # ── Desinstalar ──
    $ui.NavDesinstalar.Add_Checked({ if (-not $script:KApps) { Start-KListarApps } })
    $ui.BtnDesAtualizar.Add_Click({ Show-KListaApps })
    $ui.TxtBuscaDes.Add_TextChanged({
        $script:KUi.TxtBuscaDesDica.Visibility = if ($script:KUi.TxtBuscaDes.Text) { 'Collapsed' } else { 'Visible' }
        if ($script:KApps) { Set-KFiltroApps }
    })
    $ui.DgApps.Add_SelectionChanged({ Update-KBotaoDesinstalar })
    $ui.BtnDesinstalar.Add_Click({
        $apps = @($script:KUi.DgApps.SelectedItems)
        if (-not $apps) { $script:KUi.TxtStatus.Text = 'Marque um ou mais programas na lista'; return }
        $msg = if ($apps.Count -eq 1) {
            $app = $apps[0]
            "Desinstalar $($app.Nome)?`n`n" + $(if ($app.Tipo -eq 'Store') { 'App da Microsoft Store: sai pelo próprio Windows.' }
                elseif ($app.Quebrado) { 'O desinstalador dele não existe mais. O K-Bench vai direto pros rastros.' }
                else { 'O desinstalador do programa roda primeiro. Depois o K-Bench mostra os rastros pra você escolher o que apagar.' })
        } else {
            "Desinstalar $($apps.Count) programas?`n`n- $(($apps | Select-Object -First 15 | ForEach-Object Nome) -join "`n- ")$(if ($apps.Count -gt 15) { "`n- e mais $($apps.Count - 15)" })`n`n" +
            'Um depois do outro, com um ponto de restauração antes. No fim, os rastros de todos aparecem juntos pra você escolher o que apagar.'
        }
        if ("$([Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Desinstalar', 'YesNo', 'Question'))" -ne 'Yes') { return }
        $titulo = if ($apps.Count -eq 1) { "Desinstalando $($apps[0].Nome)" } else { "Desinstalando $($apps.Count) programas" }
        Start-KTarefaGui $titulo -Parametros @{ Apps = $apps; Silencioso = [bool]$script:KUi.ChkDesSilencioso.IsChecked } -Script {
            param($Apps, $Silencioso)
            $nomes = if ($Apps.Count -eq 1) { $Apps[0].Nome } else { "$($Apps.Count) programas" }
            New-KPontoRestauracao "K-Bench - desinstalar $nomes" | Out-Null
            $n = 0
            foreach ($App in $Apps) {
                $n++
                Write-KLog "Desinstalar: $($App.Nome)$(if ($Apps.Count -gt 1) { "  ($n de $($Apps.Count))" })" Titulo
                $st = Invoke-KDesinstaladorApp $App $Silencioso
                $r = if ($st -ne 'AindaInstalado' -and $App.Tipo -ne 'Store') {
                    Write-KLog 'Procurando rastros' Info
                    foreach ($x in Get-KRastrosApp $App -Forcado:($st -eq 'SemDesinstalador')) { $x | Add-Member Programa $App.Nome -Force -PassThru }
                }
                [pscustomobject]@{ App = $App; Status = $st; Rastros = @($r) }
            }
        } -AoConcluir {
            param($res)
            $res = @($res | Where-Object { $_ -and $_.PSObject.Properties['Status'] })
            if (-not $res) { Show-KListaApps; return }
            $rastros = @($res | ForEach-Object { $_.Rastros } | Where-Object { $_ })
            $presos = @($res | Where-Object { $_.Status -eq 'AindaInstalado' -and $_.App.Tipo -ne 'Store' } | ForEach-Object App)
            if ($presos) {
                $q = [Windows.MessageBox]::Show($script:KUi.Janela, "Ainda aparece(m) instalado(s) (o desinstalador foi cancelado ou falhou):`n`n- $(($presos | ForEach-Object Nome) -join "`n- ")`n`nProcurar os rastros mesmo assim pra remover à força?", 'Desinstalar', 'YesNo', 'Warning')
                if ("$q" -eq 'Yes') { Start-KCacarRastros $presos $true $rastros; return }
            }
            Show-KRastros $rastros
        }
    })
    $ui.BtnRastrosManter.Add_Click({ Write-KLog 'Rastros mantidos' Info; Show-KListaApps })
    $ui.BtnRastrosRemover.Add_Click({
        $itens = @($script:KInterruptoresRastros | Where-Object IsChecked | ForEach-Object Tag)
        if (-not $itens) { $script:KUi.TxtStatus.Text = 'Nenhum rastro marcado'; return }
        $grupos = @($itens | Group-Object Programa | ForEach-Object { @{ Nome = $_.Name; Itens = @($_.Group) } })
        Start-KTarefaGui 'Removendo rastros' -Parametros @{ Grupos = $grupos } -Script {
            param($Grupos)
            foreach ($g in $Grupos) { Remove-KRastros $g.Itens $g.Nome | Out-Null }
        } -AoConcluir { Show-KListaApps }
    })

    # ── Drivers ──
    $ui.NavDrivers.Add_Checked({
        if (-not $script:KFabricante) { try { Update-KCartaoFabricante } catch {} }
        if (-not $script:KDrivers) { Start-KListarDrivers $false }
    })
    $ui.BtnDrvProcurar.Add_Click({ Start-KListarDrivers $true })
    $ui.ChkDrvTodos.Add_Click({ if ($script:KDrivers) { Show-KDrivers } })
    $ui.DgDrivers.Add_SelectionChanged({ Update-KBotaoDrivers })
    $ui.BtnDrvInstalar.Add_Click({
        $itens = @($script:KUi.DgDrivers.SelectedItems | Where-Object { $_.Situacao -eq 'Atualização' })
        if (-not $itens) { $script:KUi.TxtStatus.Text = $(if ($script:KDrvOnline) { 'Marque ao menos uma atualização' } else { 'Clique em Procurar atualizações primeiro' }); return }
        $msg = "Atualizar $($itens.Count) driver(s)?`n`n- $(($itens | ForEach-Object { "$($_.Nome)  →  $($_.Disponivel) ($($_.Fonte))" }) -join "`n- ")`n`n" +
               'Antes: ponto de restauração e cópia dos drivers atuais. A tela pode piscar durante a troca do driver de vídeo.'
        if ("$([Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Drivers', 'YesNo', 'Question'))" -ne 'Yes') { return }
        Start-KTarefaGui 'Atualizando drivers' -Parametros @{ Itens = $itens } -Script {
            param($Itens)
            Write-KLog 'Atualizar drivers' Titulo
            Install-KAtualizacoesDrivers $Itens
            @(Get-KSituacaoDrivers -Todos)
        } -AoConcluir {
            param($res)
            $script:KDrivers = @($res | Where-Object { $_ -and $_.PSObject.Properties['Situacao'] })
            $script:KDrvOnline = $false
            Show-KDrivers
        }
    })
    $ui.BtnDrvFabricante.Add_Click({
        $m = $script:KFabricante
        $msg = if ($m.Ferramenta.Auto) { "Instalar o $($m.Ferramenta.Nome) (oficial da $($m.Marca)) e deixar ele atualizar drivers e firmware?`n`nPode levar bastante e pedir pra reiniciar no fim." }
               else { "Instalar o $($m.Ferramenta.Nome) da Microsoft Store?" }
        if ("$([Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Drivers do fabricante', 'YesNo', 'Question'))" -ne 'Yes') { return }
        Start-KTarefaGui "$($m.Ferramenta.Nome)" -Script { Write-KLog 'Drivers do fabricante' Titulo; New-KPontoRestauracao 'K-Bench - drivers do fabricante' | Out-Null; Invoke-KFerramentaFabricante | Out-Null }
    })
    $ui.BtnDrvPagina.Add_Click({
        $m = $script:KFabricante
        if ($m.Serial) { try { Set-Clipboard -Value $m.Serial; Write-KLog "Número de série copiado: $($m.Serial) (cole na busca do site)" OK } catch {} }
        Start-Process $m.Pagina
    })
    $ui.BtnDrvBackup.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Onde salvar o backup dos drivers? (um pendrive ou outra partição; uma pasta é criada dentro)'
        if ("$($dlg.ShowDialog())" -ne 'OK') { return }
        $q = [Windows.MessageBox]::Show($script:KUi.Janela, "Incluir os drivers de vídeo?`n`nSão os maiores (vários GB) e dá pra baixar o mais novo depois aqui mesmo, em Procurar atualizações.`n`nSim = incluir   ·   Não = deixar o vídeo de fora", 'Backup dos drivers', 'YesNoCancel', 'Question')
        if ("$q" -eq 'Cancel') { return }
        Start-KTarefaGui 'Backup dos drivers' -Parametros @{ Destino = $dlg.SelectedPath; SemVideo = ("$q" -eq 'No') } -Script {
            param($Destino, $SemVideo)
            Write-KLog 'Backup dos drivers' Titulo
            Backup-KDrivers -Destino $Destino -SemVideo:$SemVideo
        } -AoConcluir { param($res); $d = @($res | Where-Object { $_ -is [string] }) | Select-Object -Last 1; if ($d -and (Test-Path $d)) { Start-Process explorer.exe $d } }
    })
    $ui.BtnDrvRestaurar.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Escolha a pasta do backup (Drivers_...)'
        if ("$($dlg.ShowDialog())" -ne 'OK') { return }
        Start-KTarefaGui 'Restaurando drivers' -Parametros @{ Origem = $dlg.SelectedPath } -Script {
            param($Origem)
            Write-KLog 'Restaurar drivers' Titulo
            Restore-KDrivers -Origem $Origem
        } -AoConcluir { $script:KDrivers = $null; Start-KListarDrivers $false }
    })
    $ui.BtnDrvLimpar.Add_Click({
        $q = [Windows.MessageBox]::Show($script:KUi.Janela, "Apagar do Windows as versões antigas de drivers que já foram substituídas e não estão em uso?`n`nO que estiver em uso o próprio Windows recusa apagar. Ajuda a liberar espaço.", 'Limpar drivers antigos', 'YesNo', 'Question')
        if ("$q" -ne 'Yes') { return }
        Start-KTarefaGui 'Limpando drivers antigos' -Script { Write-KLog 'Drivers antigos' Titulo; Remove-KDriversAntigos }
    })

    # ── Impressoras ──
    $ui.NavImpressoras.Add_Checked({ Update-KListaImpressorasInstaladas })
    $ui.BtnImpProcurar.Add_Click({
        $script:KUi.PnlImpAchadas.Children.Clear()
        Start-KTarefaGui 'Procurando impressoras na rede' -Script { @(Find-KImpressorasRede) } -AoConcluir {
            param($res)
            Show-KImpressorasAchadas @($res)
        }
    })
    $ui.BtnImpAdicionar.Add_Click({
        $sel = @($script:KLinhasImp | Where-Object { $_.Interruptor.IsChecked } | ForEach-Object { @{ Imp = $_.Interruptor.Tag; Nome = $_.Nome.Text.Trim() } })
        if (-not $sel) { $script:KUi.TxtStatus.Text = 'Marque ao menos uma impressora (Procurar na rede primeiro)'; return }
        Start-KTarefaGui 'Adicionando impressoras' -Parametros @{ Sel = $sel; Scanner = [bool]$script:KUi.ChkImpScanner.IsChecked } -Script {
            param($Sel, $Scanner)
            Write-KLog 'Impressoras' Titulo
            foreach ($s in $Sel) { Add-KImpressoraRede $s.Imp -Nome $s.Nome -Scanner $Scanner | Out-Null }
            @(Find-KImpressorasRede)
        } -AoConcluir {
            param($res)
            Show-KImpressorasAchadas @($res)
            Update-KListaImpressorasInstaladas
        }
    })

    # ── Perfis ──
    $ui.NavPerfis.Add_Checked({ if (-not $script:KPerfis) { Update-KListaPerfis } })
    foreach ($rb in 'RbPfAjustes', 'RbPfProgramas', 'RbPfImpressoras', 'RbPfGeral') {
        $ui[$rb].Add_Checked({
            param($s)
            foreach ($p in 'Ajustes', 'Programas', 'Impressoras', 'Geral') { $script:KUi["PnlPf$p"].Visibility = if ($s.Name -eq "RbPf$p") { 'Visible' } else { 'Collapsed' } }
        })
    }
    foreach ($rb in 'RbPfManNenhuma', 'RbPfManRapida', 'RbPfManCompleta') { $ui[$rb].Add_Click({ Update-KResumoEditor }) }
    $ui.BtnPerfilSalvar.Add_Click({
        $p = Get-KPerfilDoEditor
        if (-not $p.Nome) { $script:KUi.TxtStatus.Text = 'Dê um nome ao perfil'; return }
        Save-KPerfil $p
        Write-KLog "Perfil $($p.Nome) salvo" OK
        Update-KListaPerfis $p.Id
    })
    $ui.BtnPerfilNovo.Add_Click({
        $n = 1; while ($script:KPerfis | Where-Object Id -eq "perfil$n") { $n++ }
        $p = New-KPerfil "perfil$n" "Novo perfil $n" ''
        Save-KPerfil $p
        Update-KListaPerfis $p.Id
        $script:KUi.TxtPerfilNome.Focus(); $script:KUi.TxtPerfilNome.SelectAll()
    })
    $ui.BtnPerfilDuplicar.Add_Click({
        $p = Get-KPerfilDoEditor
        $n = 2; while ($script:KPerfis | Where-Object Id -eq "$($p.Id)$n") { $n++ }
        $p.Id = "$($p.Id)$n"; $p.Nome = "$($p.Nome) ($n)"; $p.Padrao = $false
        Save-KPerfil $p
        Update-KListaPerfis $p.Id
    })
    $ui.BtnPerfilExcluir.Add_Click({
        $a = $script:KPerfilAtual
        $msg = if ($a.Padrao) { "Voltar o perfil $($a.Nome) ao padrão do K-Bench? Suas alterações nele somem." } else { "Excluir o perfil $($a.Nome)?" }
        if ("$([Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Perfis', 'YesNo', 'Question'))" -ne 'Yes') { return }
        Remove-KPerfil $a.Id
        Update-KListaPerfis $(if ($a.Padrao) { $a.Id })
    })
    $ui.BtnPerfilExportar.Add_Click({
        $p = Get-KPerfilDoEditor
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = 'Perfil do K-Bench (*.json)|*.json'; $dlg.FileName = "kbench-perfil-$($p.Id).json"
        if ($dlg.ShowDialog()) { [IO.File]::WriteAllText($dlg.FileName, (ConvertTo-KPerfilJson $p), (New-Object Text.UTF8Encoding $false)); Write-KLog "Perfil exportado: $($dlg.FileName)" OK }
    })
    $ui.BtnPerfilImportar.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Perfil do K-Bench (*.json)|*.json'
        if (-not $dlg.ShowDialog()) { return }
        try {
            $p = ConvertFrom-KPerfilJson (Get-Content $dlg.FileName -Raw -Encoding UTF8)
            if ($script:KPerfis | Where-Object Id -eq $p.Id) {
                $q = [Windows.MessageBox]::Show($script:KUi.Janela, "Já existe o perfil $($p.Nome). Substituir?", 'Importar', 'YesNo', 'Question')
                if ("$q" -ne 'Yes') { return }
            }
            Save-KPerfil $p
            Write-KLog "Perfil importado: $($p.Nome)" OK
            Update-KListaPerfis $p.Id
        } catch { Write-KLog "Arquivo de perfil inválido: $($_.Exception.Message)" Erro }
    })
    $ui.BtnPerfilCapturar.Add_Click({
        $q = [Windows.MessageBox]::Show($script:KUi.Janela, "Marcar neste perfil o que está aplicado e instalado neste PC agora?`n`n(Ajustes, programas do catálogo, drivers e impressoras de rede. Nada é salvo até você clicar em Salvar.)", 'Copiar deste PC', 'YesNo', 'Question')
        if ("$q" -ne 'Yes') { return }
        Start-KTarefaGui 'Lendo este PC' -Script { Get-KCapturaPC } -AoConcluir {
            param($res)
            $c = @($res)[0]
            if (-not $c) { return }
            $p = Get-KPerfilDoEditor
            $p.Tweaks = @($c.Tweaks); $p.Programas = @($c.Programas)
            $p.Impressoras.Drivers = @($c.Drivers); $p.Impressoras.Lembradas = @($c.Lembradas)
            Show-KPerfil $p
            $script:KUi.TxtStatus.Text = 'Copiado deste PC. Revise e clique em Salvar.'
        }
    })
    $ui.BtnPerfilAplicar.Add_Click({
        $p = Get-KPerfilDoEditor
        $agr = @(Get-KTweaks | Where-Object { $_.Nivel -eq 'Agressivo' -and $_.Id -in $p.Tweaks } | ForEach-Object Nome)
        $msg = "Aplicar o perfil $($p.Nome) neste PC?`n`n$(Get-KResumoPerfil $p)`n`nO que já estiver aplicado/instalado é pulado. Cria ponto de restauração antes." +
               $(if ($agr) { "`n`nInclui ajustes agressivos: $($agr -join ', ')." } else { '' }) +
               $(if ($p.Programas -contains 'M365Pessoal' -or $p.Programas -contains 'M365Empresas') { "`n`nO Microsoft 365 sozinho leva de 10 a 30 min." } else { '' })
        if ("$([Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Aplicar perfil', 'YesNo', 'Question'))" -ne 'Yes') { return }
        Start-KTarefaGui "Perfil $($p.Nome)" -Parametros @{ Perfil = $p } -Script {
            param($Perfil)
            Invoke-KPerfil $Perfil
        } -AoConcluir { $script:KTweaksVerificados = $false; $script:KProgramasVerificados = $false; $script:KApps = $null }
    })

    # ── Bateria e energia ──
    $ui.BtnBateria.Add_Click({
        $script:KUi.DgBateria.ItemsSource = $null
        Start-KTarefaGui 'Análise de bateria e energia' -Script {
            [pscustomobject]@{ Achados = (Get-KDiagnosticoBateria); Correcoes = @(Get-KSituacaoCorrecoes) }
        } -AoConcluir {
            param($res)
            $r = @($res)[0]
            if (-not $r) { return }
            $u = $script:KUi
            $ordem = @{ Critico = 0; Atencao = 1; Info = 2; OK = 3 }
            $u.DgBateria.ItemsSource = @($r.Achados | Sort-Object { $ordem[$_.Status] })
            $nc = @($r.Achados | Where-Object Status -eq 'Critico').Count
            $na = @($r.Achados | Where-Object Status -eq 'Atencao').Count
            $nr = @($r.Correcoes | Where-Object Recomendada).Count
            $u.TxtResumoBat.Text = "$nc crítico(s), $na de atenção  ·  $nr correção(ões) recomendada(s)"
            Update-KListaEnergia $r.Correcoes
        }
    })
    $ui.BtnAplicarEnergia.Add_Click({
        $aplicar = @(); $desfazer = @(); $ignorar = @()
        foreach ($cb in $script:KInterruptoresEnergia) {
            $s = $cb.Tag
            if ($cb.IsChecked -and (-not $s.Aplicada -or $s.Situacao -eq 'Não pegou')) { $aplicar += $s.Id }
            if (-not $cb.IsChecked -and $s.Aplicada) { $desfazer += $s.Id }
            # Recomendada e desligada de propósito: para de recomendar (volta se ligar de novo)
            if (-not $cb.IsChecked -and $s.Recomendada -and -not $s.Aplicada) { $ignorar += $s.Id }
        }
        foreach ($i in $ignorar) { Set-KCorrecaoIgnorada $i; Write-KLog "$i`: desligada por você, não será mais recomendada" Info }
        if (-not ($aplicar + $desfazer)) {
            if ($ignorar) { Update-KListaEnergia @(Get-KSituacaoCorrecoes) }
            $script:KUi.TxtStatus.Text = if ($ignorar) { 'Preferências salvas' } else { 'Nenhuma alteração pra aplicar' }
            return
        }
        Start-KTarefaGui 'Correções de energia' -Parametros @{ Aplicar = $aplicar; Desfazer = $desfazer } -Script {
            param($Aplicar, $Desfazer)
            Write-KLog 'Correções de energia' Titulo
            foreach ($i in $Desfazer) { Undo-KCorrecaoEnergia $i }
            if ($Aplicar) { New-KPontoRestauracao 'K-Bench - correções de energia' | Out-Null }
            foreach ($i in $Aplicar) { Invoke-KCorrecaoEnergia $i }
            @(Get-KSituacaoCorrecoes)
        } -AoConcluir {
            param($res)
            if ($res) { Update-KListaEnergia @($res) }
        }
    })
    $ui.BtnEnergia.Add_Click({
        Start-KTarefaGui 'Análise de energia (60 s)' -Script {
            [pscustomobject]@{ Arquivo = (Invoke-KAnaliseEnergia -Segundos 60 | Where-Object { $_ -is [string] } | Select-Object -First 1); Correcoes = @(Get-KSituacaoCorrecoes) }
        } -AoConcluir {
            param($res)
            $r = @($res)[0]
            if ($r.Arquivo -and (Test-Path $r.Arquivo)) { Start-Process $r.Arquivo }
            if ($r.Correcoes) { Update-KListaEnergia $r.Correcoes }
        }
        # A barra animada faz o próprio K-Bench pedir timer rápido e aparecer na análise: fica escondida nesses 60 s
        $script:KUi.PbOcupado.Visibility = 'Collapsed'
        $script:KUi.TxtStatus.Text = 'Analisando energia por 60 s… deixe o notebook parado (de preferência na bateria)'
    })
    $ui.BtnConsumo.Add_Click({
        $l = Get-KLeituraBateria
        if (-not $l) { $script:KUi.TxtStatus.Text = 'Este PC não tem bateria'; return }
        if ($l.NaTomada) { $script:KUi.TxtStatus.Text = 'Tire o carregador antes do teste de consumo'; return }
        $script:KUi.DgBateria.ItemsSource = $null
        Start-KTarefaGui 'Teste de consumo' -Script { @(Invoke-KTesteConsumo) } -AoConcluir {
            param($res)
            $a = @($res | Where-Object { $_ -and $_.PSObject.Properties['Status'] })
            if ($a) {
                $script:KUi.DgBateria.ItemsSource = $a
                $script:KUi.TxtResumoBat.Text = 'Teste de consumo: ' + (($a | ForEach-Object { "$($_.Item) $(($_.Detalhe -split ' W')[0]) W" }) -join '  ·  ')
            }
        }
        # Mesma razão da Análise de 60 s: a barra animada gastaria energia durante a medição
        $script:KUi.PbOcupado.Visibility = 'Collapsed'
    })
    $ui.ChkLimite80.Add_Click({
        if ($script:KAtualizandoAcer) { return }
        Set-KLimiteCarga ([bool]$script:KUi.ChkLimite80.IsChecked) | Out-Null
        Update-KCartaoBateriaAcer
    })
    $ui.BtnCalibrar.Add_Click({
        $s = Get-KLimiteCarga
        if ($s.Calibrando) { Stop-KCalibracaoBateria | Out-Null; Update-KCartaoBateriaAcer; return }
        $msg = "A BIOS vai carregar a bateria até 100%, descarregar e carregar de novo, com o carregador ligado o tempo todo. Leva algumas horas.`n`n" +
               "Durante a calibração o limite de 80% fica desligado (volta sozinho ao encerrar).`nNão desligue o carregador até terminar.`n`nComeçar?"
        $ok = [Windows.MessageBox]::Show($script:KUi.Janela, $msg, 'Calibrar bateria', 'YesNo', 'Question')
        if ("$ok" -eq 'Yes') { Start-KCalibracaoBateria | Out-Null; Update-KCartaoBateriaAcer }
    })
    try { Update-KCartaoBateriaAcer } catch {}
    $ui.BtnRelBateria.Add_Click({
        Start-KTarefaGui 'Relatório de bateria' -Script { Export-KRelatorioBateriaWindows } -AoConcluir {
            param($res)
            $arq = @($res) | Select-Object -First 1
            if ($arq) { Start-Process $arq } else { Write-KLog 'Não foi possível gerar o relatório de bateria' Erro }
        }
    })

    $ui.BtnPastaLogs.Add_Click({ Start-Process explorer.exe $KB.LogDir })

    # ── Loop de atualização e fechamento ──
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({ Update-KGui })
    $timer.Start()

    $janela.Add_Closing({
        param($s, $e)
        if ($script:KTarefa) {
            $resp = [Windows.MessageBox]::Show("Ainda executando: $($script:KTarefa.Nome).`nFechar mesmo assim?", 'K-Bench', 'YesNo', 'Warning')
            if ($resp -ne 'Yes') { $e.Cancel = $true; return }
            try { $script:KTarefa.PS.Stop() } catch {}
        }
        $timer.Stop()
    })

    if (-not (Test-KAdmin)) { Write-KLog 'Rodando SEM administrador: várias etapas vão falhar.' Aviso }
    Write-KLog "Log desta sessão: $($KB.LogFile)" Detalhe
    [void]$janela.ShowDialog()
    $KB.LogSink = $null
}
