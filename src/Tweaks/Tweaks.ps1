# ============================================================
#  Motor de tweaks (debloat + otimizações) com desfazer por ajuste.
#  Cada tweak = lista de ações declarativas. Ao aplicar, o valor anterior
#  de cada ação fica em C:\ProgramData\K-Bench\estado\tweaks.json.
#
#  Ações:
#    reg    K (caminho), N (nome; '' = valor padrão), V (valor; $null = remover), Tipo (DWord/String/QWord)
#    svc    N (serviço), V (Disabled/Manual/Automatic)
#    task   N (\Caminho\Nome da tarefa) -> fica desativada
#    appx   N (nome do pacote, aceita *) -> removido de todos os usuários e do provisionamento
#    feat   N (recurso opcional do Windows) -> desativado
#    script Teste / Aplicar / Desfazer (texto de scriptblock)
#
#  Ações reg em HKCU também vão pro usuário padrão (contas criadas depois) quando pedido.
# ============================================================

function Get-KNiveisTweak { @('Seguro', 'Recomendado', 'Agressivo', 'Preferência') }

# ── Registro ───────────────────────────────────────────────────
function Get-KValorReg {
    param([string]$K, [string]$N)
    $chave = Get-Item -LiteralPath $K -ErrorAction SilentlyContinue   # ($k e $K são a mesma variável no PowerShell)
    if (-not $chave -or $chave.GetValueNames() -notcontains $N) { return [pscustomobject]@{ Existe = $false; Valor = $null; Tipo = $null } }
    [pscustomobject]@{ Existe = $true; Valor = $chave.GetValue($N, $null, 'DoNotExpandEnvironmentNames'); Tipo = "$($chave.GetValueKind($N))" }
}

function Set-KValorReg {
    param([string]$K, [string]$N, $V, [string]$Tipo = 'DWord')
    if ($null -eq $V) {
        if (Test-Path -LiteralPath $K) { Remove-ItemProperty -LiteralPath $K -Name $N -ErrorAction SilentlyContinue }
        return
    }
    if (-not (Test-Path -LiteralPath $K)) { New-Item -Path $K -Force -ErrorAction Stop | Out-Null }
    $nome = if ($N -eq '') { '(default)' } else { $N }
    New-ItemProperty -LiteralPath $K -Name $nome -Value $V -PropertyType $Tipo -Force -ErrorAction Stop | Out-Null
}

# Usuário padrão (C:\Users\Default\NTUSER.DAT): carregado em HKU\KBench_Padrao enquanto aplica
function Mount-KHivePadrao {
    if (Test-Path 'Registry::HKEY_USERS\KBench_Padrao') { return $true }
    $arq = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (-not (Test-Path $arq)) { return $false }
    & reg.exe load 'HKU\KBench_Padrao' $arq 2>&1 | Out-Null
    $LASTEXITCODE -eq 0
}

function Dismount-KHivePadrao {
    if (-not (Test-Path 'Registry::HKEY_USERS\KBench_Padrao')) { return }
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    for ($i = 0; $i -lt 5; $i++) {
        & reg.exe unload 'HKU\KBench_Padrao' 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Milliseconds 500
    }
    Write-KLog 'Não consegui descarregar o registro do usuário padrão (fica pro próximo reinício)' Aviso
}

