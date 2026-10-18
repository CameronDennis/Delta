//
//  SteamTouchscreen.swift
//
//  Trackpad-as-touchscreen extras for the Steam Controller:
//    - user settings (4:3 mapping, press-to-touch threshold, cursor look and fade)
//    - an on-screen cursor drawn over the DS bottom screen
//    - the SwiftUI settings sections shown in Delta's controls editor
//

import UIKit
import SwiftUI
import CoreImage
import DeltaCore

// MARK: - Settings

enum SteamTouchSettings
{
    static func registerDefaults()
    {
        UserDefaults.standard.register(defaults: [
            "steam.touch.aspect43": false,
            "steam.touch.requirePress": false,
            "steam.touch.pressThreshold": 0.15,
            "steam.cursor.enabled": true,
            "steam.cursor.fade": 1.0,
            "steam.cursor.size": 26.0,
            "steam.cursor.outlineWidth": 2.0,
            "steam.cursor.fill.r": 1.0, "steam.cursor.fill.g": 1.0, "steam.cursor.fill.b": 1.0, "steam.cursor.fill.a": 0.5,
            "steam.cursor.outline.r": 0.0, "steam.cursor.outline.g": 0.0, "steam.cursor.outline.b": 0.0, "steam.cursor.outline.a": 0.8,
            "steam.cursor.pressedFill.r": 1.0, "steam.cursor.pressedFill.g": 0.2, "steam.cursor.pressedFill.b": 0.2, "steam.cursor.pressedFill.a": 0.7,
            "steam.cursor.pressedOutline.r": 0.5, "steam.cursor.pressedOutline.g": 0.0, "steam.cursor.pressedOutline.b": 0.0, "steam.cursor.pressedOutline.a": 0.9
        ])
    }

    static var aspect43: Bool { UserDefaults.standard.bool(forKey: "steam.touch.aspect43") }
    static var requirePress: Bool { UserDefaults.standard.bool(forKey: "steam.touch.requirePress") }
    static var pressThreshold: Double { UserDefaults.standard.double(forKey: "steam.touch.pressThreshold") }
    static var cursorEnabled: Bool { UserDefaults.standard.bool(forKey: "steam.cursor.enabled") }
    static var fade: Double { UserDefaults.standard.double(forKey: "steam.cursor.fade") }
    static var size: Double { UserDefaults.standard.double(forKey: "steam.cursor.size") }
    static var outlineWidth: Double { UserDefaults.standard.double(forKey: "steam.cursor.outlineWidth") }

    /// Puts every cursor look/timing setting (everything except showing the cursor) back to its default.
    static func resetCursor()
    {
        var keys = ["steam.cursor.fade", "steam.cursor.size", "steam.cursor.outlineWidth"]
        for prefix in ["steam.cursor.fill", "steam.cursor.outline", "steam.cursor.pressedFill", "steam.cursor.pressedOutline"]
        {
            keys += ["r", "g", "b", "a"].map { prefix + "." + $0 }
        }

        for key in keys
        {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Flips "Require Firm Press to Touch" (bound to a game action so it can be toggled mid-game).
    static func toggleRequirePress()
    {
        UserDefaults.standard.set(!requirePress, forKey: "steam.touch.requirePress")
    }

    static func color(_ prefix: String) -> UIColor
    {
        let d = UserDefaults.standard
        return UIColor(red: d.double(forKey: prefix + ".r"),
                       green: d.double(forKey: prefix + ".g"),
                       blue: d.double(forKey: prefix + ".b"),
                       alpha: d.double(forKey: prefix + ".a"))
    }
}

// MARK: - Cursor

private final class CursorWindow: UIWindow
{
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        return nil
    }
}

final class SteamCursor
{
    static let shared = SteamCursor()

    private var window: CursorWindow?
    private let cursorView = UIView()
    private var source: Int?
    private var isVisible = false

