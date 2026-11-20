# ============================================================
#  Catálogo de tweaks. Níveis:
#    Seguro       pode ir em qualquer PC de cliente, ninguém sente falta
#    Recomendado  padrão de formatação do técnico
#    Agressivo    tira coisas que alguém pode usar; só quando se sabe o que o PC faz
#    Preferência  gosto pessoal; nunca é marcado pelos níveis, só à mão / perfil
#  Fica como função (não JSON) pra viajar junto no arquivo único e no runspace da GUI.
# ============================================================

function Get-KTweaks {
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    $r = { param($K, $N, $V, $Tipo = 'DWord') @{ T = 'reg'; K = $K; N = $N; V = $V; Tipo = $Tipo } }
    $apps = { param([string[]]$Nomes) $Nomes | ForEach-Object { @{ T = 'appx'; N = $_ } } }

    @(
        # ── Explorer e barra de tarefas ──
        [pscustomobject]@{ Id = 'Extensoes'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Seguro'; Explorer = $true
            Nome = 'Mostrar extensões de arquivo'
            Descricao = 'Mostra ".pdf", ".exe" etc. Ajuda a perceber arquivo falso (ex.: "foto.jpg.exe").'
            Acoes = @(& $r $adv 'HideFileExt' 0) }
        [pscustomobject]@{ Id = 'Ocultos'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Recomendado'; Explorer = $true
            Nome = 'Mostrar arquivos ocultos'
            Descricao = 'Mostra pastas como AppData. Arquivos protegidos do sistema continuam escondidos.'
            Acoes = @(& $r $adv 'Hidden' 1) }
        [pscustomobject]@{ Id = 'EncerrarTarefa'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Recomendado'; Explorer = $true; MinBuild = 22631
            Nome = '"Encerrar tarefa" no botão direito da barra'
            Descricao = 'Fecha programa travado direto pela barra de tarefas, sem abrir o Gerenciador.'
            Acoes = @(& $r "$adv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1) }
        [pscustomobject]@{ Id = 'MenuAntigo'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Recomendado'; Explorer = $true; MinBuild = 22000
            Nome = 'Menu do botão direito completo'
            Descricao = 'Volta o menu de contexto clássico, sem o "Mostrar mais opções".'
            Acoes = @(@{ T = 'script'
                Teste    = 'Test-Path ''HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'''
                Aplicar  = 'New-Item ''HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'' -Value '''' -Force | Out-Null'
                Desfazer = 'Remove-Item ''HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'' -Recurse -Force -ErrorAction SilentlyContinue' }) }
        [pscustomobject]@{ Id = 'Widgets'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Seguro'; Explorer = $true; MinBuild = 22000
            Nome = 'Sem Widgets (notícias e clima)'
            Descricao = 'Tira o painel de notícias da barra. Gasta rede e memória à toa.'
            Acoes = @(& $r 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0) }
        [pscustomobject]@{ Id = 'ChatTeams'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Recomendado'; Explorer = $true; MinBuild = 22000
            Nome = 'Sem Teams pessoal (Chat)'
            Descricao = 'Remove o Teams gratuito/Chat que vem no Windows 11. Não mexe no Teams de trabalho (novo Teams).'
            Acoes = @(& $r $adv 'TaskbarMn' 0) + @(& $apps 'MicrosoftTeams') }
        [pscustomobject]@{ Id = 'BarraEsquerda'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Preferência'; Explorer = $true; MinBuild = 22000
            Nome = 'Barra de tarefas alinhada à esquerda'
            Descricao = 'Botão Iniciar no canto, como no Windows 10.'
            Acoes = @(& $r $adv 'TaskbarAl' 0) }
        [pscustomobject]@{ Id = 'PesquisaIcone'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Preferência'; Explorer = $true
            Nome = 'Pesquisa só como ícone'
            Descricao = 'Troca a caixa de pesquisa larga por um ícone de lupa.'
            Acoes = @(& $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1) }
        [pscustomobject]@{ Id = 'SemVisaoTarefas'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Preferência'; Explorer = $true
            Nome = 'Sem botão Visão de Tarefas'
            Descricao = 'Tira o botão de áreas de trabalho virtuais (Win+Tab continua funcionando).'
            Acoes = @(& $r $adv 'ShowTaskViewButton' 0) }
        [pscustomobject]@{ Id = 'AbrirEsteComputador'; Categoria = 'Explorer e barra de tarefas'; Nivel = 'Preferência'; Explorer = $true
            Nome = 'Explorer abre em "Este Computador"'
            Descricao = 'Em vez da "Página Inicial" com arquivos recentes.'
            Acoes = @(& $r $adv 'LaunchTo' 1) }

        # ── Anúncios e IA ──
        [pscustomobject]@{ Id = 'Anuncios'; Categoria = 'Anúncios, IA e sugestões'; Nivel = 'Seguro'; Explorer = $true
            Nome = 'Sem anúncios e sugestões'
            Descricao = 'Tira apps instalados sozinhos (Candy Crush, TikTok…), sugestões no Iniciar, Configurações, tela de bloqueio, notificações de "dicas" e propaganda do OneDrive no Explorer.'
            Acoes = @(
                'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
                'RotatingLockScreenOverlayEnabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
                'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled' |
                    ForEach-Object { & $r $cdm $_ 0 }) + @(
                & $r $adv 'Start_IrisRecommendations' 0
                & $r $adv 'Start_AccountNotifications' 0
                & $r $adv 'ShowSyncProviderNotifications' 0
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested' 'Enabled' 0
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1) }
        [pscustomobject]@{ Id = 'Publicidade'; Categoria = 'Anúncios, IA e sugestões'; Nivel = 'Seguro'
            Nome = 'Sem ID de publicidade'
            Descricao = 'Apps não recebem um identificador pra anúncio personalizado; sem "experiências personalizadas" com dados de diagnóstico.'
            Acoes = @(
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1) }
        [pscustomobject]@{ Id = 'BingIniciar'; Categoria = 'Anúncios, IA e sugestões'; Nivel = 'Recomendado'; Explorer = $true
            Nome = 'Pesquisa do Iniciar sem Bing'
            Descricao = 'A pesquisa procura só no PC: mais rápida e sem mandar o que você digita pra internet.'
            Acoes = @(& $r 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1) }
        [pscustomobject]@{ Id = 'Copilot'; Categoria = 'Anúncios, IA e sugestões'; Nivel = 'Recomendado'; Explorer = $true; MinBuild = 22000
            Nome = 'Sem Copilot'
            Descricao = 'Desativa o Copilot do Windows e remove o app. O Copilot no navegador/Office não é afetado.'
            Acoes = @(
                & $r 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
                & $r $adv 'ShowCopilotButton' 0) + @(& $apps 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider') }
        [pscustomobject]@{ Id = 'Recall'; Categoria = 'Anúncios, IA e sugestões'; Nivel = 'Seguro'; MinBuild = 26100
            Nome = 'Sem Recall'
            Descricao = 'Impede o Windows de tirar "fotos" da tela pra busca por IA (PCs Copilot+).'
            Acoes = @(
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
                & $r 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1) }

        # ── Privacidade e telemetria ──
        [pscustomobject]@{ Id = 'Telemetria'; Categoria = 'Privacidade e telemetria'; Nivel = 'Recomendado'
            Nome = 'Telemetria no mínimo'
            Descricao = 'Desliga o serviço de coleta (DiagTrack), as tarefas de experiência do usuário e os pedidos de feedback. Windows Update continua normal.'
            Acoes = @(
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
                & $r 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
                @{ T = 'svc'; N = 'DiagTrack'; V = 'Disabled' }
                @{ T = 'svc'; N = 'dmwappushservice'; V = 'Manual' }) + @(
                '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
                '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
                '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
                '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
                '\Microsoft\Windows\Autochk\Proxy',
                '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
                '\Microsoft\Windows\Feedback\Siuf\DmClient',
                '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload' | ForEach-Object { @{ T = 'task'; N = $_ } }) }
        [pscustomobject]@{ Id = 'Atividades'; Categoria = 'Privacidade e telemetria'; Nivel = 'Seguro'
            Nome = 'Sem histórico de atividades'
            Descricao = 'O Windows para de registrar e enviar o que você abre (linha do tempo).'
            Acoes = @(
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0) }
        [pscustomobject]@{ Id = 'EntregaP2P'; Categoria = 'Privacidade e telemetria'; Nivel = 'Seguro'
            Nome = 'Atualizações sem enviar pra outros PCs'
            Descricao = 'O Windows Update baixa direto da Microsoft e não usa sua internet pra mandar atualização pra estranhos.'
            Acoes = @(& $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0) }

        # ── Edge e OneDrive ──
        [pscustomobject]@{ Id = 'EdgeQuieto'; Categoria = 'Edge e OneDrive'; Nivel = 'Recomendado'
            Nome = 'Edge desligado em segundo plano'
            Descricao = 'O Edge para de abrir escondido com o Windows, sem barra lateral, compras, recomendações e pedidos pra ser o navegador padrão. Continua instalado (o Windows precisa dele). No Edge aparece "gerenciado pela organização": é normal.'
            Acoes = @(
                & $r $edge 'StartupBoostEnabled' 0
                & $r $edge 'BackgroundModeEnabled' 0
                & $r $edge 'HubsSidebarEnabled' 0
                & $r $edge 'ShowRecommendationsEnabled' 0
                & $r $edge 'HideFirstRunExperience' 1
                & $r $edge 'EdgeShoppingAssistantEnabled' 0
                & $r $edge 'PersonalizationReportingEnabled' 0
                & $r $edge 'DefaultBrowserSettingEnabled' 0
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0) }
        [pscustomobject]@{ Id = 'RemoverOneDrive'; Categoria = 'Edge e OneDrive'; Nivel = 'Recomendado'
            Nome = 'Remover OneDrive'
            Descricao = 'Desinstala o OneDrive e impede que ele se instale em contas novas. Arquivos já baixados ficam na pasta; os que estavam "só online" deixam de aparecer. Confira antes se o cliente usa.'
            Acoes = @(
                @{ T = 'script'
                   Teste    = '-not (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -and -not (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")'
                   Aplicar  = 'Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force; $s = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1; if ($s) { Start-Process $s "/uninstall" -Wait } elseif (Get-Command winget -ErrorAction SilentlyContinue) { winget uninstall --id Microsoft.OneDrive --silent --accept-source-agreements | Out-Null }'
                   Desfazer = 'if (Get-Command winget -ErrorAction SilentlyContinue) { winget install --id Microsoft.OneDrive --silent --accept-source-agreements --accept-package-agreements | Out-Null } else { Start-Process "https://www.microsoft.com/microsoft-365/onedrive/download" }' }
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup' $null) }

        # ── Apps ──
        [pscustomobject]@{ Id = 'AppsTerceiros'; Categoria = 'Apps pré-instalados'; Nivel = 'Recomendado'
            Nome = 'Apps de propaganda de terceiros'
            Descricao = 'Candy Crush, TikTok, Instagram, Facebook, Disney+, LinkedIn e afins que o Windows instala sozinho.'
            Acoes = @(& $apps 'king.com.*', '*.Disney*', 'BytedancePte.Ltd.TikTok', 'Facebook.Facebook', 'Facebook.Instagram*', '*.Twitter', '7EE7776C.LinkedInforWindows', '*.AmazonAlexa') }
        [pscustomobject]@{ Id = 'AppsMicrosoft'; Categoria = 'Apps pré-instalados'; Nivel = 'Recomendado'
            Nome = 'Apps dispensáveis da Microsoft'
            Descricao = 'Notícias, Clima, Dicas, Obter Ajuda, Hub de Comentários, Mapas, Filmes e TV, To Do, Power Automate, Clipchamp, Office Hub ("Microsoft 365" que só é atalho), Pessoas, Dev Home, Cortana. Fotos, Calculadora, Bloco de Notas, Assistência Rápida e Media Player ficam.'
            Acoes = @(& $apps 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.WindowsFeedbackHub',
                'Microsoft.WindowsMaps', 'Microsoft.ZuneVideo', 'Microsoft.Todos', 'Microsoft.PowerAutomateDesktop', 'Clipchamp.Clipchamp', 'Microsoft.MicrosoftOfficeHub',
                'Microsoft.People', 'Microsoft.Windows.DevHome', 'Microsoft.549981C3F5F10', 'Microsoft.MixedReality.Portal', 'Microsoft.Microsoft3DViewer', 'Microsoft.SkypeApp', 'Microsoft.Wallet') }
        [pscustomobject]@{ Id = 'Paciencia'; Categoria = 'Apps pré-instalados'; Nivel = 'Preferência'
            Nome = 'Remover Paciência (Solitaire)'
            Descricao = 'Tem propaganda, mas tem cliente que joga. Por isso fica fora dos níveis.'
            Acoes = @(& $apps 'Microsoft.MicrosoftSolitaireCollection') }
        [pscustomobject]@{ Id = 'EmailAntigo'; Categoria = 'Apps pré-instalados'; Nivel = 'Recomendado'
            Nome = 'Email e Calendário antigos'
            Descricao = 'A Microsoft encerrou esses apps em 2024 (não sincronizam mais). Só ocupam espaço.'
            Acoes = @(& $apps 'microsoft.windowscommunicationsapps') }
        [pscustomobject]@{ Id = 'OutlookNovo'; Categoria = 'Apps pré-instalados'; Nivel = 'Agressivo'
            Nome = 'Outlook novo'
            Descricao = 'O Outlook (new) que vem no Windows. Não mexe no Outlook do Microsoft 365. Remova se o cliente não usa email no PC.'
            Acoes = @(& $apps 'Microsoft.OutlookForWindows') }
        [pscustomobject]@{ Id = 'VincularCelular'; Categoria = 'Apps pré-instalados'; Nivel = 'Agressivo'
            Nome = 'Vincular ao Celular'
            Descricao = 'Espelha notificações, fotos e SMS do celular. Fica rodando em segundo plano mesmo sem uso.'
            Acoes = @(& $apps 'Microsoft.YourPhone') }
        [pscustomobject]@{ Id = 'Xbox'; Categoria = 'Apps pré-instalados'; Nivel = 'Agressivo'
            Nome = 'Xbox e Game Bar'
            Descricao = 'App Xbox e a Game Bar (Win+G). Quebra o Game Pass, conquistas e a gravação de jogos. Mantém o Xbox Identity (jogos da Store continuam abrindo).'
            Acoes = @(& $apps 'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay') }

        # ── Desempenho ──
        [pscustomobject]@{ Id = 'GameDvr'; Categoria = 'Desempenho'; Nivel = 'Recomendado'
            Nome = 'Sem gravação de jogos em segundo plano'
            Descricao = 'Desliga o Game DVR (gravação automática do Xbox Game Bar), que pesa em jogo e em PC fraco.'
            Acoes = @(
                & $r 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0) }
        [pscustomobject]@{ Id = 'ServicosManual'; Categoria = 'Desempenho'; Nivel = 'Recomendado'
            Nome = 'Serviços dispensáveis em manual'
            Descricao = 'Mapas offline, rastreamento de atalhos em rede, assistente de compatibilidade e modo demonstração de loja. Em manual eles ainda abrem se algum programa pedir.'
            Acoes = @(
                @{ T = 'svc'; N = 'MapsBroker'; V = 'Manual' }
                @{ T = 'svc'; N = 'TrkWks'; V = 'Manual' }
                @{ T = 'svc'; N = 'PcaSvc'; V = 'Manual' }
                @{ T = 'svc'; N = 'RetailDemo'; V = 'Disabled' }) }
        [pscustomobject]@{ Id = 'SemIndexacao'; Categoria = 'Desempenho'; Nivel = 'Agressivo'
            Nome = 'Sem indexação de pesquisa (PC com HD)'
            Descricao = 'Desliga o Windows Search, que mói HD mecânico. A busca de arquivos fica mais lenta e a do Outlook pode parar; apps no Iniciar continuam sendo encontrados. Não vale a pena em SSD.'
            Acoes = @(@{ T = 'svc'; N = 'WSearch'; V = 'Disabled' }) }
        [pscustomobject]@{ Id = 'SensorArmazenamento'; Categoria = 'Desempenho'; Nivel = 'Recomendado'
            Nome = 'Sensor de Armazenamento ligado'
            Descricao = 'O Windows limpa sozinho temporários e a lixeira antiga quando o disco começa a encher.'
            Acoes = @(& $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1) }
        [pscustomobject]@{ Id = 'AppsSegundoPlano'; Categoria = 'Desempenho'; Nivel = 'Agressivo'
            Nome = 'Apps da Store sem segundo plano'
            Descricao = 'Apps da Microsoft Store param de rodar escondidos. Cuidado: WhatsApp, Teams e Vincular ao Celular da Store deixam de notificar quando fechados.'
            Acoes = @(& $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2) }

        # ── Windows Update ──
        [pscustomobject]@{ Id = 'WuSemReinicio'; Categoria = 'Windows Update'; Nivel = 'Recomendado'
            Nome = 'Não reiniciar sozinho com alguém usando'
            Descricao = 'O Windows espera você reiniciar em vez de reiniciar sozinho no meio do trabalho. As atualizações continuam baixando e instalando.'
            Acoes = @(& $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1) }
        [pscustomobject]@{ Id = 'WuSemDrivers'; Categoria = 'Windows Update'; Nivel = 'Agressivo'
            Nome = 'Windows Update sem drivers'
            Descricao = 'O Windows Update para de instalar drivers e os "componentes de software" do fabricante (ex.: os agentes da Acer que voltam depois de formatar). Daí em diante, driver só pelo site do fabricante. Use em PC já com os drivers certos.'
            Acoes = @(
                & $r 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' 1
                & $r 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0) }

        # ── Segurança ──
        [pscustomobject]@{ Id = 'SemPowerShell2'; Categoria = 'Segurança'; Nivel = 'Seguro'
            Nome = 'Desativar PowerShell 2.0'
            Descricao = 'Versão de 2009 sem as proteções atuais, usada por vírus pra escapar do antivírus. Nada moderno depende dela.'
            Acoes = @(@{ T = 'feat'; N = 'MicrosoftWindowsPowerShellV2Root' }) }
        [pscustomobject]@{ Id = 'SemSmb1'; Categoria = 'Segurança'; Nivel = 'Recomendado'
            Nome = 'Desativar SMB 1.0'
            Descricao = 'Protocolo de rede antigo explorado pelo WannaCry. Só desmarque se o PC precisa acessar impressora/HD de rede muito antigo.'
            Acoes = @(@{ T = 'feat'; N = 'SMB1Protocol' }) }
        [pscustomobject]@{ Id = 'SemAutoplay'; Categoria = 'Segurança'; Nivel = 'Recomendado'
            Nome = 'Sem reprodução automática'
            Descricao = 'Pendrive e CD não abrem nada sozinhos ao conectar (vetor comum de vírus). Você abre pelo Explorer.'
            Acoes = @(& $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' 1) }
        [pscustomobject]@{ Id = 'SemAssistenciaRemota'; Categoria = 'Segurança'; Nivel = 'Seguro'
            Nome = 'Sem Assistência Remota antiga'
            Descricao = 'Desliga o convite de Assistência Remota (msra), usado em golpe de "suporte técnico". A Assistência Rápida e o AnyDesk continuam funcionando.'
            Acoes = @(& $r 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0) }

        # ── Preferências pessoais ──
        [pscustomobject]@{ Id = 'VisualLeve'; Categoria = 'Preferências'; Nivel = 'Preferência'; Explorer = $true
            Nome = 'Visual leve (PC fraco)'
            Descricao = 'Sem transparência e sem animações de janela e barra. Deixa PC com pouca memória/vídeo integrado antigo mais ágil; as fontes continuam suavizadas.'
            Acoes = @(
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
                & $r $adv 'TaskbarAnimations' 0
                & $r 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3) }
        [pscustomobject]@{ Id = 'SemRecentes'; Categoria = 'Preferências'; Nivel = 'Preferência'; Explorer = $true
            Nome = 'Explorer sem arquivos recentes'
            Descricao = 'A Página Inicial do Explorer não mostra arquivos e pastas usados recentemente (bom em PC compartilhado da loja).'
            Acoes = @(
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0) }
        [pscustomobject]@{ Id = 'MouseSemAceleracao'; Categoria = 'Preferências'; Nivel = 'Preferência'
            Nome = 'Mouse sem aceleração'
            Descricao = 'Desliga "Aumentar precisão do ponteiro": o cursor anda sempre o mesmo tanto (bom pra jogo e design). Vale no próximo login.'
            Acoes = @(
                & $r 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
                & $r 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
                & $r 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String') }
        [pscustomobject]@{ Id = 'ModoEscuro'; Categoria = 'Preferências'; Nivel = 'Preferência'
            Nome = 'Modo escuro'
            Descricao = 'Windows e apps no tema escuro.'
            Acoes = @(
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0
                & $r 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 0) }
        [pscustomobject]@{ Id = 'SemTeclasAderencia'; Categoria = 'Preferências'; Nivel = 'Preferência'
            Nome = 'Sem aviso de Teclas de Aderência'
            Descricao = 'Apertar Shift 5 vezes (comum em jogo) não abre mais a janela de acessibilidade.'
            Acoes = @(& $r 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String') }
        [pscustomobject]@{ Id = 'NumLock'; Categoria = 'Preferências'; Nivel = 'Preferência'
            Nome = 'Num Lock ligado ao iniciar'
            Descricao = 'O teclado numérico já vem ligado na tela de senha.'
            Acoes = @(
                & $r 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' 'String'
                & $r 'HKCU:\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' 'String') }
    )
}
