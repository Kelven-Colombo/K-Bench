# ============================================================
#  Drivers: "tipo Driver Booster, do jeito certo". Só fonte oficial:
#   1. Windows Update (a API do próprio Windows, por Hardware ID)
#   2. NVIDIA (consulta oficial do driver mais novo pela GPU)
#   3. Ferramenta do fabricante do PC (Dell, Lenovo, HP, Samsung) ou
#      a página de suporte dele, com o número de série copiado.
#  Antes de instalar: ponto de restauração + cópia dos drivers atuais.
# ============================================================


function Get-KVersaoNvidia([string]$DriverVersion) {
    # 32.0.16.2124 → 621.24 (os 5 últimos dígitos das duas últimas partes)
    $p = $DriverVersion.Split('.')
    if ($p.Count -lt 4) { return $null }
    $d = $p[2] + $p[3].PadLeft(4, '0')
    $d = $d.Substring($d.Length - 5)
    '{0}.{1}' -f $d.Substring(0, 3), $d.Substring(3)
}

function Get-KVersaoNoTitulo([string]$Titulo) {
    $m = [regex]::Matches($Titulo, '\d+(\.\d+){2,3}')
    if ($m.Count) { $m[$m.Count - 1].Value }
}

# ── O que está no PC ───────────────────────────────────────────
function Get-KDispositivos {
    # Fica aqui dentro (e não no script) porque as tarefas da GUI só recebem as funções
    $nomes = @{
        DISPLAY = 'Vídeo'; NET = 'Rede'; BLUETOOTH = 'Bluetooth'; MEDIA = 'Áudio'; CAMERA = 'Câmera'; IMAGE = 'Câmera/scanner'
        SYSTEM = 'Chipset/sistema'; HIDCLASS = 'Entrada'; KEYBOARD = 'Teclado'; MOUSE = 'Mouse/touchpad'; BIOMETRIC = 'Biometria'
        FIRMWARE = 'BIOS/firmware'; SCSIADAPTER = 'Armazenamento'; HDC = 'Armazenamento'; USB = 'USB'; SOFTWARECOMPONENT = 'Componente'
        EXTENSION = 'Extensão'; PRINTER = 'Impressora'; MONITOR = 'Monitor'; SENSOR = 'Sensores'; AUDIOPROCESSINGOBJECT = 'Áudio'
        SOFTWAREDEVICE = 'Dispositivo de software'; SMARTCARDREADER = 'Leitor de cartão'; SDHOST = 'Leitor de cartão'; BATTERY = 'Bateria'; PRINTQUEUE = 'Fila de impressão'; VOLUME = 'Volume'; DISKDRIVE = 'Disco'
    }
    $ent = @{}
    foreach ($e in Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue) { if ($e.PNPDeviceID) { $ent[$e.PNPDeviceID] = $e } }
    $vistos = @{}
    $lista = foreach ($d in Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) {
        if (-not $d.DeviceID -or -not $d.DeviceName -or $vistos[$d.DeviceID]) { continue }
        $vistos[$d.DeviceID] = $true
        $e = $ent[$d.DeviceID]
        $cl = "$($d.DeviceClass)".ToUpper()
        [pscustomobject]@{
            Nome = $d.DeviceName; ClasseId = $cl; Classe = $(if ($nomes[$cl]) { $nomes[$cl] } else { $d.DeviceClass })
            Fornecedor = $d.DriverProviderName; Versao = $d.DriverVersion
            Data = $(if ($d.DriverDate) { $d.DriverDate.ToString('dd/MM/yyyy') }); Inf = $d.InfName; DeviceId = $d.DeviceID
            HardwareIds = @(@($e.HardwareID) + @($e.CompatibleID) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
            Problema = [int]$e.ConfigManagerErrorCode
            Microsoft = ("$($d.DriverProviderName)" -match '^Microsoft' -or -not $d.DriverProviderName)
        }
    }
    # Sem driver nenhum (código 28) não aparece no PnPSignedDriver
    $sem = foreach ($e in $ent.Values) {
        if ($e.ConfigManagerErrorCode -eq 0 -or $vistos[$e.PNPDeviceID]) { continue }
        [pscustomobject]@{
            Nome = $(if ($e.Name) { $e.Name } else { 'Dispositivo desconhecido' }); ClasseId = "$($e.PNPClass)".ToUpper()
            Classe = $(if ($e.PNPClass -and $nomes["$($e.PNPClass)".ToUpper()]) { $nomes["$($e.PNPClass)".ToUpper()] } elseif ($e.PNPClass) { $e.PNPClass } else { 'Desconhecido' })
            Fornecedor = ''; Versao = ''; Data = ''; Inf = ''; DeviceId = $e.PNPDeviceID
            HardwareIds = @(@($e.HardwareID) + @($e.CompatibleID) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
            Problema = [int]$e.ConfigManagerErrorCode; Microsoft = $false
        }
    }
    @($lista) + @($sem)
}

# ── Fonte 1: Windows Update ────────────────────────────────────
# Funciona mesmo com "não receber drivers pelo Windows Update" ligado: isso só tira os drivers do automático.
function Find-KDriversWindowsUpdate {
    Write-KProgresso 'Windows Update' 'procurando drivers (a primeira busca leva 1 a 3 min)'
    try {
        $s = New-Object -ComObject Microsoft.Update.Session
        $s.ClientApplicationID = 'K-Bench'
        $se = $s.CreateUpdateSearcher()
        $se.Online = $true
        $r = $se.Search("IsInstalled=0 and Type='Driver'")
    } catch {
        Write-KLog "Windows Update não respondeu: $($_.Exception.Message)" Erro
        return
    }
    foreach ($u in $r.Updates) {
        if ($u.IsHidden) { continue }
        [pscustomobject]@{
            UpdateId = $u.Identity.UpdateID; Titulo = $u.Title; HardwareId = "$($u.DriverHardwareID)".ToLowerInvariant()
            Versao = Get-KVersaoNoTitulo $u.Title; Data = $(if ($u.DriverVerDate) { ([datetime]$u.DriverVerDate).ToString('dd/MM/yyyy') })
            Fornecedor = $u.DriverProvider; Classe = $u.DriverClass; TamanhoMB = [math]::Round($u.MaxDownloadSize / 1MB, 1)
        }
    }
}

# ── Fonte 2: NVIDIA ────────────────────────────────────────────
function Find-KDriverNvidia([string]$DeviceId) {
    $dev = [regex]::Match($DeviceId, 'DEV_([0-9A-F]{4})').Groups[1].Value
    if (-not $dev) { return $null }
    $j = '{"dIDa":["' + $dev + '_10DE"],"osC":"10.0","osB":"64","is6":"1","lg":"1033","iLp":"1","prvMd":"0","gcV":"3.25.1.27","gIsB":"0","dch":"1","upCRD":"0","isCRD":"0"}'
    $u = 'https://gfwsl.geforce.com/nvidia_web_services/controller.gfeclientcontent.NG.php/com.nvidia.services.GFEClientContent_NG.getDispDrvrByDevid/' + [uri]::EscapeDataString($j)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod $u -TimeoutSec 20 -UseBasicParsing
    } catch { Write-KLog "Consulta da NVIDIA falhou: $($_.Exception.Message)" Aviso; return $null }
    $info = $r.DriverAttributes
    if (-not $info.Version) { return $null }
    # Mesmo pacote do site público (o "-g" é a variante do app da NVIDIA)
    $url = ($info.DownloadURL -replace '://international-gfe\.download\.nvidia\.com', '://us.download.nvidia.com') -replace '-g\.exe$', '.exe'
    [pscustomobject]@{ Versao = "$($info.Version)"; Nome = [uri]::UnescapeDataString("$($info.Name)"); Url = $url; UrlAlternativa = $info.DownloadURL }
}

# ── Tudo junto: a tela de comparação ───────────────────────────
function Get-KSituacaoDrivers {
    param([switch]$Online, [switch]$Todos)
    $disp = @(Get-KDispositivos)
    $wu = if ($Online) { @(Find-KDriversWindowsUpdate) } else { @() }
    $usados = @{}
    foreach ($d in $disp) {
        $up = $null
        foreach ($w in $wu) {
            if ($usados[$w.UpdateId]) { continue }
            if ($d.HardwareIds | Where-Object { $_ -eq $w.HardwareId -or $_.StartsWith("$($w.HardwareId)&") }) { $up = $w; break }
        }
        if ($up) { $usados[$up.UpdateId] = $true }
        $nv = $null
        if ($Online -and $d.ClasseId -eq 'DISPLAY' -and $d.DeviceId -match 'VEN_10DE') {
            $nv = Find-KDriverNvidia $d.DeviceId
            $inst = Get-KVersaoNvidia $d.Versao
            if ($nv -and $inst -and [version]$nv.Versao -le [version]$inst) { $nv = $null }
            elseif ($nv) { $nv | Add-Member VersaoInstalada $inst }
        }
        $sit, $fonte, $disp_, $dataDisp = '', '', '', ''
        if ($nv) { $sit = 'Atualização'; $fonte = 'NVIDIA'; $disp_ = $nv.Versao; $up = $null }
        elseif ($up) { $sit = 'Atualização'; $fonte = 'Windows Update'; $disp_ = $(if ($up.Versao) { $up.Versao } else { $up.Data }); $dataDisp = $up.Data }
        elseif ($d.Problema -eq 28) { $sit = 'Sem driver' }
        elseif ($d.Problema) { $sit = 'Com erro' }
        elseif ($Online) { $sit = 'Atualizado' }
        # Oculto = driver do próprio Windows em dia, ou componente de software sem novidade (aparece em "Mostrar todos")
        $oculto = $sit -ne 'Atualização' -and -not $d.Problema -and ($d.Microsoft -or $d.ClasseId -in 'SOFTWAREDEVICE', 'AUDIOPROCESSINGOBJECT')
        if ($oculto -and -not $Todos) { continue }
        $versaoMostrada = if ($d.ClasseId -eq 'DISPLAY' -and $d.DeviceId -match 'VEN_10DE' -and $d.Versao) { "$(Get-KVersaoNvidia $d.Versao)  ($($d.Versao))" } else { $d.Versao }
        [pscustomobject]@{
            Nome = $d.Nome; Classe = $d.Classe; Fornecedor = $d.Fornecedor
            Sub = (@($d.Classe, $d.Fornecedor) | Where-Object { $_ }) -join '  ·  '
            Versao = $d.Versao; Data = $d.Data
            Instalado = $(if ($d.Versao) { "$versaoMostrada`n$($d.Data)" } else { 'nenhum' })
            Disponivel = $disp_; Fonte = $fonte
            DisponivelTexto = $(if ($disp_) { "$disp_`n$fonte$(if ($up -and $up.TamanhoMB) { "  ·  $($up.TamanhoMB) MB" })" } else { '' })
            Situacao = $sit; DeviceId = $d.DeviceId; Inf = $d.Inf; Problema = $d.Problema
            UpdateId = $(if ($up) { $up.UpdateId }); Url = $(if ($nv) { $nv.Url }); UrlAlternativa = $(if ($nv) { $nv.UrlAlternativa })
            Ordem = $(switch ($sit) { 'Sem driver' { 0 } 'Com erro' { 1 } 'Atualização' { 2 } default { 3 } }); Oculto = $oculto
        }
    }
    # Atualização do WU que não casou com nenhum dispositivo listado (raro): mostra mesmo assim
    foreach ($w in $wu | Where-Object { -not $usados[$_.UpdateId] }) {
        [pscustomobject]@{
            Nome = $w.Titulo; Classe = $w.Classe; Fornecedor = $w.Fornecedor; Sub = (@($w.Classe, $w.Fornecedor) | Where-Object { $_ }) -join '  ·  '
            Versao = ''; Data = ''; Instalado = '—'; Disponivel = $w.Versao; Fonte = 'Windows Update'
            DisponivelTexto = "$($w.Versao)`nWindows Update$(if ($w.TamanhoMB) { "  ·  $($w.TamanhoMB) MB" })"
            Situacao = 'Atualização'; DeviceId = ''; Inf = ''; Problema = 0; UpdateId = $w.UpdateId; Url = $null; UrlAlternativa = $null; Ordem = 2; Oculto = $false
        }
    }
}

# ── Instalar ───────────────────────────────────────────────────
function Install-KDriversWindowsUpdate([string[]]$UpdateIds) {
    $s = New-Object -ComObject Microsoft.Update.Session
    $s.ClientApplicationID = 'K-Bench'
    $se = $s.CreateUpdateSearcher(); $se.Online = $true
    Write-KProgresso 'Windows Update' 'preparando'
    $r = $se.Search("IsInstalled=0 and Type='Driver'")
    $col = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $r.Updates) {
        if ($UpdateIds -contains $u.Identity.UpdateID) {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$col.Add($u)
        }
    }
    if (-not $col.Count) { Write-KLog 'As atualizações escolhidas não estão mais disponíveis (já instaladas?)' Aviso; return $false }
    Write-KLog "Baixando $($col.Count) driver(s) do Windows Update" Info
    $dl = $s.CreateUpdateDownloader(); $dl.Updates = $col
    [void]$dl.Download()
    Write-KLog 'Instalando' Info
    $in = $s.CreateUpdateInstaller(); $in.Updates = $col
    $res = $in.Install()
    $reiniciar = $false
    for ($i = 0; $i -lt $col.Count; $i++) {
        $rc = $res.GetUpdateResult($i)
        $ok = $rc.ResultCode -in 2, 3
        Write-KLog "$($col.Item($i).Title): $(if ($ok) { 'instalado' } else { "falhou (código $($rc.ResultCode), 0x{0:X8})" -f $rc.HResult })" $(if ($ok) { 'OK' } else { 'Erro' })
        if ($rc.RebootRequired) { $reiniciar = $true }
    }
    if ($reiniciar -or $res.RebootRequired) { Write-KLog 'Reinicie o PC pra concluir a troca dos drivers' Aviso }
    $true
}

