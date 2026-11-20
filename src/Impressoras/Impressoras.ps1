# ============================================================
#  Impressoras: acha impressoras na rede, baixa o driver oficial
#  do fabricante, cria e gerencia as impressoras deste PC.
#  O IP muda no DHCP: a porta do K-Bench se chama KB_<MAC> e cada
#  procura na rede corrige o endereço sozinha. Se o nome da
#  impressora (Epson = EPSON + final do MAC) responder, usa o nome.
# ============================================================

# Driver oficial por modelo. Modelo = nome exato do driver no INF; Versao = DriverVer do INF.
function Get-KModelosImpressora {
    $epson = 'https://ftp.epson.com/latin/drivers/inkjet'
    @(
        [pscustomobject]@{ Id = 'EpsonL3250'; Nome = 'Epson L3250'; Modelo = 'EPSON L3250 Series'; Assinante = 'Epson'; Versao = [version]'3.80.5.0'
                           Driver = "$epson/L3250_L3251_X64_38005_LA.exe"; Scanner = "$epson/L3250_L3251_EScan2_67810_LA.exe"
                           Suporte = 'https://epson.com.br/Suporte/Impressoras/Impressoras-multifuncionais/Epson-L/Epson-L3250/s/SPT_C11CJ67301' }
        [pscustomobject]@{ Id = 'EpsonL4160'; Nome = 'Epson L4160'; Modelo = 'EPSON L4160 Series'; Assinante = 'Epson'; Versao = [version]'2.100.0.0'
                           Driver = "$epson/L4160_X64_2100_LA.exe"; Scanner = "$epson/L4160_EScan2_65230_LA.exe"
                           Suporte = 'https://epson.com.br/Suporte/Impressoras/Impressoras-multifuncionais/Epson-L/Epson-L4160/s/SPT_C11CG23301' }
    )
}

function Get-KModeloPorNome([string]$Nome) {
    $n = ConvertTo-KChaveNome $Nome
    # "EPSON L3250 Series", "Epson L3250", "EPSON1A2B3C (L3250 Series)": o número do modelo basta
    Get-KModelosImpressora | Where-Object { $n -and ($n -eq (ConvertTo-KChaveNome $_.Modelo) -or $n.Contains((ConvertTo-KChaveNome $_.Nome)) -or
                                                     ($n -match 'epson' -and $n.Contains((ConvertTo-KChaveNome ($_.Nome -replace '^\S+\s+', ''))))) } | Select-Object -First 1
}

function ConvertTo-KVersaoDriver([uint64]$v) {
    [version]('{0}.{1}.{2}.{3}' -f ($v -shr 48), (($v -shr 32) -band 0xFFFF), (($v -shr 16) -band 0xFFFF), ($v -band 0xFFFF))
}

# Baixa (com assinatura do fabricante conferida) e abre o pacote autoextraível (é um zip)
function Get-KPacoteFabricante {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Assinante)
    $arq = Join-Path $KB.Raiz "cache\drivers\$(Split-Path $Url -Leaf)"
    $dir = $arq -replace '\.exe$', ''
    if (Test-Path "$dir\.ok") { return $dir }
    if (-not (Test-Path $arq)) {
        Write-KLog "Baixando $(Split-Path $Url -Leaf) do site da $Assinante" Info
        Get-KDownload $Url $arq | Out-Null
    }
    $s = Get-AuthenticodeSignature -LiteralPath $arq
    if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch $Assinante) {
        Remove-Item -LiteralPath $arq -Force -ErrorAction SilentlyContinue
        throw "assinatura de $(Split-Path $arq -Leaf) não é da $Assinante; arquivo descartado"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    [IO.Compression.ZipFile]::ExtractToDirectory($arq, $dir)
    Set-Content "$dir\.ok" ''
    $dir
}

