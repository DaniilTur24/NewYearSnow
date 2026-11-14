// Приветственное окно: показывается при первом запуске и по пункту меню «Как настроить…».
// Помогает выдать «Универсальный доступ» и включить автозапуск без поиска по настройкам.

import SwiftUI
import ServiceManagement

final class WelcomeModel: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var login = SMAppService.mainApp.status
    @Published var loginError = false
    /// Программа лежит в «Программах» (иначе автозапуск ненадёжен, а macOS может запускать её из временной папки).
    let inApplications = Bundle.main.bundlePath.hasPrefix("/Applications/")
        || Bundle.main.bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/")
    var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        let t = AXIsProcessTrusted()
        if t != trusted { trusted = t }
        let l = SMAppService.mainApp.status
        if l != login { login = l }
    }

    func openAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func toggleLogin() {
        loginError = false
        do {
            if login == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            loginError = true
        }
        refresh()
        if login == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Снег уже идёт! ❄️").font(.title2).bold()
                    Text("Всё управление — в меню ❄️ в строке меню, вверху справа. Два необязательных шага сделают оформление полным.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.inApplications {
                Label("Программа запущена не из папки «Программы». Перетащите NewYearSnow в «Программы» и откройте оттуда — так будет работать автозапуск.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            step(number: 1, title: "Снег на Доке и вкладках",
                 text: model.trusted
                    ? "Программа знает, где находится Док, и подстраивается под него."
                    : "Нажмите кнопку и включите переключатель у NewYearSnow. Если он уже включён, а снега на Доке нет: выделите программу в списке, нажмите «−» и включите её заново.") {
                if model.trusted {
                    done("Разрешено")
                } else {
                    Button("Открыть настройки") { model.openAccessibility() }
                        .buttonStyle(.borderedProminent)
                }
            }

            step(number: 2, title: "Запуск вместе с Mac",
                 text: model.login == .requiresApproval
                    ? "Почти готово: в открывшихся настройках включите NewYearSnow в «Объектах входа»."
                    : "Снег будет включаться сам, когда вы включаете Mac.") {
                switch model.login {
                case .enabled:
                    VStack(alignment: .trailing, spacing: 2) {
                        done("Включено")
                        Button("Выключить") { model.toggleLogin() }.buttonStyle(.link).font(.caption)
                    }
                case .requiresApproval:
                    Button("Открыть настройки") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.borderedProminent)
                default:
                    Button("Включить") { model.toggleLogin() }
                        .buttonStyle(.borderedProminent)
                }
            }
            if model.loginError {
                Text("Не получилось включить автоматически. Добавьте NewYearSnow вручную: Системные настройки → Основные → Объекты входа → «+».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Попробуйте").font(.headline)
                Text("• Проведите курсором по сугробу на окне — снег слетит.")
                Text("• Дважды щёлкните по пустому рабочему столу — будет салют.")
                Text("• Меню ❄️ → «Максимальный» — настоящая метель, «Музыка 🎵» — рождественские мелодии.")
                Text("• Это окно можно открыть снова: меню ❄️ → «Как настроить…».")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Готово") { close() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    func done(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green).bold()
    }

    func step<Trailing: View>(number: Int, title: String, text: String,
                              @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

final class WelcomeWindow: NSObject, NSWindowDelegate {
    let model = WelcomeModel()
    var window: NSWindow?

    var frame: CGRect? { window?.isVisible == true ? window?.frame : nil }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Новогодний снег"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: WelcomeView(model: model) { [weak self] in self?.window?.close() })
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            window = w
        }
        model.start()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model.stop() }
}
