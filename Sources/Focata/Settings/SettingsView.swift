import KeyboardShortcuts
import Observation
import SwiftUI

/// As abas das Configurações.
///
/// A ordem aqui é a ordem na barra de ferramentas, e cada aba diz de quanta
/// altura precisa: a janela se ajusta a ela em vez de todas herdarem a altura da
/// maior — quatro interruptores não pedem meia tela vazia.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, pomodoro, shortcuts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "Geral"
        case .appearance: "Aparência"
        case .pomodoro: "Pomodoro"
        case .shortcuts: "Atalhos"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .pomodoro: "circle.dashed"
        case .shortcuts: "command"
        }
    }

    var height: CGFloat {
        switch self {
        case .general: 430
        case .appearance: 560
        case .pomodoro: 700
        case .shortcuts: 300
        }
    }

    static let width: CGFloat = 470
}

extension Color {
    /// O destaque dos controles — branco puxado para o cinza claro.
    ///
    /// Branco puro pintaria o trilho aceso do interruptor da mesma cor da
    /// bolinha, e ela sumiria dentro dele: o interruptor ligado ficava um
    /// comprimido branco liso, sem nada para dizer de que lado está.
    static let focataControl = Color(white: 0.68)
}

/// Interruptor em preto e branco.
///
/// A SwiftUI pinta trilho **e** bolinha com o `tint`, então tingir de branco (ou
/// de qualquer cor) faz a bolinha sumir dentro do trilho aceso: o interruptor
/// ligado vira um comprimido liso, sem dizer de que lado está. Daí o estilo
/// próprio — trilho claro quando ligado, escuro quando desligado, e a bolinha
/// sempre branca.
struct FocataSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Switch(configuration: configuration)
    }

    private struct Switch: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ToggleStyleConfiguration

        var body: some View {
            HStack {
                configuration.label
                Spacer(minLength: 12)

                Button {
                    withAnimation(.snappy(duration: 0.18)) { configuration.isOn.toggle() }
                } label: {
                    Capsule()
                        .fill(configuration.isOn ? Color.focataControl : Color.white.opacity(0.12))
                        .frame(width: 38, height: 22)
                        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                            Circle()
                                .fill(.white)
                                .frame(width: 18, height: 18)
                                .padding(2)
                                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// Qual aba está aberta, observável pelos botões da barra de ferramentas.
@MainActor
@Observable
final class SettingsSelection {
    var tab: SettingsTab = .general
}

/// Um botão da barra de ferramentas: ícone em cima, rótulo embaixo.
///
/// Desenhado à mão porque a seleção nativa do `NSToolbar` pinta ícone e rótulo
/// com a cor de destaque do sistema — azul, na maioria dos Macs. O Focata é
/// preto e branco, e o realce aqui é o mesmo branco do anel de foco.
struct SettingsTabButton: View {
    let tab: SettingsTab
    let selection: SettingsSelection
    var onSelect: (SettingsTab) -> Void

    private var isSelected: Bool { selection.tab == tab }

    var body: some View {
        Button { onSelect(tab) } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .frame(height: 18)
                Text(tab.label)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? .white : Color.secondary)
            .frame(width: 78, height: 46)
            // O realce é a fatia da cápsula da barra de ferramentas que cabe a
            // esta aba, e não uma pílula solta por dentro dela: arredondado só
            // na ponta de fora, onde encosta na curva da cápsula, e reto onde
            // encosta na aba vizinha.
            //
            // A cápsula tem 44pt contra os 46 do item, e nasce meio ponto à
            // direita e um ponto abaixo dele — daí o recuo de meio ponto e o
            // `offset`, que são o que faz o realce cobrir a fatia exata sem
            // sobrar borda de um lado nem vazar do outro.
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: leadingRadius,
                    bottomLeadingRadius: leadingRadius,
                    bottomTrailingRadius: trailingRadius,
                    topTrailingRadius: trailingRadius,
                    style: .circular
                )
                .fill(.white.opacity(isSelected ? 0.16 : 0))
                .padding(.vertical, 0.5)
                .offset(x: 0.5, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.label)
    }

    /// Metade da altura da cápsula da barra: é o que faz a ponta de fora ser a
    /// mesma meia-lua dela, e não um canto arredondado qualquer por dentro.
    private static let endRadius: CGFloat = 22

    private var leadingRadius: CGFloat {
        SettingsTab.allCases.first == tab ? Self.endRadius : 0
    }

    private var trailingRadius: CGFloat {
        SettingsTab.allCases.last == tab ? Self.endRadius : 0
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralTab(settings: settings)
            case .appearance: AppearanceTab(settings: settings)
            case .pomodoro: PomodoroTab(settings: settings)
            case .shortcuts: ShortcutsTab()
            }
        }
        // Dimensão explícita: um `Form` agrupado é uma área de rolagem, e não
        // propaga altura intrínseca para o `NSHostingController` — a janela
        // nasceria com a altura de nada.
        .frame(width: SettingsTab.width, height: tab.height)
        // Sem azul: os controles seguem o branco do resto do app.
        .tint(.focataControl)
        .toggleStyle(FocataSwitchStyle())
        // `ignoresSafeArea` para o material subir até a borda de cima: o
        // conteúdo fica abaixo da barra de ferramentas, mas o fundo passa por
        // trás dela e a janela inteira é a mesma translucidez.
        .background(VisualEffectBackground().ignoresSafeArea())
    }
}

