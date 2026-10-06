import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Model

enum Mode: String, CaseIterable, Identifiable {
    case timer = "TIMER", pomodoro = "POMODORO", stopwatch = "STOPWATCH"
    var id: String { rawValue }
}

enum RunState { case idle, running, paused }

enum Phase {
    case focus, shortBreak, longBreak
    var label: String {
        switch self {
        case .focus: return "FOCUS"
        case .shortBreak: return "SHORT BREAK"
        case .longBreak: return "LONG BREAK"
        }
    }
}

final class TimerModel: ObservableObject {
    @Published var mode: Mode = .timer { didSet { if oldValue != mode { reset() } } }
    @Published private(set) var state: RunState = .idle
    @Published private(set) var finished = false

    // Countdown length
    @Published var cdH = 0 { didSet { changed() } }
    @Published var cdM = 25 { didSet { changed() } }
    @Published var cdS = 0 { didSet { changed() } }

    // Stopwatch optional stop point (0 = unlimited)
    @Published var swH = 0 { didSet { changed() } }
    @Published var swM = 0 { didSet { changed() } }
    @Published var swS = 0 { didSet { changed() } }

    // Pomodoro
    @Published var focusMin = 25 { didSet { changed() } }
    @Published var shortMin = 5 { didSet { changed() } }
    @Published var longMin = 15 { didSet { changed() } }
    let roundsBeforeLong = 4
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var completedFocus = 0

    var onChange: (() -> Void)?

    private var accumulated: TimeInterval = 0
    private var startedAt: Date?
    private var ticker: Timer?
    private var lastShown = -1

    var elapsed: TimeInterval {
        accumulated + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    var target: TimeInterval? {
        switch mode {
        case .timer:
            return TimeInterval(cdH * 3600 + cdM * 60 + cdS)
        case .stopwatch:
            let t = swH * 3600 + swM * 60 + swS
            return t > 0 ? TimeInterval(t) : nil
        case .pomodoro:
            let m: Int
            switch phase {
            case .focus: m = focusMin
            case .shortBreak: m = shortMin
            case .longBreak: m = longMin
            }
            return TimeInterval(m * 60)
        }
    }

    var displaySeconds: Int {
        let e = elapsed
        if mode == .stopwatch { return Int(e) }
        return Int(ceil(max(0, (target ?? 0) - e)))
    }

    var formatted: String { Self.format(displaySeconds) }

    static func format(_ s: Int) -> String {
        String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: Controls

    func toggle() { state == .running ? pause() : start() }

    func start() {
        if finished { accumulated = 0; finished = false }
        if let t = target, t <= 0 { return }
        startedAt = Date()
        state = .running
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        tick(force: true)
    }

    func pause() {
        accumulated = elapsed
        startedAt = nil
        state = .paused
        ticker?.invalidate(); ticker = nil
        tick(force: true)
    }

    func reset() {
        ticker?.invalidate(); ticker = nil
        accumulated = 0
        startedAt = nil
        state = .idle
        finished = false
        phase = .focus
        completedFocus = 0
        tick(force: true)
    }

    func skipPhase() {
        guard mode == .pomodoro else { return }
        advancePhase()
    }

    // MARK: Internals

    private func changed() {
        if state == .idle { finished = false; tick(force: true) }
    }

    private func tick(force: Bool = false) {
        if state == .running, let t = target, elapsed >= t {
            complete(target: t)
            return
        }
        let shown = displaySeconds
        if force || shown != lastShown {
            lastShown = shown
            objectWillChange.send()
            onChange?()
        }
    }

    private func complete(target t: TimeInterval) {
        NSSound(named: "Glass")?.play()
        if mode == .pomodoro {
            advancePhase()
            return
        }
        ticker?.invalidate(); ticker = nil
        accumulated = t
        startedAt = nil
        state = .idle
        finished = true
        tick(force: true)
    }

    private func advancePhase() {
        if phase == .focus {
            completedFocus += 1
            phase = completedFocus % roundsBeforeLong == 0 ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
        accumulated = 0
        startedAt = state == .running ? Date() : nil
        tick(force: true)
    }
}

// MARK: - Panel

final class TimerPanel: NSPanel {
    var onClose: (() -> Void)?

    init(model: TimerModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 280),
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingController(rootView: ContentView(model: model, close: { [weak self] in self?.onClose?() }))
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
    }

    override var canBecomeKey: Bool { true }

    // Keep the top edge pinned when the content grows or shrinks.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        if isVisible && r.size != frame.size { r.origin.y = frame.maxY - r.height }
        super.setFrame(r, display: flag)
    }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}

/// Lets the user drag the window from any empty area of the SwiftUI view.
struct DragArea: NSViewRepresentable {
    final class V: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Views

struct Palette {
    let digits: Color
    let face: Color
    let accent: Color

