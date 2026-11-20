# ============================================================
#  Bootstrap do one-liner:
#    irm https://raw.githubusercontent.com/Kelven-Colombo/K-Bench/main/install.ps1 | iex
#  Baixa a última release (dist\kbench.ps1) e abre como administrador.
# ============================================================
& {
    $repo    = 'Kelven-Colombo/K-Bench'
    $url     = "https://github.com/$repo/releases/latest/download/kbench.ps1"
    $destDir = Join-Path $env:TEMP 'K-Bench'
    $dest    = Join-Path $destDir 'kbench.ps1'

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Write-Host 'Baixando K-Bench...' -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "Falha no download: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    Unblock-File -LiteralPath $dest
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dest`""
}
