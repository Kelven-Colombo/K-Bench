# K-Bench

Bancada de técnico para Windows 11 (e 10): manutenção, diagnóstico e reparos,
com interface gráfica e linha de comando. Veja o escopo completo em [SPEC.md](SPEC.md).

## Usar

Em um PowerShell (o K-Bench pede administrador sozinho):

```powershell
irm https://raw.githubusercontent.com/Kelven-Colombo/K-Bench/main/install.ps1 | iex
```

Ou baixe o **[K-Bench.exe](https://github.com/Kelven-Colombo/K-Bench/releases/latest/download/K-Bench.exe)**
(bom pra levar no pendrive). Ele abre como administrador, pega a versão mais nova do GitHub e, sem internet,
usa a cópia que vem dentro dele (`K-Bench.exe -Offline` força isso). Não é assinado: na primeira vez o Windows
mostra "o Windows protegeu o computador" → *Mais informações* → *Executar assim mesmo*.

Ou, com o código local:

```powershell
powershell -ExecutionPolicy Bypass -File .\kbench.ps1
```

### Linha de comando

```powershell
.\kbench.ps1 -Manutencao Rapida -Silencioso
.\kbench.ps1 -Manutencao Completa -FonteISO D:\Win11.iso -AgendarReparoDisco
.\kbench.ps1 -Diagnostico -Saida C:\relatorio.html
.\kbench.ps1 -Reparo WindowsUpdate,Rede
.\kbench.ps1 -ListarReparos
.\kbench.ps1 -Bateria                           # diagnóstico de bateria/energia + correções disponíveis
.\kbench.ps1 -CorrecaoEnergia Tampa,Turbo       # aplica (guarda o valor anterior)
.\kbench.ps1 -DesfazerEnergia Turbo             # volta ao valor anterior
.\kbench.ps1 -ListarTweaks                       # situação de cada ajuste de debloat/otimização
.\kbench.ps1 -Otimizar Recomendado               # aplica o que falta até o nível (Seguro/Recomendado/Agressivo)
.\kbench.ps1 -Tweaks MouseSemAceleracao,ModoEscuro  /  -DesfazerTweaks Copilot  (-SoEstaConta: não grava no usuário padrão)
.\kbench.ps1 -Limite80 Desligar                    # Acer: limite de carga de 80% direto na BIOS (sem NitroSense)
.\kbench.ps1 -Calibrar Iniciar                    # Acer: calibração da bateria pela BIOS (na tomada)
.\kbench.ps1 -TesteConsumo                       # mede W parado / vídeo / navegação e checa o medidor da bateria
.\kbench.ps1 -ListarProgramas                    # programas e runtimes do catálogo e se já estão instalados
.\kbench.ps1 -Preset MC                          # instala o que falta do preset (Basico/MC/Tecnico/Runtimes)
.\kbench.ps1 -Instalar Chrome,VLC,M365Pessoal  /  -Desinstalar Zoom
.\kbench.ps1 -AtualizarProgramas                 # winget upgrade --all
.\kbench.ps1 -ListarPerfis                       # Meu / MC Serviços / Clientes + os seus
.\kbench.ps1 -Perfil mc                          # aplica o perfil (pula o que já estiver feito)
.\kbench.ps1 -Perfil D:\perfil.json -Modulos Tweaks,Programas   # perfil exportado, só parte dele
.\kbench.ps1 -ProcurarImpressoras                # impressoras da rede (modelo, IP, nome fixo, driver)
.\kbench.ps1 -Drivers                            # compara os drivers com o Windows Update e a NVIDIA
.\kbench.ps1 -AtualizarDrivers                   # instala as atualizações (ponto de restauração + cópia dos atuais)
.\kbench.ps1 -BackupDrivers E:\ -SemVideo        # copia os drivers em uso pro pendrive (antes de formatar)
.\kbench.ps1 -RestaurarDrivers E:\Drivers_Acer_Nitro_ANV15-51_20261119
.\kbench.ps1 -LimparDrivers                      # apaga versões antigas que sobraram no repositório de drivers
.\kbench.ps1 -ListarInstalados                   # tudo que está instalado (Painel de Controle + Store)
.\kbench.ps1 -DesinstalarCompleto "Zoom*"        # desinstala e remove rastros de confiança alta (-Forcar: mesmo se o desinstalador falhar)
```

Logs e relatórios ficam em `C:\ProgramData\K-Bench\logs`.

## Desenvolver

| Arquivo | Função |
|---|---|
| `kbench.ps1` | Ponto de entrada (GUI sem parâmetros, CLI com parâmetros) |
| `src\Core` | Log, admin, versão do Windows, execução de comandos nativos |
| `src\Manutencao` | Limpeza, otimização, sistema de arquivos, DISM, SFC, reparos |
| `src\Diagnostico` | Verificações de lentidão/saúde e relatório HTML |
| `src\Tweaks` | Debloat e otimizações: motor (registro, serviço, tarefa, appx, script) com desfazer + catálogo por nível |
| `src\Bateria` | Bateria e energia: consumo real, suspensão, GPU dedicada, plano de energia e correções com desfazer |
| `src\Gui` + `gui\MainWindow.xaml` | Interface WPF (trabalho pesado em runspace separado) |
| `build.ps1` | Junta tudo em `dist\kbench.ps1` (arquivo único da release) |
| `tools\Test-KBench.ps1` | Testes rápidos sem alterar o sistema |
| `tools\Preview-KGui.ps1` | Renderiza cada página da GUI em PNG (fora da tela) pra revisar o visual |

Regras:
- Arquivos `.ps1` em **UTF-8 com BOM** (o PowerShell 5.1 estraga acentos sem BOM).
- Funções públicas no formato `Verbo-KNome`: é assim que a GUI as encontra e leva pro runspace.
- Nada de variáveis globais além de `$KB`: o runspace da GUI só recebe as funções e o `$KB`.

### Publicar uma versão

```powershell
.\build.ps1
```

Crie uma release no GitHub anexando `dist\kbench.ps1`. O `install.ps1` sempre baixa a última.

## Licença

MIT. Veja [LICENSE](LICENSE).