function ConvertTo-KCaminhoPadrao([string]$K) { $K -replace '^HKCU:\\', 'Registry::HKEY_USERS\KBench_Padrao\' }

# ── Serviços (pelo registro: guarda inclusive o "automático atrasado") ──
function Get-KInicioServico([string]$N) {
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$N"
    if (-not (Test-Path $k)) { return $null }
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    [pscustomobject]@{ Start = [int]$p.Start; Atrasado = [int]$p.DelayedAutostart }
}

function Get-KCodigoInicio([string]$V) { @{ Automatic = 2; Manual = 3; Disabled = 4 }[$V] }

# Alguns serviços têm a chave protegida (só o TrustedInstaller escreve): aí vai pelo sc.exe, que passa pelo gerenciador de serviços
function Set-KInicioServico {
    param([string]$N, [int]$Start, [int]$Atrasado = 0)
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$N"
    try {
        Set-ItemProperty $k -Name Start -Value $Start -Type DWord -ErrorAction Stop
        if ($Start -eq 2) { Set-ItemProperty $k -Name DelayedAutostart -Value $Atrasado -Type DWord -ErrorAction SilentlyContinue }
        elseif ((Get-ItemProperty $k -ErrorAction SilentlyContinue).DelayedAutostart) { Set-ItemProperty $k -Name DelayedAutostart -Value 0 -Type DWord -ErrorAction SilentlyContinue }
    } catch {
        $modo = switch ($Start) { 2 { if ($Atrasado) { 'delayed-auto' } else { 'auto' } } 3 { 'demand' } 4 { 'disabled' } default { 'demand' } }
        $saida = (& sc.exe config $N start= $modo 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "serviço $N protegido pelo Windows ($saida)" }
    }
}

# ── Teste de uma ação: $true aplicado, $false não, $null não se aplica (item não existe) ──
function Test-KAcaoTweak {
    param($A, $Cache)
    switch ($A.T) {
        'reg' {
            $v = Get-KValorReg $A.K $A.N
            if ($null -eq $A.V) { return -not $v.Existe }
            return ($v.Existe -and "$($v.Valor)" -eq "$($A.V)")
        }
        'svc' {
            $s = Get-KInicioServico $A.N
            if (-not $s) { return $null }
            return ($s.Start -eq (Get-KCodigoInicio $A.V))
        }
        'task' {
            $nome = Split-Path $A.N -Leaf; $cam = ($A.N.Substring(0, $A.N.Length - $nome.Length))
            $t = Get-ScheduledTask -TaskPath $cam -TaskName $nome -ErrorAction SilentlyContinue
            if (-not $t) { return $null }
            return ("$($t.State)" -eq 'Disabled')
        }
        'appx' {
            $tem = @($Cache.Appx | Where-Object { $_.Name -like $A.N }).Count + @($Cache.Prov | Where-Object { $_.DisplayName -like $A.N }).Count
            if (-not $tem) { return $null }   # não está instalado: nada a fazer
            return $false
        }
        'feat' {
            $f = try { Get-WindowsOptionalFeature -Online -FeatureName $A.N -ErrorAction Stop } catch { $null }
            if (-not $f) { return $null }   # não existe nesta versão (ou sem admin)
            return ("$($f.State)" -like 'Disabled*')
        }
        'script' { return [bool](& ([scriptblock]::Create($A.Teste))) }
    }
}

function New-KCacheTweaks {
    $appx = try { @(Get-AppxPackage -AllUsers -ErrorAction Stop | Select-Object Name, PackageFamilyName, PackageFullName) } catch { @(Get-AppxPackage | Select-Object Name, PackageFamilyName, PackageFullName) }
    $prov = try { @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Select-Object DisplayName, PackageName) } catch { @() }
    @{ Appx = $appx; Prov = $prov }
}

# ── Estado ─────────────────────────────────────────────────────
function Get-KEstadoTweaks {
    $arq = Join-Path $KB.Raiz 'estado\tweaks.json'
    $h = @{}
    if (Test-Path $arq) { try { (Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } } catch {} }
    $h
}

function Save-KEstadoTweaks([hashtable]$Estado) {
    $dir = Join-Path $KB.Raiz 'estado'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'tweaks.json'), ($Estado | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
}

# ── Situação de cada tweak ─────────────────────────────────────
function Get-KSituacaoTweaks {
    $build = (Get-KWindows).Build
    $estado = Get-KEstadoTweaks
    $cache = New-KCacheTweaks
    foreach ($t in Get-KTweaks) {
        $compativel = -not $t.MinBuild -or $build -ge $t.MinBuild
        $r = if ($compativel) { @($t.Acoes | ForEach-Object { Test-KAcaoTweak $_ $cache }) } else { @() }
        $validos = @($r | Where-Object { $null -ne $_ })
        $ok = @($validos | Where-Object { $_ }).Count
        $peloKBench = $estado.ContainsKey($t.Id)
        $situacao =
            if (-not $compativel) { 'Não se aplica' }
            elseif (-not $validos.Count) { if ($peloKBench) { 'Aplicado pelo K-Bench' } else { 'Nada a fazer' } }
            elseif ($ok -eq $validos.Count) { if ($peloKBench) { 'Aplicado pelo K-Bench' } else { 'Já está assim' } }
            elseif ($peloKBench -and $estado[$t.Id].Erros) { 'Incompleto' }
            elseif ($peloKBench) { 'Revertido' }
            elseif ($ok) { 'Parcial' }
            else { 'Padrão do Windows' }
        [pscustomobject]@{
            Id = $t.Id; Nome = $t.Nome; Descricao = $t.Descricao; Categoria = $t.Categoria; Nivel = $t.Nivel
            Situacao = $situacao; PeloKBench = $peloKBench
            Pendente = $situacao -in 'Revertido', 'Parcial', 'Padrão do Windows', 'Incompleto'
        }
    }
}