    static let red = Palette(
        digits: Color(red: 1.0, green: 0.16, blue: 0.10),
        face: Color(white: 0.02),
        accent: Color(red: 1.0, green: 0.22, blue: 0.16))

    static let black = Palette(
        digits: Color(white: 0.95),
        face: Color(white: 0.02),
        accent: Color(white: 0.95))
}

let chrome = Color(white: 0.085)
let control = Color(white: 0.15)
let dim = Color(white: 0.45)

struct ContentView: View {
    @ObservedObject var model: TimerModel
    var close: () -> Void
    @AppStorage("digitColor") private var digitColor = "red"

    private var p: Palette { digitColor == "red" ? .red : .black }

    var body: some View {
        VStack(spacing: 12) {
            header
            face
            controls
        }
        .padding(14)
        .frame(width: 320)
        .background(DragArea())
        .background(chrome)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))
        .preferredColorScheme(.dark)
    }

    // Close · mode tabs · colour dots
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundColor(dim)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(control))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")

            Spacer(minLength: 0)

            ForEach(Mode.allCases) { m in
                Button { model.mode = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(model.mode == m ? p.accent : dim)
                }
                .buttonStyle(.plain)
                .disabled(model.state != .idle)
                .opacity(model.state != .idle && model.mode != m ? 0.35 : 1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                colorDot("red", Palette.red.digits)
                colorDot("black", Color(white: 0.95))
            }
        }
    }

    private func colorDot(_ name: String, _ c: Color) -> some View {
        Button { digitColor = name } label: {
            Circle().fill(c)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white.opacity(digitColor == name ? 0.8 : 0.2), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(name == "red" ? "Red digits" : "White digits")
    }

    private var face: some View {
        VStack(spacing: 8) {
            SevenSegment(text: model.formatted, height: 44, color: p.digits)
                .modifier(Blink(active: model.state == .paused || model.finished))

            Text(statusLine)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(p.digits.opacity(0.55))
                .frame(height: 12)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.face))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var statusLine: String {
        if model.finished { return "TIME'S UP" }
        switch model.mode {
        case .pomodoro:
            let round = model.completedFocus % model.roundsBeforeLong + (model.phase == .focus ? 1 : 0)
            let r = model.phase == .focus ? " · \(round)/\(model.roundsBeforeLong)" : ""
            return model.state == .paused ? "PAUSED" : model.phase.label + r
        case .timer, .stopwatch:
            switch model.state {
            case .paused: return "PAUSED"
            case .running: return model.mode == .timer ? "COUNTING DOWN" : "COUNTING UP"
            case .idle:
                if model.mode == .stopwatch {
                    return model.target == nil ? "NO LIMIT" : "STOPS AT " + TimerModel.format(Int(model.target!))
                }
                return "READY"
            }
        }
    }

    @ViewBuilder private var fields: some View {
        switch model.mode {
        case .timer:
            NumField(label: "H", value: $model.cdH, max: 99, color: p.digits)
            NumField(label: "M", value: $model.cdM, max: 59, color: p.digits)
            NumField(label: "S", value: $model.cdS, max: 59, color: p.digits)
        case .stopwatch:
            NumField(label: "STOP H", value: $model.swH, max: 99, color: p.digits)
            NumField(label: "M", value: $model.swM, max: 59, color: p.digits)
            NumField(label: "S", value: $model.swS, max: 59, color: p.digits)
        case .pomodoro:
            NumField(label: "FOCUS", value: $model.focusMin, max: 99, color: p.digits)
            NumField(label: "BREAK", value: $model.shortMin, max: 99, color: p.digits)
            NumField(label: "LONG", value: $model.longMin, max: 99, color: p.digits)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            fields
                .disabled(model.state != .idle)
                .opacity(model.state != .idle ? 0.4 : 1)

            Button(action: model.toggle) {
                Image(systemName: model.state == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(Big(accent: p.accent, primary: true))
            .keyboardShortcut(.space, modifiers: [])
            .help(model.state == .running ? "Pause (Space)" : "Start (Space)")

            if model.mode == .pomodoro && model.state != .idle {
                Button(action: model.skipPhase) { Image(systemName: "forward.end.fill") }
                    .buttonStyle(Big(accent: p.accent, primary: false))
                    .help("Skip to next phase")
            }

            Button(action: model.reset) { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(Big(accent: p.accent, primary: true))
                .help("Reset")
        }
    }
}

/// Slow pulse while paused or finished, like an alarm clock waiting to be set.
struct Blink: ViewModifier {
    let active: Bool
    @State private var dimmed = false
    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.3 : 1)
            .onAppear { update() }
            .onChange(of: active) { _ in update() }
    }
    private func update() {
        if active {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dimmed = true }
        } else {
            withAnimation(.default) { dimmed = false }
        }
    }
}

