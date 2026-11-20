# K-Bench — Especificação

> Bancada de técnico para Windows: manutenção, diagnóstico, debloat, programas,
> runtimes e drivers, com perfis por tipo de atendimento.
> Substitui o WinUtil (Chris Titus) e evolui o `Manutencao-Windows.ps1` (v2).

Status: especificação levantada em 18/11/2026. Nada implementado ainda.

---

## 1. Decisões gerais

| Tema | Decisão |
|---|---|
| Tecnologia | PowerShell 5.1 + WPF (XAML). Roda em qualquer Windows sem instalar nada. |
| Interface | GUI (abas, checkboxes, presets) **e** CLI: os mesmos módulos rodam por parâmetro (silencioso/agendado). |
| Windows | **Foco no Windows 11** (~90% dos casos). Win 10 = melhor esforço: recurso exclusivo do 11 fica oculto no 10, nunca limita o projeto. |
| Distribuição | Repositório **público** no GitHub + one-liner `irm <url>/install.ps1 \| iex`. |
| Instaladores | Nunca hospedados no repo. Baixados na hora da fonte oficial (winget, site do fabricante). |
| Segredos | Nada sensível no repo (senhas, chaves, dados da loja). |
| Perfis | Criados/editados **dentro do programa** ("Salvar como perfil"). |
| Desfazer | **Por tweak**: cada ajuste sabe se reverter, + ponto de restauração antes de aplicar. |
| Visual | **Escuro por padrão**, inspirado no macOS: barra lateral, cartões arredondados, interruptores, barra de título escura. |
| Atendimentos/relatório pro cliente | Fora do escopo por enquanto. |

## 2. Módulos

### 2.1 Manutenção (evolução do script v2) — **MVP**
- Modos **Rápida** (semanal) e **Completa** (reparo), como hoje.
- Correções sobre a v2:
  - `Repair-Volume -Scan` no lugar de `chkdsk /scan`; `-SpotFix` quando possível (em vez de `fsutil dirty set`).
  - Verificar resultado do SFC: extrair linhas `[SR]` do `CBS.log` → "limpo / corrigido / não corrigível".
  - DISM com `-FonteISO` opcional (`install.wim` do pendrive) quando o WU falha (0x800f081f).
  - `DISM /StartComponentCleanup` (WinSxS) além do cleanmgr.
  - Remover pastas vazias nos temporários.
  - Ponto de restauração antes do modo Completa.
  - `-Silencioso`: sem `Read-Host`/`Pause`.
- Reparos direcionados (menu): reset do Windows Update, reset de rede, WMI,
  índice de pesquisa, cache de ícones, spooler de impressão, apps da Store,
  agendar teste de memória.
- Guiar reparo in-place (ISO "manter arquivos e apps" / "Corrigir problemas usando o Windows Update").

### 2.2 Diagnóstico — **MVP**
Objetivo: explicar **por que** o PC está lento, não só limpar.
- Disco do sistema em HDD (→ recomendar SSD), RAM total e pressão de memória.
- Programas na inicialização (Run, Startup, tarefas agendadas e serviços de terceiros).
- Bloatware / antivírus duplicado (McAfee, Norton + Defender, utilitários OEM).
- Uptime (Inicialização Rápida), plano de energia.
- SMART real via `smartctl` (setores realocados/pendentes, NVMe % usado) com veredito.
- Eventos: WHEA, disco (7/51/153), Kernel-Power 41, minidumps (BSOD).
- Monitor de Confiabilidade (apps que mais travam), drivers com erro (`Get-PnpDevice`).
- Bateria (capacidade vs. fábrica + `powercfg /batteryreport`).
- Saída: resumo na tela + relatório HTML local para o técnico.

### 2.2.1 Bateria e energia (notebooks) — entregue junto com a F1
- Diagnóstico: saúde e ciclos, limite de carga (80%), consumo real em W pelas descargas do relatório do Windows,
  perda na suspensão, desligamentos incompletos (Kernel-Power 41 + `SleepInProgress`), Inicialização Rápida,
  ação da tampa, turbo/EPP/modo de energia na bateria, dispositivos e origens de ativação,
  GPU dedicada (estado D0/D3 + processos segurando ela), serviços que gastam à toa, CPU em repouso.