# ── Aplicar / desfazer ─────────────────────────────────────────
function Invoke-KAcaoTweak {
    param($A, [bool]$TodosUsuarios, $Cache)
    $antes = @{ T = $A.T }
    switch ($A.T) {
        'reg' {
            $alvos = @($A.K)
            if ($TodosUsuarios -and $A.K -like 'HKCU:\*' -and (Test-Path 'Registry::HKEY_USERS\KBench_Padrao')) { $alvos += ConvertTo-KCaminhoPadrao $A.K }
            # Cada alvo (esta conta / usuário padrão) só é mexido se ainda não estiver no valor
            $antes.Valores = @(foreach ($k in $alvos) {
                $v = Get-KValorReg $k $A.N
                $jaEsta = if ($null -eq $A.V) { -not $v.Existe } else { $v.Existe -and "$($v.Valor)" -eq "$($A.V)" }
                if ($jaEsta) { continue }
                Set-KValorReg $k $A.N $A.V $(if ($A.Tipo) { $A.Tipo } else { 'DWord' })
                @{ K = $k; N = $A.N; Existe = $v.Existe; Valor = $v.Valor; Tipo = $v.Tipo }
            })
            if (-not $antes.Valores.Count) { return $null }
        }
        'svc' {
            $s = Get-KInicioServico $A.N
            if (-not $s) { return $null }
            $antes.N = $A.N; $antes.Start = $s.Start; $antes.Atrasado = $s.Atrasado
            Set-KInicioServico $A.N (Get-KCodigoInicio $A.V)
            if ($A.V -eq 'Disabled') { Stop-Service $A.N -Force -ErrorAction SilentlyContinue }
        }
        'task' {
            $nome = Split-Path $A.N -Leaf; $cam = $A.N.Substring(0, $A.N.Length - $nome.Length)
            $t = Get-ScheduledTask -TaskPath $cam -TaskName $nome -ErrorAction SilentlyContinue
            if (-not $t) { return $null }
            $antes.N = $A.N; $antes.Estado = "$($t.State)"
            Disable-ScheduledTask -TaskPath $cam -TaskName $nome -ErrorAction Stop | Out-Null
        }
        'appx' {
            $pac = @($Cache.Appx | Where-Object { $_.Name -like $A.N })
            $prov = @($Cache.Prov | Where-Object { $_.DisplayName -like $A.N })
            if (-not ($pac + $prov)) { return $null }
            $antes.Familias = @($pac.PackageFamilyName | Sort-Object -Unique)
            foreach ($p in $pac) {
                try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
                catch { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { Write-KLog "$($p.Name): $($_.Exception.Message)" Aviso } }
            }
            foreach ($p in $prov) { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -AllUsers -ErrorAction SilentlyContinue | Out-Null }
            Write-KLog "Removido: $(@($pac.Name + $prov.DisplayName | Sort-Object -Unique) -join ', ')" Detalhe
        }
        'feat' {
            $antes.N = $A.N
            Disable-WindowsOptionalFeature -Online -FeatureName $A.N -NoRestart -ErrorAction Stop | Out-Null
            Write-KLog "Recurso desativado: $($A.N) (alguns só somem de vez após reiniciar)" Detalhe
        }
        'script' {
            $antes.Desfazer = $A.Desfazer
            & ([scriptblock]::Create($A.Aplicar))
        }
    }
    $antes
}