private struct GeneralTab: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Abrir junto com o Mac", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.isEnabled = newValue
                        // O sistema pode recusar (ex.: item desativado nos Ajustes),
                        // então refletimos o estado real, não o pretendido.
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }

                Toggle("Guardar histórico", isOn: $settings.trackHistory)
                    .disabled(!settings.clearsBarOnCompletion)
            } footer: {
                if !settings.clearsBarOnCompletion {
                    Text("O histórico pede “Limpar a barra”, na aba Pomodoro: com o texto riscado a conclusão pode ser desfeita no check da caixa, e o registro iria junto.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Esconder o editor ao clicar fora", isOn: $settings.hideEditorWhenDeactivated)
                Toggle("Esconder o item da barra quando vazio", isOn: $settings.hideMenuBarItemWhenEmpty)
            }

            Section {
                Toggle("Verificar atualizações automaticamente", isOn: $settings.automaticUpdateChecks)
                UpdateRow()
            } footer: {
                Text("A verificação pergunta ao GitHub qual é o último release publicado, uma vez por dia. É uma pergunta anônima: nada do que você escreve sai do Mac, e nada é baixado nem instalado sem o seu clique.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// A linha da versão: o que você tem, o que a última verificação encontrou e o
/// botão para perguntar de novo.
private struct UpdateRow: View {
    private var updates: UpdateController { .shared }
    private var checker: UpdateChecker { updates.checker }

    var body: some View {
        LabeledContent("Versão") {
            HStack(spacing: 10) {
                Text(status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if case .available(let release) = checker.state {
                    Button("Baixar") { updates.download(release) }
                } else {
                    Button("Verificar agora") { updates.checkNow() }
                        .disabled(checker.state == .checking)
                }
            }
        }
    }

    /// A verificação já responde por alerta quando você pede pelo menu; aqui a
    /// resposta cabe na própria linha, sem alerta nenhum por cima da janela.
    private var status: String {
        switch checker.state {
        case .idle:
            "\(checker.currentVersion)"
        case .checking:
            "Verificando…"
        case .upToDate:
            "\(checker.currentVersion) · a mais recente"
        case .available(let release):
            "\(release.version) disponível"
        case .failed(let message):
            message
        }
    }
}

private struct AppearanceTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextField("Prefixo", text: $settings.prefixText)
                TextField("Sufixo", text: $settings.suffixText)
            } footer: {
                Text("Texto fixo antes e depois do que você digita. Espaços aqui dão respiro nas laterais.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Largura máxima") {
                    HStack {
                        Slider(value: $settings.maximumWidth, in: 80...800)
                        Text("\(Int(settings.maximumWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                LabeledContent("Tamanho do texto") {
                    HStack {
                        Slider(value: $settings.textSize, in: 10...22, step: 1)
                        Text("\(Int(settings.textSize)) pt")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                LabeledContent("Largura da fonte") {
                    HStack {
                        Slider(value: $settings.textWidth, in: -1...1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("Estreita").font(.caption)
                        } maximumValueLabel: {
                            Text("Larga").font(.caption)
                        }
                    }
                }

                Toggle("Negrito", isOn: $settings.textIsBold)

                Picker("Cor", selection: $settings.textColor) {
                    ForEach(MenuBarTextColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
            } footer: {
                Text("Só cores do sistema, que se adaptam para continuar legíveis em barra clara ou escura.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct PomodoroTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Ativar Pomodoro", isOn: $settings.pomodoroEnabled)
            } footer: {
                Text("Desligado, o anel some da barra e só o texto da tarefa fica.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Durações") {
                minutesRow("Foco", value: $settings.focusMinutes, range: 1...120)
                minutesRow("Livre curto", value: $settings.freeShortMinutes, range: 1...60)
                minutesRow("Livre longo", value: $settings.freeLongMinutes, range: 1...90)

                Stepper(value: $settings.cyclesBeforeLongFree, in: 1...12) {
                    LabeledContent("Ciclos até o livre longo", value: "\(settings.cyclesBeforeLongFree)")
                }

                LabeledContent("Presets") {
                    HStack {
                        ForEach(PomodoroPreset.allCases) { preset in
                            Button(preset.label) { settings.apply(preset) }
                        }
                    }
                }
            }

            Section("Notificações de transição") {
                Toggle("Avisar ao trocar de modo", isOn: $settings.transitionNotifications)
                Toggle("Com som", isOn: $settings.transitionSound)
                    .disabled(!settings.transitionNotifications)
            }

            Section {
                Picker("Ao concluir a última tarefa", selection: $settings.onLastTaskCompleted) {
                    ForEach(OnLastTaskCompleted.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section {
                Toggle("Registrar no histórico", isOn: $settings.logToHistory)
                    .disabled(!settings.recordsHistoryIsPossible)
                Toggle("Iniciar sessões em modo privado", isOn: $settings.defaultToPrivate)
            } footer: {
                Text(historyFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// O rodapé explica por que o histórico pode estar parado — e onde mexer.
    private var historyFooter: String {
        if !settings.clearsBarOnCompletion {
            return "Com “Manter o texto riscado” o histórico fica desligado: a conclusão pode ser desfeita no check da caixa, e o registro iria junto."
        }
        if !settings.trackHistory {
            return "“Guardar histórico” está desligado na aba Geral, então nada é registrado."
        }
        return "Sessões privadas nunca entram no histórico, nem como concluídas, nem como abandonadas."
    }

    private func minutesRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 1)
                Text("\(Int(value.wrappedValue)) min")
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }
}

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Abrir o editor", name: .toggleEditor)
                KeyboardShortcuts.Recorder("Iniciar / pausar", name: .toggleTimer)
                KeyboardShortcuts.Recorder("Pular ciclo", name: .skipPhase)
                KeyboardShortcuts.Recorder("Concluir tarefa", name: .completeTask)
                KeyboardShortcuts.Recorder("Alternar modo privado", name: .togglePrivate)
            } footer: {
                Text("Atalhos globais: funcionam de qualquer app. Nenhum vem definido de fábrica para não roubar teclas que você já usa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
