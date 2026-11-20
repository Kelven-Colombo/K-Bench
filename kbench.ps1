# ============================================================
#  K-Bench - bancada de técnico para Windows
#  https://github.com/Kelven-Colombo/K-Bench
#
#  Sem parâmetros abre a interface gráfica. Exemplos de linha de comando:
#    .\kbench.ps1 -Manutencao Rapida -Silencioso
#    .\kbench.ps1 -Manutencao Completa -FonteISO D:\Win11.iso -AgendarReparoDisco
#    .\kbench.ps1 -Diagnostico -Saida C:\relatorio.html
#    .\kbench.ps1 -Reparo WindowsUpdate,Rede
#    .\kbench.ps1 -ListarReparos
#    .\kbench.ps1 -Bateria                          (diagnóstico de bateria/energia + correções disponíveis)
#    .\kbench.ps1 -CorrecaoEnergia Tampa,Turbo     /  -DesfazerEnergia Turbo
#    .\kbench.ps1 -Otimizar Recomendado  /  -Tweaks Id1,Id2  /  -DesfazerTweaks Id  /  -ListarTweaks
#    .\kbench.ps1 -Limite80 Ligar|Desligar  /  -Calibrar Iniciar|Encerrar   (bateria Acer, pela BIOS)
#    .\kbench.ps1 -TesteConsumo                     (mede W parado / vídeo / navegação, na bateria)
#    .\kbench.ps1 -Preset Basico|MC|Tecnico|Dev|Runtimes  /  -Instalar Chrome,VLC  /  -Desinstalar Id
#    .\kbench.ps1 -AtualizarProgramas  /  -ListarProgramas
#    .\kbench.ps1 -Perfil mc [-Modulos Tweaks,Drivers,Programas,Impressoras,Manutencao]  /  -Perfil D:\meu.json  /  -ListarPerfis
#    .\kbench.ps1 -ProcurarImpressoras                (lista as impressoras da rede)
#    .\kbench.ps1 -Drivers  /  -AtualizarDrivers  /  -BackupDrivers E:\  [-SemVideo]  /  -RestaurarDrivers E:\Drivers_...  /  -LimparDrivers
#    .\kbench.ps1 -ListarInstalados  /  -DesinstalarCompleto "Nome*" [-Forcar]   (desinstala + remove rastros)
# ============================================================
[CmdletBinding()]
param(
    [ValidateSet('Rapida','Completa')][string]$Manutencao,
    [string[]]$Etapas,
    [string]$FonteISO,
    [switch]$AgendarReparoDisco,
    [switch]$Diagnostico,
    [string]$Saida,
    [string[]]$Reparo,
    [switch]$ListarReparos,
    [switch]$Bateria,
    [string[]]$CorrecaoEnergia,
    [string[]]$DesfazerEnergia,
    [switch]$TesteConsumo,
    [ValidateSet('Seguro','Recomendado','Agressivo')][string]$Otimizar,
    [string[]]$Tweaks,
    [string[]]$DesfazerTweaks,
    [switch]$ListarTweaks,
    [switch]$SoEstaConta,
    [ValidateSet('Ligar','Desligar')][string]$Limite80,
    [ValidateSet('Iniciar','Encerrar')][string]$Calibrar,
    [ValidateSet('Basico','MC','Tecnico','Dev','Runtimes')][string]$Preset,
    [string[]]$Instalar,
    [string[]]$Desinstalar,
    [switch]$AtualizarProgramas,
    [switch]$ListarProgramas,
    [switch]$ListarInstalados,
    [string]$Perfil,
    [string[]]$Modulos = @('Tweaks','Drivers','Programas','Impressoras','Manutencao'),
    [switch]$ListarPerfis,
    [switch]$ProcurarImpressoras,
    [switch]$Drivers,
    [switch]$AtualizarDrivers,
    [string]$BackupDrivers,
    [switch]$SemVideo,
    [string]$RestaurarDrivers,
    [switch]$LimparDrivers,
    [string]$DesinstalarCompleto,
    [switch]$Forcar,
    [switch]$Silencioso
)

# <K-BUILD:SOURCES>  (no build, este bloco é substituído pelo conteúdo de src\ e gui\)
foreach ($arq in Get-ChildItem (Join-Path $PSScriptRoot 'src') -Recurse -Filter *.ps1 | Sort-Object FullName) { . $arq.FullName }
$KXaml = Get-Content (Join-Path $PSScriptRoot 'gui\MainWindow.xaml') -Raw -Encoding UTF8
# </K-BUILD:SOURCES>