- Correções com desfazer (valor anterior em `C:\ProgramData\K-Bench\estado\energia.json`):
  tampa suspende, Inicialização Rápida, turbo desligado na bateria, EPP 70, modo "Melhor eficiência",
  tela apaga em 5 min, hibernar após 1 h, suspender após 15 min, timers de ativação, PCIe/USB, Wake-on-LAN,
  serviços Intel (PresentMon manual, Energy Server desativado), agentes de fabricante que pedem timer de 1 ms
  (detectados na Análise de 60 s e mapeados pra serviço/tarefa de logon).
- A situação de cada correção olha o estado real do Windows: "Não pegou" quando foi registrada mas não teve efeito.
  Modo de energia via API `powrprof` (`PowerSetUserConfiguredDCPowerMode`); o registro é ignorado pelo Windows.
- Antes/depois: consumo (W) e Kernel-Power 41 comparados a partir da data da primeira correção.
- Ferramentas: `powercfg /energy` (60 s, lido por classe CSS) e relatório de bateria do Windows.
- Acer sem app do fabricante: limite de carga de 80% e calibração pela classe WMI `root\wmi\BatteryControl`
  ({79772EC5-04B1-4bfd-843C-61E7F77B6CC9}, a mesma do driver acer-wmi-battery do Linux). Gravado na BIOS/EC.
- Teste de consumo guiado (parado / vídeo / navegação, brilho fixo em 40%): W pela taxa do controlador (`root\wmi BatteryStatus.DischargeRate`)
  e comparação com a queda da carga restante pra detectar **medidor da bateria descalibrado** (% despenca com consumo normal).

### 2.3 Debloat + tweaks — **entregue (v1, 19/11/2026)**
- Níveis: Seguro / Recomendado / Agressivo + Preferência (nunca marcado por nível). OneDrive removido; Edge só silenciado.
- Catálogo como função PowerShell (`src\Tweaks\Catalogo.ps1`) em vez de JSON: viaja no arquivo único e no runspace.
- Ajustes de HKCU também vão pro usuário padrão (contas novas). Situação "O Windows desfez" quando uma atualização reverte.
- Apps removidos: o desfazer tenta re-registrar e, se não der, abre a página na Microsoft Store.
- Remover apps inúteis, telemetria, Copilot/recomendações, ajustes do Explorer, plano de energia etc.
- Cada tweak: nome, descrição clara, categoria, versão mínima do Windows, **aplicar** e **desfazer**.
- Modelo declarativo (ver §4) para o desfazer ser automático e o valor original ficar salvo.

### 2.4 Programas — **entregue (v1, 19/11/2026)**
- Catálogo em `src\Programas\Catalogo.ps1` (~40 programas + runtimes), presets Básico / MC Serviços / Técnico / Runtimes.
- Situação lida do `winget export` (JSON, independe do idioma), Click-to-Run (Office) e recursos do Windows.
- Instala pra máquina toda (`--scope machine`) e cai pro escopo de usuário só quando o pacote não tem outro.
  Pacote de usuário é desinstalado sem elevação por uma tarefa agendada temporária (o winget elevado recusa).
- Microsoft 365: `setup.exe` do CDN oficial, com assinatura da Microsoft conferida; sem OneDrive/Teams/Access/Publisher.
- Sem winget (LTSC, Windows recém-instalado): registra o App Installer ou baixa de aka.ms/getwinget.
- Catálogo via **winget**, com categorias e presets.
- Microsoft 365 via **ODT** (Office Deployment Tool) com XML pronto. Ativação = conta/licença do cliente.
- Instaladores fora do winget: baixados da URL oficial do fabricante.
- Preferência por gratuitos/open source (ex.: Affinity em vez de Adobe).

### 2.4.1 Desinstalador completo (tipo Revo) — **entregue (v1, 19/11/2026)**
- Lista o que está instalado (registro de desinstalação de máquina, 32 bits e usuário + apps da Store).
- Roda o desinstalador do programa em silêncio quando dá (MSI, Inno, NSIS, QuietUninstallString); senão, interativo.
  Instalação quebrada (desinstalador sumiu) vai direto pros rastros.
- Caça rastros: pasta de instalação, pastas com o nome do programa (Program Files, ProgramData, AppData, Documentos),
  chaves em HKLM/HKCU\Software, atalhos do Iniciar/Área de Trabalho, serviços, tarefas agendadas e inicialização.
- Confiança Alta (marcado) / Média (revisar: dados do usuário, pasta do fabricante). Nunca toca pasta protegida
  nem pasta que contém outro programa instalado. Apps do Chrome não confundem a pasta do Chrome.
- Backup: arquivos na Lixeira; registro (.reg), tarefas (.xml) e serviços em `estado\desinstalados\<data>_<programa>`.