    /// Shows (or moves) the cursor to a normalized (0...1) position on the DS bottom screen.
    /// When pressed is true the touch is being sent to the game, so the "pressed" colors are used.
    func show(x: Double, y: Double, source: Int, pressed: Bool)
    {
        guard SteamTouchSettings.cursorEnabled else
        {
            hideNow()
            return
        }

        // Only draw the cursor while the game is actually running in the foreground.
        guard let (overlay, rect) = locateBottomScreen() else
        {
            hideNow()
            return
        }

        self.source = source
        cursorView.layer.removeAllAnimations()

        let size = CGFloat(max(2.0, SteamTouchSettings.size))
        cursorView.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        cursorView.layer.cornerRadius = size / 2
        cursorView.backgroundColor = SteamTouchSettings.color(pressed ? "steam.cursor.pressedFill" : "steam.cursor.fill")
        cursorView.layer.borderColor = SteamTouchSettings.color(pressed ? "steam.cursor.pressedOutline" : "steam.cursor.outline").cgColor
        cursorView.layer.borderWidth = CGFloat(max(0.0, SteamTouchSettings.outlineWidth))
        cursorView.center = CGPoint(x: rect.minX + CGFloat(x) * rect.width, y: rect.minY + CGFloat(y) * rect.height)

        if !isVisible
        {
            isVisible = true
            cursorView.alpha = 0
            overlay.isHidden = false
            UIView.animate(withDuration: 0.08) { self.cursorView.alpha = 1 }
        }
        else
        {
            cursorView.alpha = 1
        }
    }

    /// Starts fading the cursor out. Ignored if another pad has taken over the cursor.
    func release(source: Int)
    {
        guard self.source == source else { return }
        self.source = nil

        let fade = SteamTouchSettings.fade
        if fade <= 0.001
        {
            hideNow()
            return
        }

        UIView.animate(withDuration: fade, delay: 0, options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction], animations: {
            self.cursorView.alpha = 0
        }, completion: { finished in
            if finished { self.hideNow() }
        })
    }

    private func hideNow()
    {
        cursorView.layer.removeAllAnimations()
        cursorView.alpha = 0
        window?.isHidden = true
        isVisible = false
        source = nil
    }

    private func makeWindowIfNeeded() -> CursorWindow?
    {
        if let window = window { return window }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }

        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.addSubview(cursorView)
        cursorView.isUserInteractionEnabled = false
        cursorView.alpha = 0