# Com -File (e na reabertura como admin) "A,B" chega como um texto só: separa aqui
foreach ($n in 'Modulos', 'Etapas', 'Reparo', 'CorrecaoEnergia', 'DesfazerEnergia', 'Tweaks', 'DesfazerTweaks', 'Instalar', 'Desinstalar') {
    $v = Get-Variable $n -ValueOnly
    if ($v) { Set-Variable $n @($v | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ }) }
}

$invalidos = @($Modulos | Where-Object { $_ -notin 'Tweaks', 'Drivers', 'Programas', 'Impressoras', 'Manutencao' })
if ($invalidos) { Write-Host "Módulo desconhecido: $($invalidos -join ', ') (use Tweaks, Drivers, Programas, Impressoras, Manutencao)" -ForegroundColor Red; return }

# ── Elevação automática ────────────────────────────────────────
if (-not (Test-KAdmin)) {
    if (-not $PSCommandPath) { Write-Host 'Execute como administrador.' -ForegroundColor Red; return }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($p in $PSBoundParameters.GetEnumerator()) {
        if ($p.Value -is [switch]) { if ($p.Value) { $argList += "-$($p.Key)" } }
        elseif ($p.Value -is [array]) { $argList += "-$($p.Key)", (($p.Value | ForEach-Object { "`"$_`"" }) -join ',') }
        else { $argList += "-$($p.Key)", "`"$($p.Value)`"" }
    }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList }
    catch { Write-Host 'Permissão de administrador negada.' -ForegroundColor Red }
    return
}

# ── GUI ────────────────────────────────────────────────────────
$temAcao = $Manutencao -or $Diagnostico -or $Reparo -or $ListarReparos -or $Bateria -or $CorrecaoEnergia -or $DesfazerEnergia -or $TesteConsumo -or $Limite80 -or $Calibrar -or $Otimizar -or $Tweaks -or $DesfazerTweaks -or $ListarTweaks -or
            $Preset -or $Instalar -or $Desinstalar -or $AtualizarProgramas -or $ListarProgramas -or $ListarInstalados -or $DesinstalarCompleto -or $Perfil -or $ListarPerfis -or $ProcurarImpressoras -or
            $Drivers -or $AtualizarDrivers -or $BackupDrivers -or $RestaurarDrivers -or $LimparDrivers
if (-not $temAcao) {
    Show-KGui
    return
}

# ── CLI ────────────────────────────────────────────────────────
$KB.Silencioso = [bool]$Silencioso
Start-KLog 'cli' | Out-Null

if ($ListarReparos) {
    Get-KReparos | Format-Table Id, Nome, Reinicio -AutoSize | Out-String | Write-Host
}

if ($Diagnostico) {
    $achados = Get-KDiagnostico
    Export-KRelatorioHtml -Achados $achados -Caminho $Saida | Out-Null
}

foreach ($id in $Reparo) { Invoke-KReparo $id }

if ($Bateria) {
    Get-KDiagnosticoBateria | Out-Null
    Write-KLog 'Correções de energia' Titulo
    Get-KSituacaoCorrecoes | ForEach-Object { Write-KLog ("{0,-15} {1,-24} {2}" -f $_.Id, $_.Situacao, $_.Nome) $(if ($_.Recomendada -and -not $_.Aplicada) { 'Aviso' } else { 'Info' }) }
    Write-KLog 'Aplique com: -CorrecaoEnergia Id1,Id2  |  desfaça com: -DesfazerEnergia Id' Detalhe
}
foreach ($id in $DesfazerEnergia) { Undo-KCorrecaoEnergia $id }
if ($CorrecaoEnergia) {
    New-KPontoRestauracao 'K-Bench - correções de energia' | Out-Null
    foreach ($id in $CorrecaoEnergia) { Invoke-KCorrecaoEnergia $id }
}

if ($ListarTweaks) {
    Get-KSituacaoTweaks | Format-Table Nivel, Id, Situacao, Nome -AutoSize | Out-String -Width 200 | Write-Host
}
if ($Otimizar -or $Tweaks -or $DesfazerTweaks) {
    $ordem = @{ Seguro = 1; Recomendado = 2; Agressivo = 3 }
    $ids = @($Tweaks)
    if ($Otimizar) { $ids += @(Get-KSituacaoTweaks | Where-Object { $_.Pendente -and $ordem[$_.Nivel] -and $ordem[$_.Nivel] -le $ordem[$Otimizar] } | ForEach-Object Id) }
    $ids = @($ids | Where-Object { $_ } | Sort-Object -Unique)
    if ($ids) { New-KPontoRestauracao 'K-Bench - otimizações' | Out-Null }
    Invoke-KTweaks -Aplicar $ids -Desfazer $DesfazerTweaks -TodosUsuarios (-not $SoEstaConta)
}
if ($ListarProgramas) {
    Get-KSituacaoProgramas | Format-Table Categoria, Id, Situacao, Nome -AutoSize | Out-String -Width 200 | Write-Host
}
if ($Preset -or $Instalar -or $Desinstalar) {
    $ids = @($Instalar)
    # Preset instala só o que falta (o que já está instalado o winget pularia de qualquer jeito, mas leva tempo)
    if ($Preset) { $ids += @(Get-KSituacaoProgramas | Where-Object { -not $_.Instalado -and $_.Presets -contains $Preset } | ForEach-Object Id) }
    Write-KLog 'Programas' Titulo
    Invoke-KProgramas -Instalar @($ids | Where-Object { $_ } | Sort-Object -Unique) -Desinstalar @($Desinstalar | Where-Object { $_ })
}
if ($ListarPerfis) {
    Get-KPerfis | ForEach-Object { Write-KLog ("{0,-10} {1,-14} {2}" -f $_.Id, $_.Nome, (Get-KResumoPerfil $_)) }
}
if ($ProcurarImpressoras) {
    Find-KImpressorasRede | Format-Table Modelo, Ip, Host, Mac, Driver, InstaladaComo -AutoSize | Out-String -Width 220 | Write-Host
}
if ($Drivers -or $AtualizarDrivers) {
    Write-KLog 'Drivers' Titulo
    $m = Get-KFabricante
    Write-KLog "$($m.Marca) $($m.Modelo)  ·  série $($m.Serial)$(if ($m.Ferramenta) { "  ·  ferramenta oficial: $($m.Ferramenta.Nome)" } elseif ($m.Pagina) { "  ·  suporte: $($m.Pagina)" })" Detalhe
    $sd = @(Get-KSituacaoDrivers -Online)
    $sd | Sort-Object Ordem, Classe | Format-Table Situacao, Classe, Nome, @{ n = 'Instalado'; e = { $_.Versao } }, Disponivel, Fonte -AutoSize | Out-String -Width 220 | Write-Host
    if ($AtualizarDrivers) { Install-KAtualizacoesDrivers @($sd | Where-Object Situacao -eq 'Atualização') }
}
if ($BackupDrivers) { Write-KLog 'Backup dos drivers' Titulo; Backup-KDrivers -Destino $BackupDrivers -SemVideo:$SemVideo | Out-Null }
if ($RestaurarDrivers) { Write-KLog 'Restaurar drivers' Titulo; Restore-KDrivers -Origem $RestaurarDrivers }
if ($LimparDrivers) { Write-KLog 'Drivers antigos' Titulo; Remove-KDriversAntigos }
if ($Perfil) {
    $p = Get-KPerfil $Perfil
    if ($p) { Invoke-KPerfil $p -Modulos $Modulos }
}
if ($ListarInstalados) {
    Get-KAppsInstalados | Format-Table Nome, Versao, Editor, Tamanho, Escopo -AutoSize | Out-String -Width 220 | Write-Host
}
if ($DesinstalarCompleto) {
    Write-KLog "Desinstalar: $DesinstalarCompleto" Titulo
    New-KPontoRestauracao "K-Bench - desinstalar $DesinstalarCompleto" | Out-Null
    Invoke-KDesinstalacaoCompleta -Nome $DesinstalarCompleto -Forcar:$Forcar
}
if ($AtualizarProgramas) { Write-KLog 'Atualizar programas' Titulo; Update-KProgramas }

if ($Limite80) { Set-KLimiteCarga ($Limite80 -eq 'Ligar') | Out-Null }
if ($Calibrar -eq 'Iniciar') { Start-KCalibracaoBateria | Out-Null }
if ($Calibrar -eq 'Encerrar') { Stop-KCalibracaoBateria | Out-Null }

if ($TesteConsumo) { Invoke-KTesteConsumo | Out-Null }

if ($Manutencao) {
    Invoke-KManutencao -Modo $Manutencao -Etapas $Etapas -FonteISO $FonteISO -AgendarReparoDisco:$AgendarReparoDisco
}

Write-Host "`n[CONCLUÍDO] Log: $($KB.LogFile)" -ForegroundColor Green
if (-not $Silencioso) { Read-Host 'Enter pra sair' | Out-Null }