function Install-KDriverNvidia {
    param([Parameter(Mandatory)]$Item)
    $arq = Join-Path $KB.Raiz "cache\drivers\$(Split-Path $Item.Url -Leaf)"
    try {
        if (-not (Test-Path $arq)) {
            Write-KLog "Baixando o driver NVIDIA $($Item.Disponivel) (uns 700 MB)" Info
            try { Get-KDownload $Item.Url $arq | Out-Null }
            catch { if ($Item.UrlAlternativa) { $arq = Join-Path $KB.Raiz "cache\drivers\$(Split-Path $Item.UrlAlternativa -Leaf)"; Get-KDownload $Item.UrlAlternativa $arq | Out-Null } else { throw } }
        }
        $s = Get-AuthenticodeSignature -LiteralPath $arq
        if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'NVIDIA Corporation') {
            Remove-Item -LiteralPath $arq -Force -ErrorAction SilentlyContinue
            throw 'assinatura do pacote não é da NVIDIA; arquivo descartado'
        }
        Write-KLog 'Instalando o driver NVIDIA (a tela pisca algumas vezes)' Info
        $p = Start-Process -FilePath $arq -ArgumentList '-s', '-noreboot', '-noeula', '-nofinish', '-nosplash' -PassThru -ErrorAction Stop
        Wait-KArvoreProcesso $p.Id 30
        $nova = (Get-CimInstance Win32_VideoController | Where-Object PNPDeviceID -eq $Item.DeviceId).DriverVersion
        if ($nova -and (Get-KVersaoNvidia $nova) -eq $Item.Disponivel) {
            Write-KLog "Driver NVIDIA $($Item.Disponivel) instalado" OK
            Remove-Item -LiteralPath $arq -Force -ErrorAction SilentlyContinue
            return $true
        }
        Write-KLog "O instalador terminou, mas a versão ainda é $(Get-KVersaoNvidia $nova). Reinicie e confira; o pacote ficou em $arq" Aviso
    } catch { Write-KLog "Driver NVIDIA: $($_.Exception.Message)" Erro }
    $false
}