# ── Driver ─────────────────────────────────────────────────────
# Devolve o nome do driver instalado (o oficial, um que já existe no PC, ou o genérico IPP) ou $null.
# -Forcar: reinstala o oficial mesmo se já houver um (atualizar driver).
function Install-KDriverImpressora {
    param([Parameter(Mandatory)][string]$Modelo, [bool]$Ipp = $true, [switch]$Forcar)
    $cat = Get-KModeloPorNome $Modelo
    if (-not $Forcar -or -not $cat) {
        if (Get-PrinterDriver -Name $Modelo -ErrorAction SilentlyContinue) { return $Modelo }
        # Já está no repositório de drivers do Windows (instalado antes ou nativo)?
        try { Add-PrinterDriver -Name $Modelo -ErrorAction Stop; Write-KLog "Driver $Modelo (já estava no Windows)" OK; return $Modelo } catch {}
    }
    if ($cat) {
        try {
            $dir = Get-KPacoteFabricante $cat.Driver $cat.Assinante
            $infs = @(Get-ChildItem $dir -Recurse -Filter *.inf | Where-Object {
                $t = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $t -match '(?m)^\s*Class\s*=\s*Printer' -and $t.Contains("`"$($cat.Modelo)`"") })
            if (-not $infs) { throw 'o pacote não tem INF desse modelo' }
            foreach ($i in $infs) { Invoke-KNativo "$env:SystemRoot\System32\pnputil.exe" @('/add-driver', "`"$($i.FullName)`"", '/install') -SemLog | Out-Null }
            # Utilitário USB da Epson (nível de tinta pelo cabo), se vier no pacote
            foreach ($u in Get-ChildItem $dir -Recurse -Filter *.inf | Where-Object { (Get-Content $_.FullName -Raw) -match '(?m)^\s*Class\s*=\s*USB' }) {
                Invoke-KNativo "$env:SystemRoot\System32\pnputil.exe" @('/add-driver', "`"$($u.FullName)`"") -SemLog | Out-Null
            }
            Add-PrinterDriver -Name $cat.Modelo -ErrorAction Stop
            $v = (Get-PrinterDriver -Name $cat.Modelo -ErrorAction SilentlyContinue).DriverVersion
            Write-KLog "Driver oficial $($cat.Modelo) instalado$(if ($v) { " (versão $(ConvertTo-KVersaoDriver $v))" })" OK
            return $cat.Modelo
        } catch { Write-KLog "Driver oficial de $Modelo`: $($_.Exception.Message)" Erro }
    }
    if ($Ipp) {
        try {
            Add-PrinterDriver -Name 'Microsoft IPP Class Driver' -ErrorAction Stop
            Write-KLog "$Modelo sem driver no catálogo: usando o genérico do Windows (imprime, mas sem nível de tinta)" Aviso
            return 'Microsoft IPP Class Driver'
        } catch {}
    }
    Write-KLog "Sem driver pra $Modelo. Baixe no site do fabricante." Erro
    $null
}

# Epson Scan 2 (o mesmo app serve pra todas as multifuncionais; o pacote de cada modelo traz o módulo dele)
function Install-KScannerImpressora {
    param([Parameter(Mandatory)][string]$Modelo)
    $cat = Get-KModeloPorNome $Modelo
    if (-not $cat -or -not $cat.Scanner) { return $false }
    $marca = "$($KB.Raiz)\estado\scanner_$($cat.Id).ok"
    if ((Test-Path $marca) -and (Get-KAppsInstalados | Where-Object Nome -like 'Epson Scan 2*')) { return $true }
    try {
        $dir = Get-KPacoteFabricante $cat.Scanner $cat.Assinante
        Write-KLog "Instalando Epson Scan 2 ($($cat.Nome))" Info
        $p = Start-Process -FilePath (Join-Path $dir 'Setup.exe') -ArgumentList '/SI' -WorkingDirectory $dir -PassThru -ErrorAction Stop
        Wait-KArvoreProcesso $p.Id 20
        if (Get-KAppsInstalados | Where-Object Nome -like 'Epson Scan 2*') {
            New-Item -ItemType Directory -Path (Split-Path $marca) -Force | Out-Null
            Set-Content $marca (Get-Date -Format s)
            Write-KLog 'Epson Scan 2 instalado (na primeira vez, ele procura o scanner na rede sozinho)' OK
            return $true
        }
        Write-KLog 'Epson Scan 2 não apareceu como instalado' Aviso
    } catch { Write-KLog "Epson Scan 2: $($_.Exception.Message)" Erro }
    $false
}

# ── Identificar o modelo: IPP, SNMP, WSD, página web ───────────
function Get-KIppAtributos([string]$Ip) {
    $ms = New-Object IO.MemoryStream
    $w = { param([byte[]]$b) $ms.Write($b, 0, $b.Length) }
    $s16 = { param([int]$v) [byte[]]@((($v -shr 8) -band 255), ($v -band 255)) }
    $attr = { param([byte]$tag, [string]$n, [string]$v)
        & $w @($tag); & $w (& $s16 $n.Length); & $w ([Text.Encoding]::ASCII.GetBytes($n))
        $vb = [Text.Encoding]::UTF8.GetBytes($v); & $w (& $s16 $vb.Length); & $w $vb }
    & $w @(2, 0, 0, 0x0B, 0, 0, 0, 1, 1)                         # IPP 2.0, Get-Printer-Attributes
    & $attr 0x47 'attributes-charset' 'utf-8'
    & $attr 0x48 'attributes-natural-language' 'en'
    & $attr 0x45 'printer-uri' "ipp://$Ip`:631/ipp/print"
    & $attr 0x44 'requested-attributes' 'printer-make-and-model'
    foreach ($x in 'printer-name', 'printer-info', 'printer-dns-sd-name') { & $attr 0x44 '' $x }
    & $w @(3)
    $req = [Net.HttpWebRequest]::Create("http://$Ip`:631/ipp/print")
    $req.Method = 'POST'; $req.ContentType = 'application/ipp'; $req.Timeout = 3000; $req.ReadWriteTimeout = 3000
    $body = $ms.ToArray(); $rs = $req.GetRequestStream(); $rs.Write($body, 0, $body.Length); $rs.Close()
    $resp = $req.GetResponse()
    $br = New-Object IO.BinaryReader $resp.GetResponseStream()
    $b = $br.ReadBytes(65536); $resp.Close()
    $o = @{}; $pos = 8; $nome = ''
    while ($pos -lt $b.Length - 3) {
        $tag = $b[$pos]; $pos++
        if ($tag -eq 3) { break }
        if ($tag -lt 0x10) { continue }
        $nl = $b[$pos] * 256 + $b[$pos + 1]; $pos += 2
        if ($nl) { $nome = [Text.Encoding]::ASCII.GetString($b, $pos, $nl) }
        $pos += $nl
        $vl = $b[$pos] * 256 + $b[$pos + 1]; $pos += 2
        if ($tag -ge 0x40 -and -not $o[$nome]) { $o[$nome] = [Text.Encoding]::UTF8.GetString($b, $pos, $vl) }
        $pos += $vl
    }
    $o
}

# SNMP v1 GET (comunidade public). Padrão: hrDeviceDescr.1 = "EPSON L3250 Series" nas Epson.
function Get-KSnmpTexto([string]$Ip, [string]$Oid = '1.3.6.1.2.1.25.3.2.1.3.1', [int]$TimeoutMs = 1200) {
    $n = @($Oid.Split('.') | ForEach-Object { [int]$_ })
    $ob = New-Object System.Collections.Generic.List[byte]
    $ob.Add([byte](40 * $n[0] + $n[1]))
    foreach ($x in $n[2..($n.Count - 1)]) {
        $pilha = New-Object System.Collections.Generic.List[byte]
        $pilha.Insert(0, [byte]($x -band 0x7F)); $x = $x -shr 7
        while ($x -gt 0) { $pilha.Insert(0, [byte](($x -band 0x7F) -bor 0x80)); $x = $x -shr 7 }
        $ob.AddRange($pilha)
    }
    $tlv = { param([byte]$t, [byte[]]$c) [byte[]](@($t, [byte]$c.Length) + $c) }
    $oidB = $ob.ToArray()
    $vb = & $tlv 0x30 ([byte[]]((& $tlv 0x06 $oidB) + [byte[]](5, 0)))
    $pdu = & $tlv 0xA0 ([byte[]]([byte[]](2, 1, 1, 2, 1, 0, 2, 1, 0) + (& $tlv 0x30 $vb)))
    $msg = & $tlv 0x30 ([byte[]]([byte[]](2, 1, 0) + (& $tlv 0x04 ([Text.Encoding]::ASCII.GetBytes('public'))) + $pdu))
    $u = New-Object Net.Sockets.UdpClient
    $u.Client.ReceiveTimeout = $TimeoutMs
    try {
        [void]$u.Send($msg, $msg.Length, $Ip, 161)
        $ep = New-Object Net.IPEndPoint ([Net.IPAddress]::Any, 0)
        $r = $u.Receive([ref]$ep)
    } catch { return $null } finally { $u.Close() }
    # O valor vem logo depois do OID na resposta: 0x04 <tamanho> <texto>
    for ($i = 0; $i -le $r.Length - $oidB.Length; $i++) {
        $igual = $true
        for ($j = 0; $j -lt $oidB.Length; $j++) { if ($r[$i + $j] -ne $oidB[$j]) { $igual = $false; break } }
        if (-not $igual) { continue }
        $p = $i + $oidB.Length
        if ($r[$p] -ne 0x04) { return $null }
        $len = $r[$p + 1]; $p += 2
        if ($len -band 0x80) { $nb = $len -band 0x7F; $len = 0; for ($k = 0; $k -lt $nb; $k++) { $len = $len * 256 + $r[$p + $k] }; $p += $nb }
        return ([Text.Encoding]::UTF8.GetString($r, $p, $len)).Trim([char]0, ' ')
    }
    $null
}

# WS-Discovery: o mesmo anúncio que o Windows usa pra achar impressoras (multicast 239.255.255.250:3702)
function Find-KWsd([string[]]$MeusIps, [int]$EsperaMs = 3000) {
    $achados = @{}
    foreach ($meu in $MeusIps) {
        $probe = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:wsd="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:wprt="http://schemas.microsoft.com/windows/2006/08/wdp/print">' +
                 '<soap:Header><wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To><wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>' +
                 "<wsa:MessageID>urn:uuid:$([guid]::NewGuid())</wsa:MessageID></soap:Header><soap:Body><wsd:Probe><wsd:Types>wprt:PrintDeviceType</wsd:Types></wsd:Probe></soap:Body></soap:Envelope>"
        $u = $null
        try {
            $u = New-Object Net.Sockets.UdpClient (New-Object Net.IPEndPoint ([Net.IPAddress]::Parse($meu), 0))
            $u.Client.ReceiveTimeout = 500
            $b = [Text.Encoding]::UTF8.GetBytes($probe)
            [void]$u.Send($b, $b.Length, '239.255.255.250', 3702); Start-Sleep -Milliseconds 150
            [void]$u.Send($b, $b.Length, '239.255.255.250', 3702)
            $fim = (Get-Date).AddMilliseconds($EsperaMs)
            while ((Get-Date) -lt $fim) {
                try {
                    $ep = New-Object Net.IPEndPoint ([Net.IPAddress]::Any, 0)
                    $x = [Text.Encoding]::UTF8.GetString($u.Receive([ref]$ep))
                    if ($x -notmatch 'PrintDeviceType|print') { continue }
                    $achados[$ep.Address.ToString()] = [pscustomobject]@{
                        Endereco = [regex]::Match($x, '<[^>]*Address>\s*([^<]+?)\s*<').Groups[1].Value
                        XAddr = (([regex]::Match($x, '<[^>]*XAddrs>\s*([^<]+?)\s*<').Groups[1].Value) -split '\s+' | Where-Object { $_ -match '^http://\d' } | Select-Object -First 1)
                    }
                } catch {}
            }
        } catch {} finally { if ($u) { $u.Close() } }
    }
    $achados
}

function Get-KWsdModelo($Wsd) {
    if (-not $Wsd.XAddr) { return $null }
    $get = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">' +
           "<soap:Header><wsa:To>$($Wsd.Endereco)</wsa:To><wsa:Action>http://schemas.xmlsoap.org/ws/2004/09/transfer/Get</wsa:Action>" +
           "<wsa:MessageID>urn:uuid:$([guid]::NewGuid())</wsa:MessageID><wsa:ReplyTo><wsa:Address>http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous</wsa:Address></wsa:ReplyTo></soap:Header><soap:Body/></soap:Envelope>"
    try {
        $r = Invoke-WebRequest -Uri $Wsd.XAddr -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($get)) -ContentType 'application/soap+xml; charset=utf-8' -UseBasicParsing -TimeoutSec 4
        $t = $r.Content
        $c = { param($n) [regex]::Match($t, "<[^>]*:$n[^>]*>\s*([^<]+?)\s*<").Groups[1].Value }
        [pscustomobject]@{ Fabricante = (& $c 'Manufacturer'); Modelo = (& $c 'ModelName'); Nome = (& $c 'FriendlyName') }
    } catch { $null }
}

function Get-KModeloWeb([string]$Ip) {
    try {
        $r = Invoke-WebRequest -Uri "http://$Ip/" -UseBasicParsing -TimeoutSec 3 -MaximumRedirection 3
        $t = [regex]::Match($r.Content, '<title>\s*([^<]+?)\s*</title>', 'IgnoreCase').Groups[1].Value
        if ($t -match '(EPSON|HP|Brother|Canon|Samsung|Lexmark|Kyocera|Ricoh|Xerox)[^<]{2,40}') { $Matches[0].Trim() }
    } catch { $null }
}

function Resolve-KNome([string]$Nome, [string]$Ip, [int]$TimeoutMs = 2500) {
    try {
        $t = [Net.Dns]::GetHostAddressesAsync($Nome)
        if ($t.Wait($TimeoutMs)) { return [bool]($t.Result | Where-Object { $_.ToString() -eq $Ip }) }
    } catch {}
    $false
}

# ── Instaladas neste PC ────────────────────────────────────────
function Get-KImpressorasInstaladas {
    $portas = @{}
    foreach ($p in Get-PrinterPort -ErrorAction SilentlyContinue) { $portas[$p.Name] = $p }
    $epsonNet = @{}
    foreach ($k in Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\EpsonNet Print Port\Ports' -ErrorAction SilentlyContinue) {
        $epsonNet[$k.PSChildName] = Get-ItemProperty $k.PSPath
    }
    $drivers = @{}
    foreach ($d in Get-PrinterDriver -ErrorAction SilentlyContinue) { $drivers[$d.Name] = $d }
    $padrao = (Get-CimInstance Win32_Printer -Filter 'Default=TRUE' -ErrorAction SilentlyContinue).Name
    foreach ($i in Get-Printer -ErrorAction SilentlyContinue) {
        $po = $portas[$i.PortName]; $en = $epsonNet[$i.PortName]
        $mac = if ($en.MacAddress) { "$($en.MacAddress)".ToUpper() } elseif ($i.PortName -match '^KB_([0-9A-F]{12})$') { $Matches[1] } else { '' }
        # Fila WSD da Epson vem como "EPSON1A2B3C (L3250 Series)": o código é o final do MAC
        $macFim = if ($mac) { $mac.Substring(6) } elseif ($i.Name -match 'EPSON([0-9A-F]{6})') { $Matches[1].ToUpper() } else { '' }
        $host_ = if ($po.PrinterHostAddress) { $po.PrinterHostAddress } elseif ($en) { $en.PrinterAddress } else { '' }
        $dv = $drivers[$i.DriverName]
        $ver = if ($dv.DriverVersion) { ConvertTo-KVersaoDriver $dv.DriverVersion }
        $cat = Get-KModeloPorNome $i.DriverName
        [pscustomobject]@{
            Nome = $i.Name; Driver = $i.DriverName; DriverVersao = $ver; Porta = $i.PortName; Host = $host_; Mac = $mac; MacFim = $macFim
            Tipo = if ($i.PortName -like 'WSD-*') { 'WSD' } elseif ($en) { 'EpsonNet' } elseif ($po.PrinterHostAddress) { 'TCP/IP' } elseif ($i.PortName -like 'USB*') { 'USB' } else { 'Local' }
            Padrao = ($i.Name -eq $padrao)
            Virtual = ($i.DriverName -match 'Microsoft Print To PDF|OneNote|XPS|Fax' -or $i.PortName -in 'PORTPROMPT:', 'nul:', 'SHRFAX:')
            Catalogo = $(if ($cat) { $cat.Id })
            Atualizacao = [bool]($cat -and $ver -and $cat.Versao -gt $ver)
            VersaoNova = $(if ($cat) { $cat.Versao })
        }
    }
}

# Instala/atualiza o driver oficial e põe a impressora nele
function Set-KDriverImpressora {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Modelo, [switch]$Forcar)
    $drv = Install-KDriverImpressora $Modelo -Ipp $false -Forcar:$Forcar
    if (-not $drv) { return $false }
    $i = Get-Printer -Name $Nome -ErrorAction SilentlyContinue
    if ($i -and $i.DriverName -ne $drv) {
        try { Set-Printer -Name $Nome -DriverName $drv -ErrorAction Stop; Write-KLog "$Nome agora usa o driver $drv" OK }
        catch { Write-KLog "Trocar o driver de $Nome`: $($_.Exception.Message)" Erro; return $false }
    }
    $true
}

function Rename-KImpressora([string]$Nome, [string]$Novo) {
    try { Rename-Printer -Name $Nome -NewName $Novo -ErrorAction Stop; Write-KLog "Impressora renomeada: $Nome → $Novo" OK; $true }
    catch { Write-KLog "Renomear $Nome`: $($_.Exception.Message)" Erro; $false }
}

function Set-KImpressoraPadrao([string]$Nome) {
    # Sem isso o Windows troca a padrão sozinho pra "a última usada"
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -ErrorAction SilentlyContinue
    $p = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object Name -eq $Nome
    if ($p -and (Invoke-CimMethod -InputObject $p -MethodName SetDefaultPrinter).ReturnValue -eq 0) { Write-KLog "$Nome agora é a impressora padrão" OK; $true }
    else { Write-KLog "Não deu pra definir $Nome como padrão" Erro; $false }
}

function Send-KPaginaTeste([string]$Nome) {
    $p = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object Name -eq $Nome
    if ($p -and (Invoke-CimMethod -InputObject $p -MethodName PrintTestPage).ReturnValue -eq 0) { Write-KLog "Página de teste enviada pra $Nome" OK }
    else { Write-KLog "Não deu pra imprimir a página de teste em $Nome" Erro }
}

# Remove a impressora; com -Driver tira também o driver (se nenhuma outra impressora usar) e a porta do K-Bench
function Remove-KImpressora {
    param([Parameter(Mandatory)][string]$Nome, [switch]$Driver)
    $i = Get-Printer -Name $Nome -ErrorAction SilentlyContinue
    if (-not $i) { Write-KLog "$Nome não existe mais" Aviso; return }
    try { Remove-Printer -Name $Nome -ErrorAction Stop; Write-KLog "Impressora removida: $Nome" OK }
    catch { Write-KLog "Remover $Nome`: $($_.Exception.Message)" Erro; return }
    if ($i.PortName -like 'KB_*' -and -not (Get-Printer | Where-Object PortName -eq $i.PortName)) { Remove-PrinterPort -Name $i.PortName -ErrorAction SilentlyContinue }
    if (-not $Driver) { return }
    $outras = @(Get-Printer | Where-Object DriverName -eq $i.DriverName)
    if ($outras) { Write-KLog "Driver $($i.DriverName) mantido: ainda usado por $(($outras | ForEach-Object Name) -join ', ')" Aviso; return }
    try {
        Restart-Service Spooler -Force -ErrorAction SilentlyContinue   # solta arquivos do driver presos no spooler
        Remove-PrinterDriver -Name $i.DriverName -RemoveFromDriverStore -ErrorAction Stop
        Write-KLog "Driver removido: $($i.DriverName)" OK
    } catch { Write-KLog "Driver $($i.DriverName): $($_.Exception.Message)" Aviso }
}

# ── Procurar na rede ───────────────────────────────────────────
function Find-KImpressorasRede {
    param([int]$EsperaMs = 2500)
    $meus = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
              ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { $_ -notlike '169.254.*' })
    if (-not $meus) { Write-KLog 'Sem rede: conecte o PC na rede da impressora' Aviso; return }

    # 1) WSD (como o Windows acha) em paralelo com 2) varredura de portas de impressão no /24
    $tarefas = New-Object System.Collections.Generic.List[object]
    foreach ($meu in $meus) {
        $base = ($meu -split '\.')[0..2] -join '.'
        Write-KLog "Procurando impressoras em $base.0/24" Info
        foreach ($i in 1..254) {
            if ("$base.$i" -eq $meu) { continue }
            foreach ($porta in 631, 9100, 515) {
                $c = New-Object Net.Sockets.TcpClient
                $tarefas.Add(@{ Ip = "$base.$i"; Porta = $porta; C = $c; T = $c.ConnectAsync("$base.$i", $porta) })
            }
        }
    }
    $wsd = Find-KWsd $meus $EsperaMs        # já espera $EsperaMs, tempo em que as conexões TCP também completam
    $abertos = @{}
    foreach ($t in $tarefas) {
        if ($t.T.Status -eq 'RanToCompletion' -and $t.C.Connected) { $abertos[$t.Ip] = @($abertos[$t.Ip]) + $t.Porta }
        try { $t.C.Close() } catch {}
    }
    $ips = @(@($abertos.Keys) + @($wsd.Keys) | Sort-Object -Unique)
    Write-KLog "Respostas: $(@($abertos.Keys).Count) com porta de impressão, $(@($wsd.Keys).Count) por WSD" Detalhe

    $instaladas = @(Get-KImpressorasInstaladas)
    $vizinhos = @{}
    foreach ($n in Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue) { $vizinhos[$n.IPAddress] = ($n.LinkLayerAddress -replace '-', '').ToUpper() }

    foreach ($ip in $ips | Sort-Object { [version]$_ }) {
        $portas = @($abertos[$ip] | Where-Object { $_ })
        $modelo = ''; $fonte = ''; $nomeWsd = ''
        if ($portas -contains 631) { try { $a = Get-KIppAtributos $ip; $modelo = "$($a['printer-make-and-model'])".Trim(); if ($modelo) { $fonte = 'IPP' } } catch {} }
        if (-not $modelo) { $s = Get-KSnmpTexto $ip; if ($s) { $modelo = $s; $fonte = 'SNMP' } }
        if ($wsd[$ip]) {
            $w = Get-KWsdModelo $wsd[$ip]
            if ($w) { $nomeWsd = $w.Nome; if (-not $modelo -and $w.Modelo) { $modelo = (@($w.Fabricante, $w.Modelo) | Where-Object { $_ } | Select-Object -Unique) -join ' '; $fonte = 'WSD' } }
        }
        if (-not $modelo) { $h = Get-KModeloWeb $ip; if ($h) { $modelo = $h; $fonte = 'página web' } }
        Write-KLog "$ip`: portas $(if ($portas) { $portas -join ',' } else { 'nenhuma' })$(if ($wsd[$ip]) { ' · WSD' }) · modelo $(if ($modelo) { "$modelo ($fonte)" } else { 'desconhecido' })" Detalhe
        if (-not $modelo -and -not $wsd[$ip] -and $portas -notcontains 9100) { continue }   # 515 sozinho costuma ser outra coisa

        if (-not $vizinhos[$ip]) {
            foreach ($n in Get-NetNeighbor -IPAddress $ip -ErrorAction SilentlyContinue) { $vizinhos[$ip] = ($n.LinkLayerAddress -replace '-', '').ToUpper() }
        }
        $mac = $vizinhos[$ip]
        if ($mac -eq '000000000000') { $mac = '' }
        # Nome que não muda com o IP: Epson = EPSON + 6 últimos do MAC
        $nomeRede = $null
        $candidatos = @()
        if ($mac -and "$modelo $nomeWsd" -match 'EPSON') { $candidatos += "EPSON$($mac.Substring(6))" }
        try { $rev = [Net.Dns]::GetHostEntry($ip).HostName; if ($rev -and $rev -ne $ip) { $candidatos += ($rev -split '\.')[0] } } catch {}
        foreach ($c in $candidatos | Select-Object -Unique) {
            if (Resolve-KNome $c $ip) { $nomeRede = $c; break }
            if (Resolve-KNome "$c.local" $ip) { $nomeRede = "$c.local"; break }
        }
        $hostAlvo = if ($nomeRede) { $nomeRede } else { $ip }

        # Porta do K-Bench pra esta impressora com IP velho: corrige
        if ($mac) {
            $pk = Get-CimInstance Win32_TCPIPPrinterPort -Filter "Name='KB_$mac'" -ErrorAction SilentlyContinue
            if ($pk -and $pk.HostAddress -ne $hostAlvo) {
                try { Set-CimInstance -InputObject $pk -Property @{ HostAddress = $hostAlvo } -ErrorAction Stop; Write-KLog "Endereço da impressora $mac atualizado: $($pk.HostAddress) → $hostAlvo" OK } catch {}
            }
        }
        $ja = @($instaladas | Where-Object { ($mac -and ($_.Mac -eq $mac -or ($_.MacFim -and $mac.EndsWith($_.MacFim)))) -or ($_.Host -and ($_.Host -eq $ip -or $_.Host -eq $nomeRede)) })
        $cat = if ($modelo) { Get-KModeloPorNome $modelo }
        $sufixo = if ($mac) { $mac.Substring(6) } else { ($ip -split '\.')[-1] }
        $nomeModelo = if ($cat) { $cat.Modelo } elseif ($modelo) { $modelo } else { 'Impressora' }
        [pscustomobject]@{
            Ip = $ip; Mac = $mac; Modelo = $(if ($modelo) { $modelo } else { 'modelo desconhecido' }); ModeloFonte = $fonte
            NomeWsd = $nomeWsd; Host = $hostAlvo; HostFixo = [bool]$nomeRede
            Nome = "$nomeModelo ($sufixo)"
            Driver = $(if ($cat) { 'Oficial' } elseif ($modelo -and (Get-PrinterDriver -Name $modelo -ErrorAction SilentlyContinue)) { 'Já no PC' } elseif ($portas -contains 631) { 'Genérico (IPP)' } else { 'Sem driver' })
            Raw = ($portas -contains 9100); Lpr = ($portas -contains 515)
            Instalada = [bool]$ja; InstaladaComo = (@($ja | ForEach-Object Nome) -join ', ')
        }
    }
}

function Add-KImpressoraRede {
    param([Parameter(Mandatory)]$Impressora, [string]$Nome, [bool]$Scanner = $true)
    $i = $Impressora
    if (-not $Nome) { $Nome = $i.Nome }
    Write-KLog "Adicionando $Nome ($($i.Modelo) em $($i.Host))" Info
    if (-not $i.Raw -and -not $i.Lpr) { Write-KLog "$Nome só respondeu por WSD (sem porta de impressão aberta): adicione pelo Windows em Configurações > Impressoras" Aviso; return $false }
    $drv = Install-KDriverImpressora $i.Modelo -Ipp $true
    if (-not $drv) { return $false }
    $porta = if ($i.Mac) { "KB_$($i.Mac)" } else { "KB_$($i.Host)" }
    try {
        if (-not (Get-PrinterPort -Name $porta -ErrorAction SilentlyContinue)) {
            if ($i.Raw) { Add-PrinterPort -Name $porta -PrinterHostAddress $i.Host -PortNumber 9100 -SNMP 1 -SNMPCommunity public -ErrorAction Stop }
            else { Add-PrinterPort -Name $porta -LprHostAddress $i.Host -LprQueueName 'lp' -ErrorAction Stop }
        }
        if (Get-Printer -Name $Nome -ErrorAction SilentlyContinue) { Write-KLog "Já existe uma impressora chamada $Nome" Aviso; return $true }
        Add-Printer -Name $Nome -DriverName $drv -PortName $porta -ErrorAction Stop
        Write-KLog "$Nome pronta$(if (-not $i.HostFixo) { ' (pelo IP; se ele mudar, é só Procurar na rede de novo que o K-Bench corrige)' })" OK
    } catch { Write-KLog "$Nome`: $($_.Exception.Message)" Erro; return $false }
    if ($Scanner -and $drv -ne 'Microsoft IPP Class Driver') { Install-KScannerImpressora $i.Modelo | Out-Null }
    $true
}