struct NumField: View {
    let label: String
    @Binding var value: Int
    let max: Int
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                TextField("", text: Binding(
                    get: { String(format: "%02d", value) },
                    set: { value = min(max, Int(String($0.filter(\.isNumber).suffix(2))) ?? 0) }))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.clear)
                SevenSegment(text: String(format: "%02d", value), height: 18, color: color)
                    .allowsHitTesting(false)
            }
            .frame(width: 36, height: 22)
            Text(label)
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundColor(dim)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.02)))
        .onScrollWheel { delta in value = Swift.max(0, min(max, value + delta)) }
    }
}

/// Classic seven-segment readout, drawn as shapes so it needs no special font.
struct SevenSegment: View {
    let text: String
    let height: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: height * 0.14) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch == ":" {
                    VStack(spacing: height * 0.28) {
                        Circle().frame(width: height * 0.11, height: height * 0.11)
                        Circle().frame(width: height * 0.11, height: height * 0.11)
                    }
                    .foregroundColor(color)
                } else {
                    SegmentDigit(digit: ch.wholeNumberValue ?? 0)
                        .fill(color)
                        .frame(width: height * 0.52, height: height)
                }
            }
        }
    }
}

struct SegmentDigit: Shape {
    let digit: Int

    // Segments a–g: top, upper-right, lower-right, bottom, lower-left, upper-left, middle.
    private static let lit: [[Bool]] = [
        [true, true, true, true, true, true, false],     // 0
        [false, true, true, false, false, false, false], // 1
        [true, true, false, true, true, false, true],    // 2
        [true, true, true, true, false, false, true],    // 3
        [false, true, true, false, false, true, true],   // 4
        [true, false, true, true, false, true, true],    // 5
        [true, false, true, true, true, true, true],     // 6
        [true, true, true, false, false, false, false],  // 7
        [true, true, true, true, true, true, true],      // 8
        [true, true, true, true, false, true, true],     // 9
    ]