function Undo-KAcaoTweak($Antes) {
    switch ($Antes.T) {
        'reg' {
            foreach ($v in @($Antes.Valores)) {
                if (-not $v) { continue }
                if ($v.K -like 'Registry::HKEY_USERS\KBench_Padrao\*' -and -not (Test-Path 'Registry::HKEY_USERS\KBench_Padrao')) { continue }
                if ($v.Existe) { Set-KValorReg $v.K $v.N $v.Valor $(if ($v.Tipo -and $v.Tipo -ne 'Unknown') { $v.Tipo } else { 'DWord' }) }
                else { Set-KValorReg $v.K $v.N $null }
            }
        }
        'svc' {
            Set-KInicioServico $Antes.N ([int]$Antes.Start) ([int]$Antes.Atrasado)
            if ([int]$Antes.Start -eq 2) { Start-Service $Antes.N -ErrorAction SilentlyContinue }
        }
        'task' {
            if ($Antes.Estado -ne 'Disabled') {
                $nome = Split-Path $Antes.N -Leaf
                Enable-ScheduledTask -TaskPath $Antes.N.Substring(0, $Antes.N.Length - $nome.Length) -TaskName $nome -ErrorAction SilentlyContinue | Out-Null
            }
        }
        'appx' {
            # Apps removidos não voltam por comando: abre a página de cada um na Microsoft Store
            foreach ($f in @($Antes.Familias)) {
                if (-not $f) { continue }
                try { Add-AppxPackage -RegisterByFamilyName -MainPackage $f -ErrorAction Stop; Write-KLog "Restaurado: $f" Detalhe }
                catch { Start-Process "ms-windows-store://pdp/?PFN=$f"; Write-KLog "Abra a Store e clique em Obter: $f" Aviso }
            }
        }
        'feat' { Enable-WindowsOptionalFeature -Online -FeatureName $Antes.N -All -NoRestart -ErrorAction Stop | Out-Null }
        'script' { if ($Antes.Desfazer) { & ([scriptblock]::Create($Antes.Desfazer)) } }
    }
}

function Restart-KExplorer {
    Write-KLog 'Reiniciando o Explorer pra aplicar barra de tarefas/menus…' Detalhe
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

function Invoke-KTweaks {
    param([string[]]$Aplicar, [string[]]$Desfazer, [bool]$TodosUsuarios = $true)
    $catalogo = Get-KTweaks
    $estado = Get-KEstadoTweaks
    $build = (Get-KWindows).Build
    $explorer = $false
    $hive = $false
    if ($TodosUsuarios -and $Aplicar) {
        $hive = Mount-KHivePadrao
        if (-not $hive) { Write-KLog 'Não deu pra abrir o usuário padrão: os ajustes valem só pra esta conta' Aviso }
    }
    try {
        foreach ($id in $Desfazer) {
            $t = $catalogo | Where-Object Id -eq $id
            if (-not $estado.ContainsKey($id)) { Write-KLog "$($t.Nome): não foi aplicado pelo K-Bench" Aviso; continue }
            if (@($estado[$id].Acoes | ForEach-Object { $_.Valores } | Where-Object { $_.K -like '*KBench_Padrao*' })) { if (-not $hive) { $hive = Mount-KHivePadrao } }
            try {
                foreach ($a in @($estado[$id].Acoes)) { if ($a) { Undo-KAcaoTweak $a } }
                $estado.Remove($id)
                Write-KLog "$($t.Nome): desfeito" OK
                if ($t.Explorer) { $explorer = $true }
            } catch { Write-KLog "$($t.Nome): falhou ao desfazer - $($_.Exception.Message)" Erro }
        }
        $cache = if ($Aplicar) { New-KCacheTweaks }
        foreach ($id in $Aplicar) {
            $t = $catalogo | Where-Object Id -eq $id
            if (-not $t) { Write-KLog "Ajuste desconhecido: $id" Erro; continue }
            if ($t.MinBuild -and $build -lt $t.MinBuild) { Write-KLog "$($t.Nome): não se aplica a este Windows" Info; continue }
            $antes = New-Object System.Collections.Generic.List[object]
            $erros = 0
            foreach ($a in $t.Acoes) {
                try {
                    # reg decide por alvo (esta conta e usuário padrão); o resto pula se já está assim ou não existe
                    if ($a.T -ne 'reg' -and (Test-KAcaoTweak $a $cache) -ne $false) { continue }
                    $r = Invoke-KAcaoTweak $a $TodosUsuarios $cache
                    if ($r) { $antes.Add($r) }
                } catch {
                    $erros++
                    Write-KLog "$($t.Nome): $($_.Exception.Message)" Aviso
                }
            }
            # Reaplicando (Windows reverteu): mantém o "antes" original
            if ($estado.ContainsKey($id)) { $antes = @($estado[$id].Acoes) + $antes }
            $lista = @($antes | ForEach-Object { $_ })   # @(List) dentro de @{} dá erro no PS 5.1
            $estado[$id] = @{ Data = (Get-Date).ToString('s'); Acoes = $lista; Erros = $erros }
            Write-KLog "$($t.Nome): $(if ($erros) { "aplicado com $erros erro(s)" } else { 'aplicado' })" $(if ($erros) { 'Aviso' } else { 'OK' })
            if ($t.Explorer) { $explorer = $true }
        }
    } finally {
        Save-KEstadoTweaks $estado
        if ($hive) { Dismount-KHivePadrao }
    }
    if ($explorer) { Restart-KExplorer }
}
