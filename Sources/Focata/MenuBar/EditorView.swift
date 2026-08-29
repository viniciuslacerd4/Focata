import AppKit
import SwiftUI

/// O campo de texto da caixa da tarefa. Um campo, e só.
///
/// Não há janela principal no Focata: toda a edição acontece no `TaskPanelView`,
/// que é este campo com uma barra de título por cima.
struct EditorView: View {
    @Bindable var task: TaskStore
    /// Chamado por `return` ou `esc` — os dois fecham o editor (§2 da spec).
    var onDismiss: () -> Void
    /// Muda a cada vez que a caixa reaparece. A janela não é recriada ao
    /// minimizar, então focar só na criação devolveria o cursor ao campo apenas
    /// na primeira abertura.
    var focusToken: Int = 0
    /// A saída de cena da tarefa concluída, quando concluir limpa a barra.
    var completion: TaskCompletionAnimation

    var body: some View {
        ZStack(alignment: .topLeading) {
            TaskTextEditor(text: $task.text, focusToken: focusToken, onDismiss: onDismiss)
                // Enquanto a tarefa sai de cena quem aparece é o retrato dela; o
                // campo, já vazio, ficaria com o cursor piscando por cima do
                // texto que está sendo riscado.
                .opacity(completion.isSayingFarewell ? 0 : 1)

            if task.text.isEmpty, !completion.isSayingFarewell {
                placeholder
            }

            if let farewell = completion.text, completion.isSayingFarewell {
                FarewellText(text: farewell, onFinish: completion.farewellDidEnd)
                    .allowsHitTesting(false)
            }
        }
        .padding(12)
        // Digitar corta a despedida e devolve o campo na hora — vale também para
        // um texto vindo de fora. O vazio da própria conclusão não conta.
        .onChange(of: task.text) { _, novo in
            if !novo.isEmpty { completion.cancel() }
        }
    }

    /// O marcador d'água.
    ///
    /// É desenhado aqui, e não pelo `NSTextView`, porque é ele mesmo que sobe de
    /// baixo quando a tarefa anterior sai de cena: dois desenhos diferentes se
    /// entregariam no pulo da troca.
    private var placeholder: some View {
        line(TaskTextEditor.placeholder)
            .foregroundStyle(Color(nsColor: .placeholderTextColor))
            .offset(y: completion.greetingOffset)
            .opacity(completion.greetingOpacity)
            .allowsHitTesting(false)
    }

    /// O convite, com a fonte e a largura do campo.
    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TaskTextLayout.fontSize))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Campo de várias linhas que cresce com o texto até cinco linhas e, daí em
/// diante, rola por dentro.
///
/// É `NSTextView` e não `TextField(axis: .vertical)` porque o campo da SwiftUI
/// só sabe crescer: chegando ao `lineLimit` ele para de mostrar o resto, e a
/// linha que está sendo digitada pode acabar fora da caixa. Aqui a altura é
/// medida a cada mudança de texto e limitada; o que passar disso vira rolagem,
/// com o cursor sempre à vista.
private struct TaskTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var onDismiss: () -> Void

    static let placeholder = "No que você vai focar?"

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 de propósito: é a mesma máquina de layout que a `Coordinator`
        // usa para medir a altura, e duas quebras de linha diferentes dariam uma
        // caixa de tamanho diferente do texto que ela mostra.
        let textView = TaskTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.font = TaskTextLayout.font
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        // Texto cru: a tarefa vira Markdown na barra, e colar de um navegador
        // não pode trazer fonte e cor da página junto.
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        // O respiro em volta é o `padding` da `EditorView`; aqui, nenhum — senão
        // a medida da altura e o desenho do texto discordariam.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        // A altura quem manda é a SwiftUI; a largura acompanha a caixa.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // Barra sobreposta e sem elástico: num campo de cinco linhas, uma calha
        // de rolagem ao lado roubaria largura do texto, e o repique do elástico
        // pareceria defeito.
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? TaskTextView else { return }

        context.coordinator.text = $text
        textView.onDismiss = onDismiss

        // Texto vindo de fora (automação, Serviços, "limpar" pelo menu): a
        // comparação evita reescrever o campo a cada tecla, o que levaria o
        // cursor para o fim e apagaria o desfazer.
        if textView.string != text {
            textView.string = text
        }

        guard context.coordinator.focusToken != focusToken else { return }
        context.coordinator.focusToken = focusToken
        // Depois desta passada de layout: durante `updateNSView` a view ainda
        // pode não estar na janela, e o primeiro respondedor iria para o vazio.
        DispatchQueue.main.async {
            guard textView.window?.makeFirstResponder(textView) == true else { return }
            // Tudo selecionado ao abrir, como num campo de texto do sistema: a
            // caixa se abre para a próxima tarefa, e digitar já troca a atual.
            textView.selectAll(nil)
            textView.scroll(.zero)
        }
    }

    /// A altura da caixa é a do texto, entre uma linha e `maxLines`.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        var width = proposal.width ?? TaskPanelView.width
        if !width.isFinite || width <= 0 { width = TaskPanelView.width }
        return CGSize(width: width, height: context.coordinator.height(of: text, width: width))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// Começa fora de qualquer valor real para que a primeira atualização já
        /// leve o cursor ao campo.
        var focusToken = Int.min

        /// Uma máquina de layout só para medir: perguntar a altura ao próprio
        /// campo exigiria redimensioná-lo antes de saber de que tamanho ele é.
        /// É a mesma que o risco usa para achar as linhas — a caixa e o traço
        /// têm que enxergar as mesmas quebras.
        private let layout = TaskTextLayout()

        init(text: Binding<String>) {
            self.text = text
            super.init()
        }

        func height(of string: String, width: CGFloat) -> CGFloat {
            layout.update(text: string, width: width)
            return layout.height()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            // Passadas as cinco linhas a caixa para de crescer, e é a rolagem
            // que mantém à vista a linha que está sendo escrita.
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }
}

/// O campo em si.
///
/// `return` e `esc` não editam nada aqui: os dois fecham a caixa, como manda a
/// spec.
private final class TaskTextView: NSTextView {
    var onDismiss: () -> Void = {}

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.cancelOperation(_:)),
             // Dentro de um `NSTextView` o `esc` chega como "completar palavra",
             // e não como cancelar.
             #selector(NSStandardKeyBindingResponding.complete(_:)):
            onDismiss()
        default:
            super.doCommand(by: selector)
        }
    }
}