    func path(in r: CGRect) -> Path {
        let t = r.height * 0.13          // segment thickness
        let g = t * 0.18                 // gap between segments
        let l = r.minX + t / 2, rt = r.maxX - t / 2
        let top = r.minY + t / 2, mid = r.midY, bot = r.maxY - t / 2

        func h(_ y: CGFloat) -> Path {
            let x0 = l + g, x1 = rt - g
            return Path { p in
                p.addLines([CGPoint(x: x0, y: y), CGPoint(x: x0 + t / 2, y: y - t / 2),
                            CGPoint(x: x1 - t / 2, y: y - t / 2), CGPoint(x: x1, y: y),
                            CGPoint(x: x1 - t / 2, y: y + t / 2), CGPoint(x: x0 + t / 2, y: y + t / 2)])
                p.closeSubpath()
            }
        }
        func v(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
            let a = y0 + g, b = y1 - g
            return Path { p in
                p.addLines([CGPoint(x: x, y: a), CGPoint(x: x + t / 2, y: a + t / 2),
                            CGPoint(x: x + t / 2, y: b - t / 2), CGPoint(x: x, y: b),
                            CGPoint(x: x - t / 2, y: b - t / 2), CGPoint(x: x - t / 2, y: a + t / 2)])
                p.closeSubpath()
            }
        }

        let segments = [h(top), v(rt, top, mid), v(rt, mid, bot), h(bot), v(l, mid, bot), v(l, top, mid), h(mid)]
        var path = Path()
        for (on, seg) in zip(Self.lit[min(max(digit, 0), 9)], segments) where on { path.addPath(seg) }
        return path
    }
}

extension View {
    /// Scroll over a number field to nudge it up or down.
    func onScrollWheel(_ action: @escaping (Int) -> Void) -> some View {
        overlay(ScrollCatcher(action: action).allowsHitTesting(false))
    }
}

struct ScrollCatcher: NSViewRepresentable {
    let action: (Int) -> Void
    final class V: NSView {
        var action: ((Int) -> Void)?
        var monitor: Any?
        override func viewDidMoveToWindow() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let w = self.window, e.window == w,
                      self.bounds.contains(self.convert(e.locationInWindow, from: nil)),
                      abs(e.scrollingDeltaY) > 0.5 else { return e }
                self.action?(e.scrollingDeltaY > 0 ? 1 : -1)
                return nil
            }
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.action = action; return v }
    func updateNSView(_ v: V, context: Context) { v.action = action }
}

struct Big: ButtonStyle {
    let accent: Color
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(primary ? accent : Color(white: 0.75))
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(control))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? accent.opacity(0.35) : .clear))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - App

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = TimerModel()
    var statusItem: NSStatusItem!
    var panel: TimerPanel!
    var positioned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "clock", accessibilityDescription: "Study Timer")
            img?.isTemplate = true
            button.image = img
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        panel = TimerPanel(model: model)
        panel.onClose = { [weak self] in self?.hidePanel() }
        model.onChange = { [weak self] in self?.updateStatus() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatus() }
        }
        updateStatus()
    }

    func updateStatus() {
        guard let button = statusItem?.button else { return }
        let title: String
        if model.state != .idle {
            title = model.formatted
        } else if panel?.isVisible == true {
            title = "00:00:00"
        } else {
            title = ""
        }
        button.title = ""
        button.imagePosition = .imageOnly
        let img = statusImage(title)
        button.image = img
        // Size the item to the rendered image so the seconds never get clipped.
        statusItem.length = (img?.size.width ?? 18) + 12
    }

    /// Clock icon plus seven-segment time, in the app's digit colour. White mode renders
    /// as a template so it stays readable on both light and dark menu bars.
    func statusImage(_ time: String) -> NSImage? {
        let red = UserDefaults.standard.string(forKey: "digitColor") ?? "red" == "red"
        let color: Color = red ? Palette.red.digits : .black
        let view = HStack(spacing: 5) {
            Image(systemName: "clock").font(.system(size: 13, weight: .medium))
            if !time.isEmpty { SevenSegment(text: time, height: 12, color: color) }
        }
        .foregroundColor(color)
        .frame(height: 18)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = renderer.nsImage
        img?.isTemplate = !red
        return img
    }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: panel.isVisible ? "Hide Timer" : "Show Timer", action: #selector(togglePanel), keyEquivalent: "").target = self
            let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Study Timer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        if !positioned, let screen = NSScreen.main {
            panel.layoutIfNeeded()
            let size = panel.frame.size
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 12, y: vf.maxY - size.height - 12))
            positioned = true
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        updateStatus()
    }

    func hidePanel() {
        panel.orderOut(nil)
        updateStatus()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
