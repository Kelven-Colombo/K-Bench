# ============================================================
#  Manutenção: limpeza, otimização, sistema de arquivos, DISM, SFC
# ============================================================

function Get-KEtapasManutencao {
    # Id, nome, descrição e em quais modos vem marcada por padrão
    @(
        [pscustomobject]@{ Id = 'PontoRestauracao'; Nome = 'Ponto de restauração';        Rapida = $false; Completa = $true
            Descricao = 'Cria um ponto de restauração antes de mexer no sistema.' }
        [pscustomobject]@{ Id = 'Temporarios';      Nome = 'Temporários';                 Rapida = $true;  Completa = $true
            Descricao = 'Apaga temporários de todos os usuários e do Windows com mais de 2 dias.' }
        [pscustomobject]@{ Id = 'Cleanmgr';         Nome = 'Limpeza de Disco (seguras)';  Rapida = $true;  Completa = $true
            Descricao = 'cleanmgr só com categorias seguras (sem Downloads, Lixeira, Windows.old).' }
        [pscustomobject]@{ Id = 'Componentes';      Nome = 'Limpeza do WinSxS';           Rapida = $true;  Completa = $true
            Descricao = 'DISM /StartComponentCleanup: remove versões antigas de componentes do Windows.' }
        [pscustomobject]@{ Id = 'Otimizacao';       Nome = 'Otimização de volumes';       Rapida = $true;  Completa = $true
            Descricao = 'TRIM em SSD, desfragmentação em HDD (o Windows decide).' }
        [pscustomobject]@{ Id = 'SistemaArquivos';  Nome = 'Sistema de arquivos';         Rapida = $true;  Completa = $true
            Descricao = 'Verificação online do volume do sistema (Repair-Volume), sem reiniciar.' }
        [pscustomobject]@{ Id = 'Dism';             Nome = 'DISM RestoreHealth';          Rapida = $false; Completa = $true
            Descricao = 'Repara a imagem do Windows (fonte: Windows Update ou ISO).' }
        [pscustomobject]@{ Id = 'Sfc';              Nome = 'SFC /scannow';                Rapida = $false; Completa = $true
            Descricao = 'Verifica e restaura arquivos de sistema corrompidos.' }
        [pscustomobject]@{ Id = 'WindowsUpdate';    Nome = 'Atualizações pendentes';      Rapida = $true;  Completa = $true
            Descricao = 'Lista atualizações do Windows ainda não instaladas.' }
    )
}

# ── Temporários ────────────────────────────────────────────────
function Clear-KTemporarios {
    param([int]$Dias = 2)
    Write-KLog 'Limpeza de temporários' Titulo
    $limite = (Get-Date).AddDays(-$Dias)
    $pastas = @("$env:SystemRoot\Temp")
    $pastas += Get-ChildItem "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue |
               Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
               ForEach-Object { Join-Path $_.FullName 'AppData\Local\Temp' }

    $totalBytes = 0
    foreach ($p in $pastas) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $qtd = 0; $bytes = 0
        Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limite } |
            ForEach-Object {
                $tam = $_.Length
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $qtd++; $bytes += $tam } catch {}
            }
        # Pastas vazias (da mais funda pra mais rasa)
        Get-ChildItem -LiteralPath $p -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { $_.LastWriteTime -lt $limite -and -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        $totalBytes += $bytes
        if ($qtd) { Write-KLog ("{0} - {1} arquivo(s), {2:N0} MB" -f $p, $qtd, ($bytes / 1MB)) OK }
    }
    Write-KLog ("Total em temporários: {0:N0} MB" -f ($totalBytes / 1MB)) OK
}