        let window = CursorWindow(windowScene: scene)
        window.windowLevel = .alert + 2
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.rootViewController = controller
        window.isHidden = true
        self.window = window
        return window
    }

    private func collectGameViews(in view: UIView, into result: inout [GameView])
    {
        if let gameView = view as? GameView, !gameView.isHidden, gameView.alpha > 0
        {
            result.append(gameView)
        }

        for subview in view.subviews
        {
            collectGameViews(in: subview, into: &result)
        }
    }

    /// True when the emulator behind this game view is running (not paused by the pause menu, a sheet, etc.).
    private func isReceivingInput(_ gameView: GameView) -> Bool
    {
        var responder: UIResponder? = gameView
        while let current = responder
        {
            if let viewController = current as? DeltaCore.GameViewController
            {
                return viewController.emulatorCore?.state == .running
            }

            responder = current.next
        }

        return true
    }

    /// The crop rectangle (in the DS frame, top-left origin) that a game view applies, if any.
    private func cropRect(of gameView: GameView) -> CGRect?
    {
        var filters = [CIFilter]()

        if let chain = gameView.filter as? FilterChain
        {
            filters = chain.inputFilters
        }
        else if let filter = gameView.filter
        {
            filters = [filter]
        }

        for filter in filters where filter.name == "CICrop"
        {
            if let vector = filter.value(forKey: "inputRectangle") as? CIVector
            {
                return vector.cgRectValue
            }
        }

        return nil
    }

    /// Finds the DS bottom screen on screen, in the cursor window's coordinates.
    ///
    /// The screen is identified by what it displays rather than where it sits, so any layout works
    /// (stacked, side by side, or swapped). Each screen's game view crops the combined DS frame, and
    /// the bottom screen's crop is the lower region.
    private func locateBottomScreen() -> (CursorWindow, CGRect)?
    {
        guard let overlay = makeWindowIfNeeded(), let scene = overlay.windowScene else { return nil }
        guard UIApplication.shared.applicationState == .active, scene.activationState == .foregroundActive else { return nil }

        var gameViews = [GameView]()
        for window in scene.windows where window !== overlay
        {
            collectGameViews(in: window, into: &gameViews)
        }

        var entries = [(frame: CGRect, crop: CGRect?)]()
        for gameView in gameViews
        {
            guard let window = gameView.window, gameView.bounds.width > 10, gameView.bounds.height > 10 else { continue }
            guard isReceivingInput(gameView) else { continue }
            let windowRect = window.convert(gameView.bounds, from: gameView)
            entries.append((frame: overlay.convert(windowRect, from: window), crop: cropRect(of: gameView)))
        }

        // Normal case: each screen is cropped from the DS frame. The one cropped lowest is the bottom screen.
        let cropped = entries.filter { $0.crop != nil }
        if let bottom = cropped.max(by: { ($0.crop?.minY ?? 0) < ($1.crop?.minY ?? 0) }),
           let crop = bottom.crop, cropped.count >= 2 || crop.minY > 100
        {
            return (overlay, bottom.frame)
        }

        // One uncropped view showing both screens stacked (aspect 2:3): use its lower half.
        if let full = entries.first(where: { $0.crop == nil && abs($0.frame.width / $0.frame.height - 2.0 / 3.0) < 0.08 })
        {
            return (overlay, CGRect(x: full.frame.minX, y: full.frame.midY, width: full.frame.width, height: full.frame.height / 2))
        }

        // Last resort: the lowest 4:3 view.
        let screens = entries.map { $0.frame }.filter { abs($0.width / $0.height - 4.0 / 3.0) < 0.12 }
        if let bottom = screens.max(by: { $0.midY < $1.midY })
        {
            return (overlay, bottom)
        }

        return nil
    }
}

// MARK: - Settings UI

struct SteamTouchscreenOptions: View
{
    @AppStorage("steam.touch.aspect43") private var aspect43 = false
    @AppStorage("steam.touch.requirePress") private var requirePress = false
    @AppStorage("steam.touch.pressThreshold") private var threshold = 0.15
    @AppStorage("steam.cursor.enabled") private var cursorEnabled = true
    @AppStorage("steam.cursor.advanced") private var showsAdvancedCursor = false
    @AppStorage("steam.cursor.fade") private var fade = 1.0
    @AppStorage("steam.cursor.size") private var size = 26.0
    @AppStorage("steam.cursor.outlineWidth") private var outlineWidth = 2.0