# Cópia dos drivers que vão ser trocados (pra voltar, se precisar: Restaurar backup)
function Save-KDriversAtuais($Itens) {
    $infs = @($Itens | Where-Object { $_.Inf -like 'oem*.inf' } | ForEach-Object Inf | Select-Object -Unique)
    if (-not $infs) { return }
    $dir = Join-Path $KB.Raiz "estado\drivers\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($i in $infs) { Invoke-KNativo "$env:SystemRoot\System32\pnputil.exe" @('/export-driver', $i, "`"$dir`"") -SemLog | Out-Null }
    Write-KLog "Drivers atuais guardados em $dir" Detalhe
}

function Install-KAtualizacoesDrivers {
    param([Parameter(Mandatory)][object[]]$Itens)
    $Itens = @($Itens | Where-Object { $_.Situacao -eq 'Atualização' })
    if (-not $Itens) { Write-KLog 'Nenhuma atualização de driver marcada' Aviso; return }
    New-KPontoRestauracao 'K-Bench - drivers' | Out-Null
    Save-KDriversAtuais $Itens
    $wu = @($Itens | Where-Object { $_.Fonte -eq 'Windows Update' -and $_.UpdateId } | ForEach-Object UpdateId)
    if ($wu) { Install-KDriversWindowsUpdate $wu | Out-Null }
    foreach ($n in $Itens | Where-Object Fonte -eq 'NVIDIA') { Install-KDriverNvidia $n | Out-Null }
}