# ── cleanmgr ───────────────────────────────────────────────────
function Invoke-KCleanmgr {
    param([int]$TimeoutMin = 30)
    Write-KLog 'Limpeza de Disco (cleanmgr)' Titulo
    $sageset = 64
    $flag    = 'StateFlags{0:D4}' -f $sageset
    # Fora de propósito: Downloads, Lixeira, Windows.old, dumps/relatórios de erro, shaders, miniaturas
    $permitidos = @(
        'Active Setup Temp Folders', 'Delivery Optimization Files', 'Downloaded Program Files',
        'Internet Cache Files', 'Old ChkDsk Files', 'Setup Log Files', 'Temporary Files',
        'Temporary Setup Files', 'Update Cleanup', 'Windows Upgrade Log Files'
    )
    $regBase = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    Get-ChildItem $regBase | ForEach-Object {
        $valor = if ($permitidos -contains $_.PSChildName) { 2 } else { 0 }
        Set-ItemProperty -Path $_.PSPath -Name $flag -Value $valor -Type DWord -ErrorAction SilentlyContinue
    }
    $proc = Start-Process cleanmgr.exe -ArgumentList "/sagerun:$sageset" -PassThru -WindowStyle Hidden
    $proc | Wait-Process -Timeout ($TimeoutMin * 60) -ErrorAction SilentlyContinue
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Write-KLog "cleanmgr travou e foi encerrado após $TimeoutMin min" Aviso
    } else {
        Write-KLog 'Limpeza de disco concluída' OK
    }
}

# ── WinSxS ─────────────────────────────────────────────────────
function Invoke-KLimpezaComponentes {
    Write-KLog 'Limpeza do repositório de componentes (WinSxS)' Titulo
    $r = Invoke-KNativo dism.exe '/Online','/Cleanup-Image','/StartComponentCleanup','/NoRestart' -SemLog
    if ($r.Codigo -eq 0) { Write-KLog 'Componentes antigos removidos' OK }
    else { Write-KLog "DISM StartComponentCleanup terminou com código $($r.Codigo)" Aviso }
}

# ── Otimização ─────────────────────────────────────────────────
function Optimize-KVolumes {
    Write-KLog 'Otimização de volumes' Titulo
    $naBateria = Test-KNaBateria
    Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.FileSystem -eq 'NTFS' } |
        ForEach-Object {
            $letra = $_.DriveLetter
            $tipo  = try { (Get-Partition -DriveLetter $letra | Get-Disk | ForEach-Object {
                         Get-PhysicalDisk | Where-Object DeviceId -eq "$($_.Number)" }).MediaType } catch { $null }
            if ($naBateria -and $tipo -eq 'HDD') {
                Write-KLog "${letra}: HDD na bateria, desfragmentação pulada (ligue na tomada)" Aviso
                return
            }
            try {
                Optimize-Volume -DriveLetter $letra -ErrorAction Stop
                Write-KLog "${letra}: otimizado$(if ($tipo) { " ($tipo)" })" OK
            } catch {
                Write-KLog "${letra}: $($_.Exception.Message)" Aviso
            }
        }
}

# ── Sistema de arquivos ────────────────────────────────────────
function Test-KSistemaArquivos {
    param([switch]$AgendarReparo)
    $letra = $env:SystemDrive.TrimEnd(':')
    Write-KLog "Sistema de arquivos (${letra}:)" Titulo
    try {
        $res = Repair-Volume -DriveLetter $letra -Scan -ErrorAction Stop
    } catch {
        Write-KLog "Falha na verificação: $($_.Exception.Message)" Erro
        return
    }
    switch ("$res") {
        'NoErrorsFound' { Write-KLog 'Nenhum erro no sistema de arquivos' OK }
        'SpotFixNeeded' {
            Write-KLog 'Erros pontuais encontrados (corrigíveis rapidamente)' Aviso
            if ($AgendarReparo) {
                try {
                    Repair-Volume -DriveLetter $letra -SpotFix -ErrorAction Stop | Out-Null
                    Write-KLog 'Correção pontual aplicada/agendada (pode concluir no próximo boot, leva segundos)' OK
                } catch { Write-KLog "SpotFix falhou: $($_.Exception.Message)" Erro }
            } else { Write-KLog 'Rode com "agendar reparo" ativado pra corrigir' Detalhe }
        }
        default {
            Write-KLog "Reparo completo necessário ($res)" Erro
            if ($AgendarReparo) {
                try {
                    Repair-Volume -DriveLetter $letra -OfflineScanAndFix -ErrorAction Stop | Out-Null
                    Write-KLog 'Reparo offline agendado pro próximo boot' OK
                } catch { Write-KLog "Não foi possível agendar: $($_.Exception.Message)" Erro }
                Write-KLog "Se for HDD com suspeita de setor ruim, rode depois: chkdsk ${letra}: /r" Detalhe
            }
        }
    }
}