    var body: some View {
        Section {
            Toggle("Match DS Aspect Ratio (4:3)", isOn: $aspect43)

            Toggle("Require Firm Press to Touch", isOn: $requirePress)

            if requirePress
            {
                SteamSliderField(title: String(localized: "Press Strength"), value: $threshold, sliderRange: 0...1, typedRange: 0...1, step: 0.01, scale: 100, unit: "%", decimals: 0)
            }
        } header: {
            Text("Trackpad Touch")
        } footer: {
            Text("4:3 uses a DS-shaped area of the pad so the screen isn't stretched. With a firm press required, the cursor still follows your finger, but the screen is only touched once you press at least this hard. A full click is 100%.")
        }

        Section {
            Toggle("Show Cursor", isOn: $cursorEnabled)

            if cursorEnabled
            {
                Toggle("Advanced Cursor Settings", isOn: $showsAdvancedCursor)

                if showsAdvancedCursor
                {
                    SteamSliderField(title: String(localized: "Fade Out Time"), value: $fade, sliderRange: 0...3, typedRange: 0...30, step: 0.05, scale: 1, unit: "s", decimals: 2)
                    SteamSliderField(title: String(localized: "Size"), value: $size, sliderRange: 8...80, typedRange: 2...300, step: 1, scale: 1, unit: "pt", decimals: 0)
                    SteamSliderField(title: String(localized: "Outline Width"), value: $outlineWidth, sliderRange: 0...8, typedRange: 0...40, step: 0.5, scale: 1, unit: "pt", decimals: 1)

                    if requirePress
                    {
                        SteamColorField(title: String(localized: "Fill Color"), prefix: "steam.cursor.fill", defaults: (1, 1, 1, 0.5))
                        SteamColorField(title: String(localized: "Outline Color"), prefix: "steam.cursor.outline", defaults: (0, 0, 0, 0.8))
                        SteamColorField(title: String(localized: "Pressed Fill Color"), prefix: "steam.cursor.pressedFill", defaults: (1, 0.2, 0.2, 0.7))
                        SteamColorField(title: String(localized: "Pressed Outline Color"), prefix: "steam.cursor.pressedOutline", defaults: (0.5, 0, 0, 0.9))
                    }
                    else
                    {
                        // Every touch is sent, so the cursor always uses the "pressed" look.
                        SteamColorField(title: String(localized: "Fill Color"), prefix: "steam.cursor.pressedFill", defaults: (1, 0.2, 0.2, 0.7))
                        SteamColorField(title: String(localized: "Outline Color"), prefix: "steam.cursor.pressedOutline", defaults: (0.5, 0, 0, 0.9))
                    }

                    SteamCursorPreview(showsNormal: requirePress)

                    Button("Reset Cursor to Defaults", role: .destructive) {
                        SteamTouchSettings.resetCursor()
                    }
                }
            }
        } header: {
            Text("Cursor")
        } footer: {
            Text("The cursor appears on the bottom screen where your finger is on the trackpad. When a firm press is required, the cursor shows the normal colors until the press is strong enough, then switches to the pressed colors. Without it, the pressed colors show whenever you touch, since every touch is sent to the game. Color pickers include opacity.")
        }
    }
}

private struct SteamSliderField: View
{
    let title: String
    @Binding var value: Double
    let sliderRange: ClosedRange<Double>
    let typedRange: ClosedRange<Double>
    let step: Double
    let scale: Double
    let unit: String
    let decimals: Int

    @SwiftUI.State private var text = ""
    @FocusState private var isFocused: Bool

    private func format(_ value: Double) -> String
    {
        return String(format: "%.\(decimals)f", value * scale)
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { min(max(value, sliderRange.lowerBound), sliderRange.upperBound) },
            set: { value = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField("", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .focused($isFocused)
                    .textFieldStyle(.roundedBorder)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .leading)
            }

            Slider(value: sliderValue, in: sliderRange, step: step)
        }
        .onAppear {
            text = format(value)
        }
        .onChange(of: value) { _, _ in
            if !isFocused { text = format(value) }
        }
        .onChange(of: text) { _, newText in
            guard isFocused, let typed = Double(newText.replacingOccurrences(of: ",", with: ".")) else { return }
            value = min(max(typed / scale, typedRange.lowerBound), typedRange.upperBound)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = format(value) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isFocused
                {
                    Spacer()
                    Button("Done") { isFocused = false }
                }
            }
        }
    }
}

private struct SteamColorField: View
{
    let title: String
    @AppStorage private var red: Double
    @AppStorage private var green: Double
    @AppStorage private var blue: Double
    @AppStorage private var alpha: Double

    init(title: String, prefix: String, defaults: (Double, Double, Double, Double))
    {
        self.title = title
        self._red = AppStorage(wrappedValue: defaults.0, prefix + ".r")
        self._green = AppStorage(wrappedValue: defaults.1, prefix + ".g")
        self._blue = AppStorage(wrappedValue: defaults.2, prefix + ".b")
        self._alpha = AppStorage(wrappedValue: defaults.3, prefix + ".a")
    }