# ── Repositório de drivers (C:\Windows\System32\DriverStore) ───
# Pacotes de terceiros: em uso (por dispositivo ou impressora) e versões velhas que ficaram pra trás.
function Get-KDriverStore {
    $emUso = @{}
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) { if ($d.InfName -like 'oem*.inf') { $emUso[$d.InfName.ToLower()] = $true } }
    $pastasImp = @{}
    foreach ($p in Get-PrinterDriver -ErrorAction SilentlyContinue) { if ($p.InfPath) { $pastasImp[(Split-Path $p.InfPath).ToLower()] = $true } }
    $pacotes = foreach ($w in Get-WindowsDriver -Online -ErrorAction SilentlyContinue) {
        $pasta = Split-Path $w.OriginalFileName
        [pscustomobject]@{
            Inf = "$($w.Driver)".ToLower(); Original = (Split-Path $w.OriginalFileName -Leaf).ToLower(); Pasta = $pasta
            Versao = $w.Version; Data = $w.Date; Classe = $w.ClassName; Fornecedor = $w.ProviderName
            EmUso = [bool]($emUso["$($w.Driver)".ToLower()] -or $pastasImp[$pasta.ToLower()])
            Bytes = [long](Get-ChildItem -LiteralPath $pasta -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        }
    }
    # Velho = não está em uso e existe versão mais nova do mesmo pacote (mesmo .inf original, mesmo fornecedor)
    foreach ($g in $pacotes | Group-Object Original, Fornecedor) {
        $novo = $g.Group | Sort-Object { try { [version]$_.Versao } catch { [version]'0.0' } }, Data -Descending | Select-Object -First 1
        foreach ($p in $g.Group) { $p | Add-Member Antigo ([bool](-not $p.EmUso -and $p -ne $novo -and $g.Count -gt 1)) -PassThru }
    }
}