### 2.5 Runtimes (presente em quase todos os perfis) — **entregue junto com a 2.4**
Equivalente aos "All-in-One", mas com pacotes **oficiais** via winget:
- Visual C++ 2005–2022 (x86 + x64).
- .NET Desktop Runtime 6 / 8 / 9 + .NET Framework 3.5.
- DirectX End-User Runtime (junho/2010).
- Opcionais: Java, XNA, OpenAL, WebView2.

### 2.6 Drivers — **entregue (v1, 19/11/2026)**
Objetivo: "tipo Driver Booster, do jeito certo" — tudo de fonte oficial e rastreável.

Como ficou na v1:
- **Windows Update pela API do próprio Windows** (Microsoft.Update.Session, `Type='Driver'`), casando pelo Hardware ID de cada
  dispositivo. Funciona mesmo com o ajuste "drivers fora do Windows Update" ligado (ele só tira os drivers do automático).
  Primeira busca: 1 a 3 min.
- **NVIDIA**: consulta oficial por Device ID (a mesma do app da NVIDIA), compara com a versão instalada (32.0.16.2124 = 621.24),
  baixa o pacote do site da NVIDIA (assinatura conferida) e instala em silêncio. AMD/Intel: Windows Update + Intel DSA (Programas).
- **Fabricante**: Dell Command | Update (CLI), Lenovo System Update (linha Think, CLI), HP Image Assistant (linhas
  Elite/Pro/ZBook, só drivers), Samsung Update (Store). Acer, Positivo, ASUS, linhas domésticas Lenovo/HP e PCs montados:
  abre a página oficial de suporte com o número de série copiado.
- Antes de instalar: ponto de restauração + `pnputil /export-driver` dos drivers que vão ser trocados (`estado\drivers\<data>`).
- **Backup/restaurar** (pra formatar sem caçar driver): exporta só os em uso + extensões/componentes/impressoras/scanners
  (o repositório guarda versões velhas: exportar tudo dava 7 GB neste Acer). Opção de deixar o vídeo de fora (~4 GB).
- **Limpar versões antigas** do repositório (substituídas e fora de uso; `pnputil /delete-driver` sem /force).
- Perfil: opção "Atualizar drivers" (ligada em MC e Clientes), roda logo depois dos ajustes.

Plano original:
1. **Microsoft Update Catalog** por Hardware ID (cobre qualquer dispositivo com driver publicado).
2. **Fabricantes de chip** (chipset/vídeo): NVIDIA (consulta do driver mais recente por GPU), AMD (instaladores silenciosos), Intel.
3. **Fabricantes de PC**: Lenovo (catálogo por machine type), Dell (Command Update CLI), HP (Image Assistant).
   Acer / Samsung / Positivo (sem API oficial): camadas 1 e 2 + abrir a página de suporte exata pelo número de série.
4. **Tela de comparação**: dispositivo · versão instalada · versão disponível · fonte · status
   (atualizado / desatualizado / sem driver).

Marcas mais frequentes: Samsung, Acer, Positivo, Lenovo, montados. Máquina de teste: Acer Nitro V15 ANV15-51.

### 2.6.1 Impressoras — **entregue (v1, 19/11/2026)**
- Procura na rede: varredura do /24 (portas 631/9100/515) + WS-Discovery (o mesmo anúncio que o Windows usa). Modelo por
  IPP → SNMP (hrDeviceDescr) → metadados WSD → título da página web; o log mostra, por IP, as portas e de onde veio o modelo.
  Lista com nome editável; você marca quais adicionar.
- IP muda (DHCP): a porta se chama `KB_<MAC>` e aponta pro **nome** da impressora (Epson = `EPSON` + 6 últimos do MAC) quando ele resolve;
  senão, pelo IP — e cada "Procurar na rede" corrige o IP da porta sozinho.
- Gerenciador (impressoras deste PC): renomear, página de teste, tornar padrão, atualizar driver (quando o catálogo tem versão mais nova),
  trocar pro driver oficial, remover só a impressora ou impressora + driver (o driver só sai se nenhuma outra usar).
- Driver oficial por modelo (Epson Brasil, assinatura da Epson conferida): o pacote autoextraível é um zip, então
  o K-Bench extrai e instala só o INF do modelo (`pnputil` + `Add-PrinterDriver`), sem telas. Epson Scan 2: `Setup.exe /SI`.
- Catálogo: L3250 e L4160. Modelo fora do catálogo: driver que já esteja no Windows, senão o genérico "Microsoft IPP Class Driver".
- L6170: sem página no site da Epson Brasil (descontinuada); usa o driver que já estiver no PC ou o IPP genérico.

