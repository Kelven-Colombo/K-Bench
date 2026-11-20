# ============================================================
#  Relatório HTML do diagnóstico (para o técnico)
# ============================================================

function Export-KRelatorioHtml {
    param(
        [Parameter(Mandatory)][object[]]$Achados,
        [string]$Caminho
    )
    if (-not $Caminho) {
        New-Item -ItemType Directory -Path $KB.LogDir -Force | Out-Null
        $Caminho = Join-Path $KB.LogDir ("$($env:COMPUTERNAME)_diagnostico_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    }
    $enc   = { param($t) [Net.WebUtility]::HtmlEncode("$t") }
    $win   = Get-KWindows
    $ordem = @{ Critico = 0; Atencao = 1; Info = 2; OK = 3 }
    $rotulo = @{ Critico = 'Crítico'; Atencao = 'Atenção'; Info = 'Info'; OK = 'OK' }
    $conta  = { param($s) @($Achados | Where-Object Status -eq $s).Count }

    $nCrit = & $conta 'Critico'; $nAten = & $conta 'Atencao'; $nOk = & $conta 'OK'
    $veredito = if ($nCrit) { 'crit', "$nCrit problema(s) crítico(s) encontrado(s)" }
                elseif ($nAten) { 'aten', "$nAten ponto(s) de atenção" }
                else { 'ok', 'Tudo certo com esta máquina' }

    # Prioridades: o que fazer, em ordem
    $acoes = $Achados | Where-Object { $_.Recomendacao -and $_.Status -in 'Critico', 'Atencao' } |
             Sort-Object { $ordem[$_.Status] } |
             ForEach-Object { "<li class='$($_.Status.ToLower())'><b>$(& $enc $_.Item):</b> $(& $enc $_.Recomendacao)</li>" }

    $secoes = $Achados | Group-Object Categoria | ForEach-Object {
        $linhas = $_.Group | Sort-Object { $ordem[$_.Status] } | ForEach-Object {
            $rec = if ($_.Recomendacao) { "<div class='rec'>$(& $enc $_.Recomendacao)</div>" }
            "<tr><td><span class='tag $($_.Status.ToLower())'>$($rotulo[$_.Status])</span></td>" +
            "<td class='item'>$(& $enc $_.Item)</td><td>$(& $enc $_.Detalhe)$rec</td></tr>"
        }
        "<section><h2>$(& $enc $_.Name)</h2><table>$($linhas -join '')</table></section>"
    }

    $html = @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>K-Bench - $(& $enc $env:COMPUTERNAME)</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--tx:#1d2330;--mut:#667085;--ln:#e4e7ec;
--ok:#12805c;--okb:#e3f6ee;--at:#a15c00;--atb:#fff2db;--cr:#b42318;--crb:#fde7e5;--in:#3b5bdb;--inb:#e8edff}
@media (prefers-color-scheme:dark){:root{--bg:#12151b;--card:#1b2029;--tx:#e6e9ef;--mut:#98a2b3;--ln:#2a313d;
--ok:#4cc38a;--okb:#123326;--at:#f5b544;--atb:#3a2a0d;--cr:#ff6b5e;--crb:#3d1714;--in:#8ea2ff;--inb:#1e2547}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.5 "Segoe UI",system-ui,sans-serif}
main{max-width:1000px;margin:0 auto;padding:24px 16px 48px}
header{display:flex;flex-wrap:wrap;justify-content:space-between;gap:8px;align-items:baseline}
h1{margin:0;font-size:24px}h1 small{color:var(--mut);font-weight:400;font-size:14px;margin-left:8px}
.meta{color:var(--mut);font-size:13px}
.veredito{margin:20px 0;padding:16px 20px;border-radius:12px;font-size:18px;font-weight:600}
.veredito.ok{background:var(--okb);color:var(--ok)}.veredito.aten{background:var(--atb);color:var(--at)}.veredito.crit{background:var(--crb);color:var(--cr)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin-bottom:20px}
.card{background:var(--card);border:1px solid var(--ln);border-radius:12px;padding:12px 16px}
.card b{display:block;font-size:26px}.card.critico b{color:var(--cr)}.card.atencao b{color:var(--at)}.card.ok b{color:var(--ok)}
section,.acoes{background:var(--card);border:1px solid var(--ln);border-radius:12px;padding:4px 16px 8px;margin-bottom:16px}
h2{font-size:16px;margin:12px 0 8px}
.acoes ol{margin:0 0 8px;padding-left:20px}.acoes li{margin:6px 0}.acoes li.critico::marker{color:var(--cr)}
table{width:100%;border-collapse:collapse}td{padding:8px 6px;border-top:1px solid var(--ln);vertical-align:top;overflow-wrap:anywhere}
td:first-child{width:80px}td.item{width:30%;font-weight:600}
.tag{display:inline-block;padding:1px 8px;border-radius:99px;font-size:12px;font-weight:600}
.tag.ok{background:var(--okb);color:var(--ok)}.tag.atencao{background:var(--atb);color:var(--at)}
.tag.critico{background:var(--crb);color:var(--cr)}.tag.info{background:var(--inb);color:var(--in)}
.rec{color:var(--mut);font-size:13px;margin-top:4px}
@media (max-width:600px){td.item{width:auto}td:first-child{width:auto}}
footer{color:var(--mut);font-size:12px;text-align:center;margin-top:24px}
</style></head><body><main>
<header><h1>$(& $enc $env:COMPUTERNAME)<small>$(& $enc "$($win.Nome) $($win.Versao)")</small></h1>
<div class="meta">Diagnóstico K-Bench $($KB.Versao) · $(Get-Date -Format 'dd/MM/yyyy HH:mm')</div></header>
<div class="veredito $($veredito[0])">$(& $enc $veredito[1])</div>
<div class="cards">
<div class="card critico"><b>$nCrit</b>Crítico</div>
<div class="card atencao"><b>$nAten</b>Atenção</div>
<div class="card ok"><b>$nOk</b>OK</div>
</div>
$(if ($acoes) { "<div class='acoes'><h2>O que fazer, por prioridade</h2><ol>$($acoes -join '')</ol></div>" })
$($secoes -join "`n")
<footer>Gerado pelo K-Bench</footer>
</main></body></html>
"@
    [IO.File]::WriteAllText($Caminho, $html, (New-Object Text.UTF8Encoding $true))
    Write-KLog "Relatório: $Caminho" OK
    $Caminho
}