function Remove-KDriversAntigos {
    $velhos = @(Get-KDriverStore | Where-Object Antigo)
    if (-not $velhos) { Write-KLog 'Nenhuma versão antiga de driver sobrando' OK; return }
    $total = 0; $n = 0
    foreach ($v in $velhos) {
        # Sem /force: se algo ainda usar, o pnputil recusa e o pacote fica
        $r = Invoke-KNativo "$env:SystemRoot\System32\pnputil.exe" @('/delete-driver', $v.Inf) -SemLog
        if ($r.Codigo -eq 0) { $n++; $total += $v.Bytes; Write-KLog "Removido: $($v.Original) $($v.Versao) ($($v.Fornecedor))" Detalhe }
    }
    Write-KLog "$n versão(ões) antiga(s) de driver removida(s): $(Format-KTamanho $total) liberados" OK
}

# ── Backup / restaurar (formatar sem caçar driver) ─────────────
function Backup-KDrivers {
    param([Parameter(Mandatory)][string]$Destino, [switch]$SemVideo)
    $m = Get-KFabricante
    $nome = "Drivers_$(($m.Marca + '_' + $m.Modelo) -replace '[^\w\-]+', '_')_$(Get-Date -Format 'yyyyMMdd')"
    $dir = Join-Path $Destino $nome
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    # Só os em uso (o repositório guarda versões velhas também: exportar tudo dá vários GB à toa)
    # Extensões e componentes (áudio Realtek/DTS etc.) não aparecem como "em uso" no WMI: vão os mais novos de cada.
    $usados = @(Get-KDriverStore | Where-Object { $_.EmUso -or ($_.Classe -in 'Extension', 'SoftwareComponent', 'Printer', 'Image' -and -not $_.Antigo) })
    if ($SemVideo) { $usados = @($usados | Where-Object Classe -ne 'Display') }
    Write-KLog "Exportando $($usados.Count) driver(s) em uso$(if ($SemVideo) { ', sem o de vídeo' }) (só os de terceiros; os do Windows já vêm na instalação)" Info
    $r = $null
    foreach ($u in $usados) { $r = Invoke-KNativo "$env:SystemRoot\System32\pnputil.exe" @('/export-driver', $u.Inf, "`"$dir`"") -SemLog }
    $n = @(Get-ChildItem $dir -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count
    $tam = Format-KTamanho ((Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
    Set-Content (Join-Path $dir 'LEIA-ME.txt') -Encoding UTF8 -Value @(
        "Backup de drivers do K-Bench - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
        "PC: $($m.Marca) $($m.Modelo)  |  série $($m.Serial)  |  $env:COMPUTERNAME"
        ''
        'Pra restaurar depois de formatar: K-Bench > Drivers > Restaurar backup e escolha esta pasta.'
        'Ou, no prompt como administrador: pnputil /add-driver "<esta pasta>\*.inf" /subdirs /install'
    )
    if ($n) { Write-KLog "$n driver(s) salvos em $dir ($tam)" OK } else { Write-KLog "Nenhum driver exportado (código $($r.Codigo))" Erro }
    $dir
}

function Restore-KDrivers {
    param([Parameter(Mandatory)][string]$Origem)
    $n = @(Get-ChildItem $Origem -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count
    if (-not $n) { Write-KLog "Nenhum .inf em $Origem" Erro; return }
    New-KPontoRestauracao 'K-Bench - restaurar drivers' | Out-Null
    Write-KLog "Instalando $n driver(s) de $Origem (o Windows só aplica os que servem neste PC)" Info
    $r = Invoke-KNativo "$env:SystemRoot\System32\pnputil.exe" @('/add-driver', "`"$(Join-Path $Origem '*.inf')`"", '/subdirs', '/install') -SemLog
    $ok = @($r.Saida | Where-Object { $_ -match 'oem\d+\.inf' }).Count
    Write-KLog "Concluído: $ok pacote(s) adicionados ao Windows$(if ($r.Codigo -eq 3010) { '. Reinicie pra terminar' })" $(if ($r.Codigo -in 0, 3010, 259) { 'OK' } else { 'Aviso' })
}

# ── Fonte 3: fabricante do PC ──────────────────────────────────
function Get-KFabricante {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $pr = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $serial = "$((Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber)".Trim()
    $fab = "$($cs.Manufacturer)".Trim()
    $generico = $fab -match 'System manufacturer|To Be Filled|Default string|O\.E\.M|^$'
    $marca = switch -Regex ($(if ($generico) { "$($bb.Manufacturer)" } else { $fab })) {
        'Acer'                 { 'Acer' }
        'Lenovo'               { 'Lenovo' }
        'Dell'                 { 'Dell' }
        'HP|Hewlett'           { 'HP' }
        'Samsung'              { 'Samsung' }
        'Positivo'             { 'Positivo' }
        'ASUS'                 { 'ASUS' }
        'Micro-Star|MSI'       { 'MSI' }
        'Gigabyte'             { 'Gigabyte' }
        'ASRock'               { 'ASRock' }
        'Microsoft'            { 'Microsoft' }
        default                { if ($generico) { "$($bb.Manufacturer)".Trim() } else { $fab } }
    }
    # Lenovo: Model é o "machine type" (20XX...); o nome comercial vem em Version
    $modelo = if ($marca -eq 'Lenovo' -and $pr.Version) { "$($pr.Version)".Trim() } elseif ($generico) { "placa $($bb.Product)".Trim() } else { "$($cs.Model)".Trim() }
    if ($serial -match 'To Be Filled|Default string|O\.E\.M|^0+$|^$') { $serial = '' }
    $ferr = $null; $pagina = $null
    switch ($marca) {
        'Dell'    { $ferr = @{ Nome = 'Dell Command | Update'; Pacote = 'Dell.CommandUpdate.Universal'; Fonte = 'winget'; Auto = $true }
                    $pagina = 'https://www.dell.com/support/home/pt-br' }
        'Lenovo'  { if ($modelo -match 'Think') { $ferr = @{ Nome = 'Lenovo System Update'; Pacote = 'Lenovo.SystemUpdate'; Fonte = 'winget'; Auto = $true } }
                    $pagina = 'https://pcsupport.lenovo.com/br/pt' }
        'HP'      { if ($modelo -match 'Elite|Pro(Book|Desk|One)|ZBook|Z\d') { $ferr = @{ Nome = 'HP Image Assistant'; Pacote = 'HP.ImageAssistant'; Fonte = 'winget'; Auto = $true } }
                    $pagina = 'https://support.hp.com/br-pt/drivers' }
        'Samsung' { $ferr = @{ Nome = 'Samsung Update'; Pacote = '9NQ3HDB99VBF'; Fonte = 'msstore'; Auto = $false }
                    $pagina = 'https://www.samsung.com/br/support/' }
        'Acer'     { $pagina = 'https://www.acer.com/br-pt/support/drivers-and-manuals' }
        'Positivo' { $pagina = 'https://www.positivotecnologia.com.br/suporte/' }
        'ASUS'     { $pagina = 'https://www.asus.com/br/support/download-center/' }
        'MSI'      { $pagina = 'https://br.msi.com/support/download' }
        'Gigabyte' { $pagina = 'https://www.gigabyte.com/br/Support' }
        'ASRock'   { $pagina = 'https://www.asrock.com/support/index.pt.asp' }
    }
    [pscustomobject]@{
        Marca = $marca; Modelo = $modelo; Serial = $serial; Montado = $generico
        Ferramenta = $(if ($ferr) { [pscustomobject]$ferr }); Pagina = $pagina
    }
}

# Instala a ferramenta oficial do fabricante e, quando ela tem modo automático, já atualiza
function Invoke-KFerramentaFabricante {
    $m = Get-KFabricante
    $f = $m.Ferramenta
    if (-not $f) { Write-KLog "$($m.Marca) não tem ferramenta oficial de atualização automática" Aviso; return $false }
    if (-not (Install-KWinget)) { return $false }
    Write-KLog "Instalando $($f.Nome) (oficial da $($m.Marca))" Info
    $r = Invoke-KWinget -Acao install -Pacote $f.Pacote -Fonte $f.Fonte
    if ($r.Resultado -notin 'OK', 'JaInstalado', 'Atual', 'Reinicio') { Write-KLog "$($f.Nome): não instalou ($($r.Hex))" Erro; return $false }
    if (-not $f.Auto) { Write-KLog "$($f.Nome) instalado. Abra pelo Iniciar e clique em atualizar" OK; return $true }
    $log = Join-Path $KB.Raiz "logs\$($m.Marca)-drivers-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    switch ($m.Marca) {
        'Dell' {
            $exe = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $exe) { Write-KLog 'dcu-cli.exe não encontrado' Erro; return $false }
            Write-KLog 'Dell Command | Update procurando e instalando (drivers, BIOS e firmware da Dell)' Info
            $x = Invoke-KNativo $exe @('/applyUpdates', '-silent', '-reboot=disable', '-autoSuspendBitLocker=enable', "-outputLog=`"$log.log`"") -TimeoutMin 90
            switch ($x.Codigo) { 0 { Write-KLog 'Dell: atualizações instaladas' OK } 1 { Write-KLog 'Dell: instalado, reinicie pra concluir' Aviso } 5 { Write-KLog 'Dell: reinicie pra concluir' Aviso }
                                 500 { Write-KLog 'Dell: nada a atualizar' OK } default { Write-KLog "Dell Command | Update terminou com código $($x.Codigo) (log: $log.log)" Aviso } }
        }
        'Lenovo' {
            $exe = "${env:ProgramFiles(x86)}\Lenovo\System Update\tvsu.exe"
            if (-not (Test-Path $exe)) { Write-KLog 'tvsu.exe não encontrado' Erro; return $false }
            Write-KLog 'Lenovo System Update procurando e instalando (pode levar bastante)' Info
            $p = Start-Process $exe -ArgumentList '/CM', '-search', 'A', '-action', 'INSTALL', '-includerebootpackages', '1,3,4', '-noicon', '-noreboot', '-nolicense' -PassThru
            Wait-KArvoreProcesso $p.Id 120
            Write-KLog 'Lenovo System Update terminou. Reinicie se ele instalou BIOS/firmware' OK
        }
        'HP' {
            $exe = @(Get-ChildItem "$env:ProgramFiles\HP", "${env:ProgramFiles(x86)}\HP", 'C:\SWSetup' -Recurse -Filter HPImageAssistant.exe -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
            if (-not $exe) { Write-KLog 'HPImageAssistant.exe não encontrado' Erro; return $false }
            Write-KLog 'HP Image Assistant analisando e instalando drivers da HP' Info
            $p = Start-Process $exe -ArgumentList '/Operation:Analyze', '/Action:Install', '/Selection:All', '/Category:Drivers', '/Silent', "/ReportFolder:`"$log`"" -PassThru
            Wait-KArvoreProcesso $p.Id 120
            Write-KLog "HP Image Assistant terminou (relatório em $log)" OK
        }
    }
    $true
}