    private var color: Binding<Color> {
        Binding(
            get: { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) },
            set: { newColor in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                UIColor(newColor).getRed(&r, green: &g, blue: &b, alpha: &a)
                red = Double(r)
                green = Double(g)
                blue = Double(b)
                alpha = Double(a)
            }
        )
    }

    var body: some View {
        ColorPicker(title, selection: color, supportsOpacity: true)
    }
}

private struct SteamCursorPreview: View
{
    // The normal (not yet transmitted) cursor only exists when a firm press is required.
    let showsNormal: Bool

    @AppStorage("steam.cursor.size") private var size = 26.0
    @AppStorage("steam.cursor.outlineWidth") private var outlineWidth = 2.0
    @AppStorage("steam.cursor.fill.r") private var fillR = 1.0
    @AppStorage("steam.cursor.fill.g") private var fillG = 1.0
    @AppStorage("steam.cursor.fill.b") private var fillB = 1.0
    @AppStorage("steam.cursor.fill.a") private var fillA = 0.5
    @AppStorage("steam.cursor.outline.r") private var lineR = 0.0
    @AppStorage("steam.cursor.outline.g") private var lineG = 0.0
    @AppStorage("steam.cursor.outline.b") private var lineB = 0.0
    @AppStorage("steam.cursor.outline.a") private var lineA = 0.8
    @AppStorage("steam.cursor.pressedFill.r") private var pFillR = 1.0
    @AppStorage("steam.cursor.pressedFill.g") private var pFillG = 0.2
    @AppStorage("steam.cursor.pressedFill.b") private var pFillB = 0.2
    @AppStorage("steam.cursor.pressedFill.a") private var pFillA = 0.7
    @AppStorage("steam.cursor.pressedOutline.r") private var pLineR = 0.5
    @AppStorage("steam.cursor.pressedOutline.g") private var pLineG = 0.0
    @AppStorage("steam.cursor.pressedOutline.b") private var pLineB = 0.0
    @AppStorage("steam.cursor.pressedOutline.a") private var pLineA = 0.9

    private func dot(fill: Color, line: Color) -> some View
    {
        Circle()
            .fill(fill)
            .overlay(Circle().inset(by: outlineWidth / 2).stroke(line, lineWidth: outlineWidth))
            .frame(width: min(size, 60), height: min(size, 60))
    }

    var body: some View {
        HStack {
            Text("Preview")
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: showsNormal ? 170 : 110, height: 70)

                HStack(spacing: 24) {
                    if showsNormal
                    {
                        dot(fill: Color(.sRGB, red: fillR, green: fillG, blue: fillB, opacity: fillA),
                            line: Color(.sRGB, red: lineR, green: lineG, blue: lineB, opacity: lineA))
                    }

                    dot(fill: Color(.sRGB, red: pFillR, green: pFillG, blue: pFillB, opacity: pFillA),
                        line: Color(.sRGB, red: pLineR, green: pLineG, blue: pLineB, opacity: pLineA))
                }
            }
        }
    }
}

// MARK: - Pause menu shortcut

/// Shown from the pause menu's "Controller" button: Player 1's controller page, opened straight to
/// the controls for the system that is currently running.
struct PauseControllerSettingsView: View
{
    let system: System
    let close: () -> Void

    @SwiftUI.State private var showsEditor = false
    @SwiftUI.State private var didAutoOpen = false

    private var controller: GameController? {
        ExternalGameControllerManager.shared.connectedControllers.first { $0.playerIndex == 0 }
    }

    var body: some View {
        NavigationStack {
            PlayerControllerView(playerIndex: 0)
                .navigationDestination(isPresented: $showsEditor) {
                    if let controller
                    {
                        ControlsEditorView(controller: controller, system: system, playerIndex: 0)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: close)
                    }
                }
        }
        .onAppear {
            guard !didAutoOpen, controller != nil else { return }
            didAutoOpen = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showsEditor = true
            }
        }
    }
}
