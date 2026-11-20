# ============================================================
#  Gera dist\kbench.ps1: um arquivo único (src + gui embutidos),
#  que é o que o one-liner baixa. Salvo em UTF-8 com BOM
#  (sem BOM o PowerShell 5.1 estraga os acentos).
# ============================================================
param([string]$Saida = (Join-Path $PSScriptRoot 'dist\kbench.ps1'))

$ErrorActionPreference = 'Stop'
$utf8bom = New-Object Text.UTF8Encoding $true
$entrada = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'kbench.ps1'))

$ini = '# <K-BUILD:SOURCES>'
$fim = '# </K-BUILD:SOURCES>'
$i = $entrada.IndexOf($ini); $f = $entrada.IndexOf($fim)
if ($i -lt 0 -or $f -lt 0) { throw 'Marcadores K-BUILD não encontrados em kbench.ps1' }
$fimLinha = $entrada.IndexOf("`n", $f) + 1

$sb = New-Object Text.StringBuilder
foreach ($arq in Get-ChildItem (Join-Path $PSScriptRoot 'src') -Recurse -Filter *.ps1 | Sort-Object FullName) {
    $rel = $arq.FullName.Substring($PSScriptRoot.Length + 1)
    [void]$sb.AppendLine("#region $rel")
    [void]$sb.AppendLine([IO.File]::ReadAllText($arq.FullName).TrimEnd())
    [void]$sb.AppendLine("#endregion $rel`r`n")
}
$xaml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'gui\MainWindow.xaml')).TrimEnd()
if ($xaml -match "(?m)^'@") { throw "MainWindow.xaml não pode ter linha começando com '@" }
[void]$sb.AppendLine("`$KXaml = @'`r`n$xaml`r`n'@")

$saidaTxt = $entrada.Substring(0, $i) + $sb.ToString() + $entrada.Substring($fimLinha)

# Valida a sintaxe do resultado antes de gravar
$erros = $null
[Management.Automation.Language.Parser]::ParseInput($saidaTxt, [ref]$null, [ref]$erros) | Out-Null
if ($erros) { $erros | ForEach-Object { Write-Host "$($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }; throw 'Build com erro de sintaxe' }

New-Item -ItemType Directory -Path (Split-Path $Saida) -Force | Out-Null
[IO.File]::WriteAllText($Saida, $saidaTxt, $utf8bom)
Write-Host "OK: $Saida ($([math]::Round((Get-Item $Saida).Length / 1KB)) KB)" -ForegroundColor Green

# K-Bench.exe: lançador (launcher\KBench.cs) com o script embutido, compilado pelo csc.exe do .NET Framework
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe = Join-Path (Split-Path $Saida) 'K-Bench.exe'
$l = Join-Path $PSScriptRoot 'launcher'
$saidaCsc = & $csc /nologo /target:winexe /optimize+ /codepage:65001 "/out:$exe" "/win32icon:$l\kbench.ico" "/win32manifest:$l\app.manifest" `
    "/resource:$Saida,kbench.ps1" /reference:System.Windows.Forms.dll "$l\KBench.cs" 2>&1
if ($LASTEXITCODE) { $saidaCsc | Write-Host -ForegroundColor Red; throw 'Falha ao compilar o K-Bench.exe' }
Write-Host "OK: $exe ($([math]::Round((Get-Item $exe).Length / 1KB)) KB)" -ForegroundColor Green