# ── DISM ───────────────────────────────────────────────────────
# FonteISO aceita: arquivo .iso, letra/pasta de mídia (D:\) ou caminho direto do install.wim/.esd
function Invoke-KDism {
    param([string]$FonteISO)
    Write-KLog 'DISM RestoreHealth' Titulo
    $dismArgs = @('/Online', '/Cleanup-Image', '/RestoreHealth', '/NoRestart')
    $iso  = $null

    if ($FonteISO) {
        try {
            $imagem = $FonteISO
            if ($FonteISO -match '\.iso$') {
                $iso = Mount-DiskImage -ImagePath $FonteISO -PassThru -ErrorAction Stop
                $imagem = ($iso | Get-Volume).DriveLetter + ':\'
            }
            if (Test-Path -LiteralPath $imagem -PathType Container) {
                $imagem = @('sources\install.wim', 'sources\install.esd') |
                          ForEach-Object { Join-Path $imagem $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
            }
            if (-not $imagem) { throw 'install.wim/install.esd não encontrado na fonte' }

            # Escolhe o índice com a mesma edição instalada (Professional, Core...)
            $edicao = (Get-KWindows).Edicao
            $indice = Get-WindowsImage -ImagePath $imagem | ForEach-Object {
                          Get-WindowsImage -ImagePath $imagem -Index $_.ImageIndex } |
                      Where-Object EditionId -eq $edicao | Select-Object -First 1 -ExpandProperty ImageIndex
            if (-not $indice) { $indice = 1; Write-KLog "Edição $edicao não achada na imagem, usando índice 1" Aviso }

            $prefixo = if ($imagem -match '\.esd$') { 'esd' } else { 'wim' }
            $dismArgs += "/Source:${prefixo}:`"$imagem`":$indice", '/LimitAccess'
            Write-KLog "Fonte: $imagem (índice $indice)" Detalhe
        } catch {
            Write-KLog "Fonte inválida ($($_.Exception.Message)); usando Windows Update" Aviso
        }
    } else {
        Write-KLog 'Fonte: Windows Update (precisa de internet)' Detalhe
    }

    try {
        $r = Invoke-KNativo dism.exe $dismArgs
        switch ($r.Codigo) {
            0          { Write-KLog 'DISM concluído sem erros' OK }
            -2146498529 { Write-KLog 'Fonte de reparo não encontrada (0x800f081f). Use uma ISO da mesma versão como fonte.' Erro }
            default    { Write-KLog ("DISM terminou com código 0x{0:X8}" -f $r.Codigo) Erro }
        }
        $r.Codigo
    } finally {
        if ($iso) { Dismount-DiskImage -ImagePath $FonteISO -ErrorAction SilentlyContinue | Out-Null }
    }
}

# ── SFC ────────────────────────────────────────────────────────
function Invoke-KSfc {
    Write-KLog 'SFC /scannow' Titulo
    $inicio = Get-Date
    $r = Invoke-KNativo sfc.exe '/scannow' -Unicode -SemLog

    # Lê só as linhas [SR] desta execução no CBS.log (aberto com compartilhamento, o TrustedInstaller segura o arquivo)
    $cbs   = Join-Path $env:SystemRoot 'Logs\CBS\CBS.log'
    $linhas = New-Object System.Collections.Generic.List[string]
    try {
        $fs = [IO.File]::Open($cbs, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs)
        while ($null -ne ($l = $sr.ReadLine())) {
            if ($l -notmatch '\[SR\]') { continue }
            $dt = [datetime]::MinValue
            if ([datetime]::TryParseExact($l.Substring(0, [math]::Min(19, $l.Length)), 'yyyy-MM-dd HH:mm:ss',
                    $null, 'None', [ref]$dt) -and $dt -ge $inicio.AddSeconds(-5)) { $linhas.Add($l) }
        }
        $sr.Close()
    } catch {
        Write-KLog "Não foi possível ler o CBS.log: $($_.Exception.Message)" Aviso
    }

    if ($linhas.Count) {
        $srLog = if ($KB.LogFile) { [IO.Path]::ChangeExtension($KB.LogFile, '.sfc.txt') } else { Join-Path $KB.LogDir 'sfc.txt' }
        $linhas | Set-Content -LiteralPath $srLog -Encoding UTF8
    }

    $naoCorrigidos = @($linhas | Where-Object { $_ -match 'Cannot repair' })
    $corrigidos    = @($linhas | Where-Object { $_ -match 'Repair(ing|ed) (corrupted )?file|Repaired file' })

    if ($r.Codigo -ne 0 -and -not $linhas.Count) {
        Write-KLog "SFC não concluiu (código $($r.Codigo)). Saída:" Erro
        $r.Saida | Select-Object -Last 5 | ForEach-Object { Write-KLog $_ Detalhe }
        return 'Falhou'
    }
    if ($naoCorrigidos.Count) {
        Write-KLog "SFC: $($naoCorrigidos.Count) arquivo(s) corrompido(s) que NÃO puderam ser corrigidos" Erro
        Write-KLog 'Rode o DISM (com ISO como fonte se precisar) e depois o SFC de novo. Se persistir: reparo in-place.' Detalhe
        Write-KLog "Detalhes: $srLog" Detalhe
        return 'NaoCorrigivel'
    }
    if ($corrigidos.Count) {
        Write-KLog "SFC: arquivos corrompidos encontrados e CORRIGIDOS ($($corrigidos.Count) registro(s)). Reinicie." OK
        Write-KLog "Detalhes: $srLog" Detalhe
        return 'Corrigido'
    }
    Write-KLog 'SFC: nenhuma violação de integridade' OK
    'Limpo'
}

# ── Windows Update (consulta) ──────────────────────────────────
function Get-KAtualizacoesPendentes {
    Write-KLog 'Windows Update' Titulo
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $res      = $searcher.Search('IsInstalled=0 and IsHidden=0')
        if ($res.Updates.Count -eq 0) {
            Write-KLog 'Nenhuma atualização pendente' OK
        } else {
            Write-KLog "$($res.Updates.Count) atualização(ões) pendente(s):" Aviso
            foreach ($u in $res.Updates) { Write-KLog "- $($u.Title)" Detalhe }
        }
        $res.Updates.Count
    } catch {
        Write-KLog "Não foi possível consultar o Windows Update: $($_.Exception.Message)" Aviso
    }
}

# ── Orquestrador ───────────────────────────────────────────────
function Invoke-KManutencao {
    param(
        [ValidateSet('Rapida','Completa')][string]$Modo = 'Rapida',
        [string[]]$Etapas,
        [string]$FonteISO,
        [switch]$AgendarReparoDisco
    )
    if (-not $Etapas) { $Etapas = (Get-KEtapasManutencao | Where-Object $Modo).Id }
    $letra = $env:SystemDrive.TrimEnd(':')
    $livreAntes = Get-KEspacoLivreGB $letra
    Write-KLog "Manutenção $Modo | etapas: $($Etapas -join ', ')"

    $ordem = (Get-KEtapasManutencao).Id   # sempre na ordem certa, independente de como veio
    foreach ($e in $ordem | Where-Object { $Etapas -contains $_ }) {
        try {
            switch ($e) {
                'PontoRestauracao' { Write-KLog 'Ponto de restauração' Titulo; New-KPontoRestauracao "K-Bench - manutenção $Modo" | Out-Null }
                'Temporarios'      { Clear-KTemporarios }
                'Cleanmgr'         { Invoke-KCleanmgr }
                'Componentes'      { Invoke-KLimpezaComponentes }
                'Otimizacao'       { Optimize-KVolumes }
                'SistemaArquivos'  { Test-KSistemaArquivos -AgendarReparo:$AgendarReparoDisco }
                'Dism'             { Invoke-KDism -FonteISO $FonteISO | Out-Null }   # DISM antes do SFC: conserta a fonte que o SFC usa
                'Sfc'              { Invoke-KSfc | Out-Null }
                'WindowsUpdate'    { Get-KAtualizacoesPendentes | Out-Null }
            }
        } catch {
            Write-KLog "Etapa $e falhou: $($_.Exception.Message)" Erro
        }
    }

    Write-KLog 'Resumo' Titulo
    $liberado = [math]::Round((Get-KEspacoLivreGB $letra) - $livreAntes, 2)
    if ($liberado -gt 0) { Write-KLog "Liberado no ${letra}: nesta execução: $liberado GB" OK }
    else { Write-KLog "Nada liberado no ${letra}: (o Windows usou $([math]::Abs($liberado)) GB durante as etapas: atualizações, ponto de restauração, logs)" Info }
    if (Test-KReinicioPendente) { Write-KLog 'REINICIALIZAÇÃO PENDENTE - reinicie pra concluir atualizações/reparos' Aviso }
    Write-KLog "Log: $($KB.LogFile)" Detalhe
}