### 2.7 Perfis — **entregue (v1, 19/11/2026)**
- Padrão no código (Meu / MC / Clientes); editar grava `C:\ProgramData\K-Bench\perfis\<id>.json`, que passa a valer. "Restaurar padrão" apaga a cópia.
- Editor na GUI: ajustes, programas, impressoras (drivers + impressoras da rede lembradas pelo MAC), manutenção no fim, contas novas.
- "Copiar deste PC" monta o perfil a partir da máquina atual. Exportar/importar .json (pendrive). `-Perfil arquivo.json` na CLI.
- Aplicar = ponto de restauração → ajustes pendentes → programas que faltam → drivers/scanner/impressoras lembradas → manutenção.
Um perfil = seleção de tweaks + programas + runtimes + drivers/impressoras + configurações.

| Perfil | Conteúdo inicial |
|---|---|
| **Meu** | Configuração pessoal do técnico. |
| **MC Serviços** (loja da família: documentos, consultas online, design, gráfica rápida) | Epson **L3250** (driver + Epson Scan 2 + impressora configurada), Chrome (perfil com Gmail), Google Drive para Windows, Affinity, runtimes. Uso intenso de web apps (Canva, Bling, ChatGPT, iLovePDF/IMG). A detalhar. |
| **Clientes** | Debloat, programas básicos, Microsoft 365, runtimes. Sem impressoras. |

## 3. CLI (exemplos)

```powershell
# GUI
irm <url>/install.ps1 | iex

# Sem interface
.\kbench.ps1 -Manutencao Rapida -Silencioso
.\kbench.ps1 -Perfil mc -Modulos Runtimes,Programas,Tweaks
.\kbench.ps1 -Diagnostico -Saida C:\K-Bench\relatorio.html
```

## 4. Arquitetura proposta

```
K-Bench/
├─ install.ps1            # bootstrap do one-liner: baixa a release e abre o K-Bench
├─ kbench.ps1             # ponto de entrada (GUI ou CLI conforme parâmetros)
├─ build.ps1              # junta tudo num único .ps1 pra distribuição (como o WinUtil)
├─ src/
│  ├─ Core/               # log, checagem de admin, versão do Windows, download, winget
│  ├─ Manutencao/
│  ├─ Diagnostico/
│  ├─ Tweaks/
│  ├─ Programas/
│  ├─ Runtimes/
│  ├─ Drivers/
│  └─ Perfis/
├─ gui/MainWindow.xaml
├─ config/
│  ├─ tweaks.json         # tweaks declarativos (registro, serviço, appx, tarefa, script)
│  ├─ apps.json           # catálogo winget / URLs oficiais
│  └─ runtimes.json
└─ perfis/                # meu.json, mc.json, clientes.json
```

**Tweak declarativo** (o desfazer sai de graça):

```json
{
  "id": "desativar-copilot",
  "nome": "Desativar Copilot",
  "descricao": "Remove o Copilot da barra e desativa via política.",
  "categoria": "Privacidade",
  "minBuild": 22000,
  "acoes": [
    { "tipo": "registro", "caminho": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\WindowsCopilot",
      "nome": "TurnOffWindowsCopilot", "valor": 1, "tipoValor": "DWord" }
  ]
}
```
Ao aplicar, o valor original é salvo em `C:\ProgramData\K-Bench\estado\`; o desfazer restaura exatamente o que havia.

Logs: `C:\ProgramData\K-Bench\logs\<PC>_<data>.log`.

## 5. Roadmap

| Fase | Entrega |
|---|---|
| **F1 — MVP** | Core + estrutura + build em arquivo único; Manutenção (com correções) + Diagnóstico; CLI; GUI básica com aba Manutenção/Diagnóstico. |
| F2 | Runtimes + Programas (winget, presets, Microsoft 365 via ODT). |
| F3 | Debloat/tweaks com desfazer por tweak. |
| F4 | Editor de perfis na GUI + perfis Meu / MC / Clientes (Epson L3250). |
| F5 ✅ | Drivers (Windows Update por Hardware ID, NVIDIA, ferramentas OEM, tela de comparação, backup/restaurar). |
| Futuro | Registro de atendimentos e relatório para o cliente. |

## 6. Pendências
- Detalhar o perfil MC Serviços (outros equipamentos, configurações do Chrome, scanner).
- Criar o repositório público no GitHub (usuário/nome).
- Nome definitivo (provisório: **K-Bench**).
