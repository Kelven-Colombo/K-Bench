# ============================================================
#  Reparos direcionados (cada um resolve um problema específico)
# ============================================================

function Get-KReparos {
    $win = Get-KWindows
    @(
        [pscustomobject]@{ Id = 'WindowsUpdate'; Nome = 'Resetar Windows Update'; Reinicio = $false; MinBuild = 0
            Descricao = 'Para os serviços, renomeia SoftwareDistribution e catroot2 e reinicia. Resolve update travado ou com erro.' }
        [pscustomobject]@{ Id = 'Rede'; Nome = 'Resetar rede'; Reinicio = $true; MinBuild = 0
            Descricao = 'Limpa DNS, reseta Winsock e TCP/IP. Resolve "conectado sem internet" e sites que não abrem.' }
        [pscustomobject]@{ Id = 'Hora'; Nome = 'Sincronizar relógio'; Reinicio = $false; MinBuild = 0
            Descricao = 'Força sincronização da hora. Relógio errado quebra HTTPS, certificado digital e sites do governo.' }
        [pscustomobject]@{ Id = 'Wmi'; Nome = 'Verificar/reparar WMI'; Reinicio = $false; MinBuild = 0
            Descricao = 'Verifica o repositório WMI e salva se estiver inconsistente. Resolve painéis e programas que não leem info do sistema.' }
        [pscustomobject]@{ Id = 'Pesquisa'; Nome = 'Reconstruir índice de pesquisa'; Reinicio = $false; MinBuild = 0
            Descricao = 'Recria o índice do Windows Search. Resolve pesquisa do Iniciar quebrada ou lenta.' }
        [pscustomobject]@{ Id = 'Icones'; Nome = 'Limpar cache de ícones'; Reinicio = $false; MinBuild = 0
            Descricao = 'Apaga o cache de ícones e reinicia o Explorer. Resolve ícones em branco ou errados.' }
        [pscustomobject]@{ Id = 'Spooler'; Nome = 'Limpar fila de impressão'; Reinicio = $false; MinBuild = 0
            Descricao = 'Para o spooler, apaga trabalhos presos e reinicia. Resolve impressão travada.' }
        [pscustomobject]@{ Id = 'Store'; Nome = 'Reregistrar Microsoft Store'; Reinicio = $false; MinBuild = 0
            Descricao = 'Reregistra a Store e o App Installer (winget). Resolve Store que não abre e winget sumido.' }
        [pscustomobject]@{ Id = 'Memoria'; Nome = 'Agendar teste de memória'; Reinicio = $true; MinBuild = 0
            Descricao = 'Roda o Diagnóstico de Memória do Windows no próximo boot. Use quando houver tela azul aleatória.' }
        [pscustomobject]@{ Id = 'Recuperacao'; Nome = 'Reinstalar Windows mantendo tudo'; Reinicio = $false; MinBuild = 26100
            Descricao = 'Abre Configurações > Recuperação > "Corrigir problemas usando o Windows Update" (reinstala o Windows mantendo arquivos e apps). Último recurso antes de formatar.' }
    ) | Where-Object { $win.Build -ge $_.MinBuild }
}

function Invoke-KReparo {
    param([Parameter(Mandatory)][string]$Id)
    $r = Get-KReparos | Where-Object Id -eq $Id
    if (-not $r) { Write-KLog "Reparo desconhecido ou indisponível nesta versão: $Id" Erro; return }
    Write-KLog $r.Nome Titulo
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'

    try {
        switch ($Id) {
            'WindowsUpdate' {
                $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver', 'usosvc'
                foreach ($s in $svcs) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
                foreach ($p in "$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2") {
                    if (Test-Path $p) {
                        Rename-Item $p "$(Split-Path $p -Leaf).kbench-$stamp" -ErrorAction Stop
                        Write-KLog "Renomeado: $p" Detalhe
                    }
                }
                foreach ($s in $svcs) { Start-Service $s -ErrorAction SilentlyContinue }
                Write-KLog 'Windows Update resetado. Rode "Verificar atualizações" de novo.' OK
            }
            'Rede' {
                Invoke-KNativo ipconfig.exe '/flushdns' -SemLog | Out-Null
                Invoke-KNativo netsh.exe 'winsock', 'reset' -SemLog | Out-Null
                Invoke-KNativo netsh.exe 'int', 'ip', 'reset' -SemLog | Out-Null
                Write-KLog 'DNS limpo, Winsock e TCP/IP resetados. Reinicie o PC.' OK
            }
            'Hora' {
                Set-Service w32time -StartupType Manual -ErrorAction SilentlyContinue
                Start-Service w32time -ErrorAction SilentlyContinue
                $res = Invoke-KNativo w32tm.exe '/resync', '/force' -SemLog
                if ($res.Codigo -eq 0) { Write-KLog "Relógio sincronizado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" OK }
                else { Write-KLog "w32tm falhou (código $($res.Codigo)). Verifique a internet e o fuso horário." Aviso }
            }
            'Wmi' {
                $v = Invoke-KNativo winmgmt.exe '/verifyrepository' -SemLog
                if ($v.Codigo -eq 0) { Write-KLog 'Repositório WMI consistente' OK }
                else {
                    Write-KLog 'Repositório WMI inconsistente, salvando...' Aviso
                    $s = Invoke-KNativo winmgmt.exe '/salvagerepository'
                    if ($s.Codigo -eq 0) { Write-KLog 'Repositório WMI reparado' OK } else { Write-KLog 'Falha ao reparar o WMI' Erro }
                }
            }
            'Pesquisa' {
                Stop-Service WSearch -Force -ErrorAction Stop
                Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Search' -Name SetupCompletedSuccessfully -Value 0 -Type DWord
                Start-Service WSearch -ErrorAction Stop
                Write-KLog 'Índice será reconstruído em segundo plano (pode levar algumas horas)' OK
            }
            'Icones' {
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                $alvos = @("$env:LOCALAPPDATA\IconCache.db") +
                         @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue).FullName
                $n = 0
                foreach ($a in $alvos) { if ($a -and (Test-Path $a)) { Remove-Item $a -Force -ErrorAction SilentlyContinue; $n++ } }
                Start-Process explorer.exe
                Write-KLog "Cache de ícones limpo ($n arquivo(s))" OK
            }
            'Spooler' {
                Stop-Service Spooler -Force -ErrorAction Stop
                $fila = "$env:SystemRoot\System32\spool\PRINTERS"
                $n = @(Get-ChildItem $fila -File -Force -ErrorAction SilentlyContinue).Count
                Get-ChildItem $fila -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Start-Service Spooler -ErrorAction Stop
                Write-KLog "Fila de impressão limpa ($n trabalho(s) removido(s))" OK
            }
            'Store' {
                foreach ($pkg in 'Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller') {
                    $apps = Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue
                    if (-not $apps) { Write-KLog "$pkg não está instalado" Aviso; continue }
                    foreach ($a in $apps) {
                        try {
                            Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $a.InstallLocation 'AppXManifest.xml') -ErrorAction Stop
                            Write-KLog "$pkg reregistrado" OK
                        } catch { Write-KLog "${pkg}: $($_.Exception.Message)" Aviso }
                    }
                }
            }
            'Memoria' {
                $res = Invoke-KNativo bcdedit.exe '/bootsequence', '{memdiag}' -SemLog
                if ($res.Codigo -eq 0) { Write-KLog 'Teste de memória agendado. Reinicie; o resultado aparece no próximo login.' OK }
                else { Write-KLog 'Não foi possível agendar. Rode mdsched.exe manualmente.' Erro }
            }
            'Recuperacao' {
                Start-Process 'ms-settings:recovery'
                Write-KLog 'Aberto: Configurações > Recuperação. Clique em "Reinstalar agora" em "Corrigir problemas usando o Windows Update".' OK
            }
        }
        if ($r.Reinicio) { Write-KLog 'Este reparo precisa de reinicialização' Aviso }
    } catch {
        Write-KLog "Falhou: $($_.Exception.Message)" Erro
    }
}
