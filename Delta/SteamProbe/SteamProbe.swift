//
//  SteamProbe.swift
//
//  Debug overlay for the Steam Controller experiment. Shows a floating "SC" button on top of
//  every screen; tapping it opens a panel with:
//    - Scan BLE: finds the controller, connects, and subscribes to every characteristic.
//    - Wizard: a timed, hands-on-controller walkthrough that records which bits of the
//      controller's 45-byte state report change for each button, stick, trigger and pad,
//      then prints compact RESULT lines you can copy back.
//    - Copy results / Copy all: put the RESULT lines (or the whole log) on the clipboard.
//
//  Characteristic roles seen so far (service 100F6C32-...):
//    100F6C7A  45-byte controller state (buttons, triggers, sticks, pads, IMU)
//    100F6C76  8-byte keyboard-style report (the controller's "lizard mode")
//    100F6C75  5-byte mouse-style report (lizard mode)
//    100F6C78  14-byte periodic status
//

import UIKit
import CoreBluetooth
import GameController
import AudioToolbox

final class SteamProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate
{
    static let shared = SteamProbe()

    private var window: PassthroughWindow?
    private let panel = UIView()
    private let textView = UITextView()
    private let promptLabel = UILabel()

    private var lines: [String] = []
    private var resultLines: [String] = []
    private var refreshPending = false
    private var installed = false

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var seen = Set<UUID>()
    private var unnamedCount = 0
    private var notifyCounts: [String: Int] = [:]
    private var mouseMoveCount = 0
    private var statePacketCount = 0

    // Wizard state
    private var wizardRunning = false
    private var wizardToken = 0
    private var stats = StepStats()
    private var idleCounts = [Int](repeating: 0, count: 32)
    private var idlePackets = 0
    private let stepSeconds: Double = 4.5

    private let wizardSteps: [(name: String, hint: String)] = [
        ("IDLE", "Hold the controller normally. Press NOTHING."),
        ("DPAD UP", "Press and HOLD D-pad UP, then release."),
        ("DPAD DOWN", "Press and HOLD D-pad DOWN, then release."),
        ("DPAD LEFT", "Press and HOLD D-pad LEFT, then release."),
        ("DPAD RIGHT", "Press and HOLD D-pad RIGHT, then release."),
        ("A", "Press and HOLD A, then release."),
        ("B", "Press and HOLD B, then release."),
        ("X", "Press and HOLD X, then release."),
        ("Y", "Press and HOLD Y, then release."),
        ("L1", "Press and HOLD the LEFT bumper (L1)."),
        ("R1", "Press and HOLD the RIGHT bumper (R1)."),
        ("L2", "Pull the LEFT trigger (L2) all the way in and hold."),
        ("R2", "Pull the RIGHT trigger (R2) all the way in and hold."),
        ("L3", "Push the LEFT stick straight DOWN into a click and hold."),
        ("R3", "Push the RIGHT stick straight DOWN into a click and hold."),
        ("LEFT STICK", "Roll the LEFT stick around its edge. NO click."),
        ("RIGHT STICK", "Roll the RIGHT stick around its edge. NO click."),
        ("L4", "Press and HOLD back button L4."),
        ("L5", "Press and HOLD back button L5."),
        ("R4", "Press and HOLD back button R4."),
        ("R5", "Press and HOLD back button R5."),
        ("LEFT PAD TOUCH", "Touch the LEFT trackpad lightly and slide. NO click."),
        ("LEFT PAD CLICK", "Press the LEFT trackpad down into a click and hold."),
        ("RIGHT PAD TOUCH", "Touch the RIGHT trackpad lightly and slide. NO click."),
        ("RIGHT PAD CLICK", "Press the RIGHT trackpad down into a click and hold."),
        ("STEAM", "TAP the Steam button once (do not hold it)."),
        ("MENU", "Press and HOLD the Menu / Start button."),
        ("VIEW", "Press and HOLD the View / Select button."),
        ("EXTRA", "Press any other button not done yet (quick access, etc.)."),
        ("PUT DOWN", "Put the controller DOWN on a table. Hands off."),
    ]

    private let steamKeywords = ["steam", "valve", "triton", "proteus", "nereid"]

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private struct StepStats
    {
        var packets = 0
        var bitCounts = [Int](repeating: 0, count: 32)
        var maxTL = 0
        var maxTR = 0
        var lsMinX = 0, lsMaxX = 0, lsMinY = 0, lsMaxY = 0
        var rsMinX = 0, rsMaxX = 0, rsMinY = 0, rsMaxY = 0
        var lpAbsX = 0, lpAbsY = 0, lpPressure = 0
        var rpAbsX = 0, rpAbsY = 0, rpPressure = 0
        var keys = Set<UInt8>()
        var mouseButtons = Set<UInt8>()
    }

    // MARK: - Install

    func install()
    {
        guard !installed else { return }
        installed = true

        NotificationCenter.default.addObserver(self, selector: #selector(sceneDidActivate(_:)), name: UIScene.didActivateNotification, object: nil)

        log("SteamProbe ready. iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)")
        startGameControllerWatching()
    }

    @objc private func sceneDidActivate(_ notification: Notification)
    {
        guard window == nil, let scene = notification.object as? UIWindowScene else { return }
        buildWindow(scene: scene)
    }

    // MARK: - UI

    private func makeButton(_ title: String, _ action: @escaping () -> Void) -> UIButton
    {
        let button = UIButton(type: .system, primaryAction: UIAction(title: title) { _ in action() })
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.layer.cornerRadius = 6
        return button
    }

    private func buildWindow(scene: UIWindowScene)
    {
        let root = UIViewController()
        root.view.backgroundColor = .clear

        let toggle = UIButton(type: .system, primaryAction: UIAction(title: "SC") { [weak self] _ in
            guard let self = self else { return }
            self.panel.isHidden.toggle()
            self.refreshText()
        })
        toggle.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toggle.setTitleColor(.white, for: .normal)
        toggle.layer.cornerRadius = 8
        toggle.translatesAutoresizingMaskIntoConstraints = false

        panel.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        panel.layer.cornerRadius = 10
        panel.isHidden = true
        panel.translatesAutoresizingMaskIntoConstraints = false

        let scanButton = makeButton("Scan BLE") { [weak self] in self?.startBluetooth() }
        let wizardButton = makeButton("Wizard") { [weak self] in self?.toggleWizard() }
        let copyResultsButton = makeButton("Copy results") { [weak self] in
            guard let self = self else { return }
            let text = self.resultLines.isEmpty ? self.lines.joined(separator: "\n") : self.resultLines.joined(separator: "\n")
            UIPasteboard.general.string = text
            self.log("Copied \(self.resultLines.isEmpty ? self.lines.count : self.resultLines.count) line(s) to clipboard")
        }
        let copyAllButton = makeButton("Copy all") { [weak self] in
            guard let self = self else { return }
            UIPasteboard.general.string = self.lines.joined(separator: "\n")
            self.log("Copied entire log (\(self.lines.count) lines) to clipboard")
        }

        let stack = UIStackView(arrangedSubviews: [scanButton, wizardButton, copyResultsButton, copyAllButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        promptLabel.text = "Wizard idle. Tap Scan BLE, then Wizard."
        promptLabel.numberOfLines = 2
        promptLabel.font = UIFont.boldSystemFont(ofSize: 17)
        promptLabel.textColor = UIColor.systemYellow
        promptLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textColor = UIColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1.0)
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(stack)
        panel.addSubview(promptLabel)
        panel.addSubview(textView)
        root.view.addSubview(panel)
        root.view.addSubview(toggle)

        let guide = root.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            toggle.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
            toggle.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
            toggle.widthAnchor.constraint(equalToConstant: 44),
            toggle.heightAnchor.constraint(equalToConstant: 30),

            panel.topAnchor.constraint(equalTo: toggle.bottomAnchor, constant: 6),
            panel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
            panel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
            panel.heightAnchor.constraint(equalTo: root.view.heightAnchor, multiplier: 0.6),

            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalToConstant: 32),

            promptLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            promptLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            promptLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),

            textView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 6),
            textView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 6),
            textView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -6),
            textView.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),
        ])

        let probeWindow = PassthroughWindow(windowScene: scene)
        probeWindow.windowLevel = .alert + 1
        probeWindow.backgroundColor = .clear
        probeWindow.rootViewController = root
        probeWindow.isHidden = false
        window = probeWindow

        refreshText()
    }

    // MARK: - Logging

    private func log(_ message: String)
    {
        lines.append("\(formatter.string(from: Date())) \(message)")
        if lines.count > 600 { lines.removeFirst(lines.count - 600) }

        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshText()
        }
    }

    private func refreshText()
    {
        refreshPending = false
        textView.text = lines.joined(separator: "\n")
        guard !panel.isHidden, !textView.text.isEmpty else { return }
        textView.scrollRangeToVisible(NSRange(location: textView.text.utf16.count - 1, length: 1))
    }

    private func hex(_ data: Data) -> String
    {
        let bytes = data.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
        return data.count > 64 ? "\(bytes) ... (\(data.count) bytes)" : "\(bytes) (\(data.count) bytes)"
    }

    // MARK: - Wizard

    private func toggleWizard()
    {
        if wizardRunning
        {
            wizardToken += 1
            wizardRunning = false
            promptLabel.text = "Wizard cancelled."
            log("Wizard cancelled")
            return
        }

        guard statePacketCount > 0 else
        {
            promptLabel.text = "No controller data yet. Tap Scan BLE first."
            log("Wizard: no controller data yet. Tap Scan BLE first.")
            return
        }

        wizardRunning = true
        wizardToken += 1
        resultLines.removeAll()
        idleCounts = [Int](repeating: 0, count: 32)
        idlePackets = 0
        log("Wizard started: \(wizardSteps.count) steps, \(stepSeconds) s each. Hold the controller and follow the prompts.")
        runStep(0, token: wizardToken)
    }

    private func runStep(_ index: Int, token: Int)
    {
        guard token == wizardToken else { return }

        stats = StepStats()
        promptLabel.text = "\(index + 1)/\(wizardSteps.count)  \(wizardSteps[index].hint)"
        AudioServicesPlaySystemSound(1104)

        DispatchQueue.main.asyncAfter(deadline: .now() + stepSeconds) { [weak self] in
            guard let self = self, token == self.wizardToken else { return }
            self.finishStep(index)

            if index + 1 < self.wizardSteps.count
            {
                self.runStep(index + 1, token: token)
            }
            else
            {
                self.wizardRunning = false
                self.promptLabel.text = "Wizard done. Tap Copy results and paste it to Claude."
                AudioServicesPlaySystemSound(1105)
                self.log("Wizard finished (\(self.resultLines.count) result lines)")
            }
        }
    }

    private func bitName(_ bit: Int) -> String
    {
        return String(format: "i%d:%02x", Int32(1 + bit / 8), UInt32(1 << (bit % 8)))
    }

    private func finishStep(_ index: Int)
    {
        let s = stats
        let name = wizardSteps[index].name
        var parts: [String] = ["RESULT [\(name)] n=\(s.packets)"]

        if index == 0
        {
            idleCounts = s.bitCounts
            idlePackets = s.packets
            let on = (0..<32).filter { s.bitCounts[$0] * 2 > s.packets }.map { bitName($0) }
            parts.append("baseline-on=" + (on.isEmpty ? "-" : on.joined(separator: ",")))
        }
        else
        {
            var added: [String] = []
            var cleared: [String] = []
            for bit in 0..<32
            {
                let idleFraction = idlePackets > 0 ? Double(idleCounts[bit]) / Double(idlePackets) : 0
                let fraction = s.packets > 0 ? Double(s.bitCounts[bit]) / Double(s.packets) : 0
                if s.bitCounts[bit] >= 4 && idleFraction < 0.2 { added.append(bitName(bit)) }
                if idleFraction > 0.8 && fraction < 0.2 { cleared.append(bitName(bit)) }
            }
            parts.append("new=" + (added.isEmpty ? "-" : added.joined(separator: ",")))
            parts.append("off=" + (cleared.isEmpty ? "-" : cleared.joined(separator: ",")))
        }

        if s.maxTL > 1000 { parts.append("TL=\(s.maxTL)") }
        if s.maxTR > 1000 { parts.append("TR=\(s.maxTR)") }
        if max(abs(s.lsMinX), s.lsMaxX, abs(s.lsMinY), s.lsMaxY) > 5000
        {
            parts.append("LS x[\(s.lsMinX),\(s.lsMaxX)] y[\(s.lsMinY),\(s.lsMaxY)]")
        }
        if max(abs(s.rsMinX), s.rsMaxX, abs(s.rsMinY), s.rsMaxY) > 5000
        {
            parts.append("RS x[\(s.rsMinX),\(s.rsMaxX)] y[\(s.rsMinY),\(s.rsMaxY)]")
        }
        if s.lpPressure > 0 || s.lpAbsX > 0 || s.lpAbsY > 0
        {
            parts.append("LP x\(s.lpAbsX) y\(s.lpAbsY) p\(s.lpPressure)")
        }
        if s.rpPressure > 0 || s.rpAbsX > 0 || s.rpAbsY > 0
        {
            parts.append("RP x\(s.rpAbsX) y\(s.rpAbsY) p\(s.rpPressure)")
        }
        if !s.keys.isEmpty
        {
            parts.append("kbd=" + s.keys.sorted().map { String(format: "%02x", $0) }.joined(separator: ","))
        }
        if !s.mouseButtons.isEmpty
        {
            parts.append("mouseBtn=" + s.mouseButtons.sorted().map { String(format: "%02x", $0) }.joined(separator: ","))
        }

        let line = parts.joined(separator: " ")
        resultLines.append(line)
        log(line)
    }

    // MARK: - Report decoding

    private func s16(_ data: Data, _ index: Int) -> Int
    {
        let lo = UInt16(data[data.startIndex + index])
        let hi = UInt16(data[data.startIndex + index + 1])
        return Int(Int16(bitPattern: lo | (hi << 8)))
    }

    private func handleState(_ data: Data)
    {
        guard data.count >= 29 else { return }
        statePacketCount += 1
        guard wizardRunning else { return }

        stats.packets += 1
        for byteIndex in 0..<4
        {
            let value = data[data.startIndex + 1 + byteIndex]
            for bit in 0..<8 where (value >> UInt8(bit)) & 1 == 1
            {
                stats.bitCounts[byteIndex * 8 + bit] += 1
            }
        }

        stats.maxTL = max(stats.maxTL, s16(data, 5))
        stats.maxTR = max(stats.maxTR, s16(data, 7))

        let lsx = s16(data, 9), lsy = s16(data, 11)
        stats.lsMinX = min(stats.lsMinX, lsx); stats.lsMaxX = max(stats.lsMaxX, lsx)
        stats.lsMinY = min(stats.lsMinY, lsy); stats.lsMaxY = max(stats.lsMaxY, lsy)

        let rsx = s16(data, 13), rsy = s16(data, 15)
        stats.rsMinX = min(stats.rsMinX, rsx); stats.rsMaxX = max(stats.rsMaxX, rsx)
        stats.rsMinY = min(stats.rsMinY, rsy); stats.rsMaxY = max(stats.rsMaxY, rsy)

        stats.lpAbsX = max(stats.lpAbsX, abs(s16(data, 17)))
        stats.lpAbsY = max(stats.lpAbsY, abs(s16(data, 19)))
        stats.lpPressure = max(stats.lpPressure, s16(data, 21))
        stats.rpAbsX = max(stats.rpAbsX, abs(s16(data, 23)))
        stats.rpAbsY = max(stats.rpAbsY, abs(s16(data, 25)))
        stats.rpPressure = max(stats.rpPressure, s16(data, 27))
    }

    private func handleKeys(_ data: Data)
    {
        guard wizardRunning, data.count >= 8 else { return }
        for index in 2..<8
        {
            let key = data[data.startIndex + index]
            if key != 0 { stats.keys.insert(key) }
        }
    }

    private func handleMouse(_ data: Data)
    {
        guard wizardRunning, data.count >= 1 else { return }
        let buttons = data[data.startIndex]
        if buttons != 0 { stats.mouseButtons.insert(buttons) }
    }

    // MARK: - GameController framework

    private func startGameControllerWatching()
    {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(gamepadConnected(_:)), name: .GCControllerDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(gamepadDisconnected(_:)), name: .GCControllerDidDisconnect, object: nil)
        nc.addObserver(self, selector: #selector(keyboardConnected(_:)), name: .GCKeyboardDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(keyboardDisconnected(_:)), name: .GCKeyboardDidDisconnect, object: nil)
        nc.addObserver(self, selector: #selector(mouseConnected(_:)), name: .GCMouseDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(mouseDisconnected(_:)), name: .GCMouseDidDisconnect, object: nil)

        let pads = GCController.controllers()
        log("GameController: \(pads.count) gamepad(s) at start")
        pads.forEach { attach($0) }

        if let keyboard = GCKeyboard.coalesced
        {
            attach(keyboard)
        }
        else
        {
            log("GameController: no keyboard at start")
        }

        let mice = GCMouse.mice()
        log("GameController: \(mice.count) mouse/mice at start")
        mice.forEach { attach($0) }
    }

    @objc private func gamepadConnected(_ notification: Notification)
    {
        if let pad = notification.object as? GCController { attach(pad) }
    }

    @objc private func gamepadDisconnected(_ notification: Notification)
    {
        if let pad = notification.object as? GCController { log("GAMEPAD disconnected: \(pad.vendorName ?? "?")") }
    }

    @objc private func keyboardConnected(_ notification: Notification)
    {
        if let keyboard = notification.object as? GCKeyboard { attach(keyboard) }
    }

    @objc private func keyboardDisconnected(_ notification: Notification)
    {
        log("KEYBOARD disconnected")
    }

    @objc private func mouseConnected(_ notification: Notification)
    {
        if let mouse = notification.object as? GCMouse { attach(mouse) }
    }

    @objc private func mouseDisconnected(_ notification: Notification)
    {
        log("MOUSE disconnected")
    }

    private func attach(_ pad: GCController)
    {
        log("GAMEPAD connected: \(pad.vendorName ?? "?") category=\(pad.productCategory) extended=\(pad.extendedGamepad != nil)")
        pad.extendedGamepad?.valueChangedHandler = { [weak self] _, element in
            self?.log("pad: \(element.aliases.sorted().joined(separator: "/"))")
        }
    }

    private func attach(_ keyboard: GCKeyboard)
    {
        log("KEYBOARD connected: \(keyboard.vendorName ?? "?")")
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            self?.log("key \(keyCode.rawValue) \(pressed ? "down" : "up")")
        }
    }

    private func attach(_ mouse: GCMouse)
    {
        log("MOUSE connected: \(mouse.vendorName ?? "?")")
        guard let input = mouse.mouseInput else { return }

        input.mouseMovedHandler = { [weak self] _, dx, dy in
            guard let self = self else { return }
            self.mouseMoveCount += 1
            if self.mouseMoveCount % 15 == 1 { self.log("mouse move dx=\(dx) dy=\(dy) (#\(self.mouseMoveCount))") }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.log("mouse left \(pressed ? "down" : "up")")
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.log("mouse right \(pressed ? "down" : "up")")
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.log("mouse middle \(pressed ? "down" : "up")")
        }
    }

    // MARK: - CoreBluetooth

    private func startBluetooth()
    {
        if central == nil
        {
            log("BLE: starting (iOS may ask for Bluetooth permission)")
            central = CBCentralManager(delegate: self, queue: .main)
        }
        else
        {
            scan()
        }
    }

    private func scan()
    {
        guard let central = central, central.state == .poweredOn else
        {
            log("BLE: not powered on yet")
            return
        }

        let services = [CBUUID(string: "1812"), CBUUID(string: "180F"), CBUUID(string: "180A"), CBUUID(string: "1800")]
        let connected = central.retrieveConnectedPeripherals(withServices: services)
        log("BLE: \(connected.count) peripheral(s) already connected (HID/battery/device-info/generic)")
        connected.forEach { peripheral in
            log("BLE: already connected: \(peripheral.name ?? "unnamed") \(peripheral.identifier.uuidString.prefix(8))")
            consider(peripheral)
        }

        seen.removeAll()
        unnamedCount = 0
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("BLE: scanning for 25 s. Put the controller in Bluetooth mode now.")

        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self = self, let central = self.central, central.isScanning else { return }
            central.stopScan()
            self.log("BLE: scan finished (\(self.unnamedCount) unnamed devices ignored)")
        }
    }

    private func isSteam(_ name: String) -> Bool
    {
        let lower = name.lowercased()
        return steamKeywords.contains { lower.contains($0) }
    }

    private func consider(_ peripheral: CBPeripheral)
    {
        guard peripherals[peripheral.identifier] == nil, let central = central else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        log("BLE: connecting to \(peripheral.name ?? "unnamed")")
        central.connect(peripheral, options: nil)
    }

    private func describe(_ properties: CBCharacteristicProperties) -> String
    {
        var parts: [String] = []
        if properties.contains(.read) { parts.append("read") }
        if properties.contains(.write) { parts.append("write") }
        if properties.contains(.writeWithoutResponse) { parts.append("writeNoResp") }
        if properties.contains(.notify) { parts.append("notify") }
        if properties.contains(.indicate) { parts.append("indicate") }
        return parts.joined(separator: ",")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager)
    {
        log("BLE: state = \(central.state.rawValue) (5 = powered on)")
        if central.state == .poweredOn { scan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""

        if name.isEmpty
        {
            unnamedCount += 1
            return
        }

        if seen.insert(peripheral.identifier).inserted
        {
            log("BLE saw: \(name) rssi=\(RSSI)")
        }

        if isSteam(name) { consider(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        log("BLE: connected to \(peripheral.name ?? "unnamed"), discovering services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    {
        log("BLE: connect failed: \(error?.localizedDescription ?? "unknown")")
        peripherals[peripheral.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        log("BLE: disconnected: \(error?.localizedDescription ?? "no error")")
        peripherals[peripheral.identifier] = nil
        statePacketCount = 0
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        if let error = error
        {
            log("BLE: service discovery error: \(error.localizedDescription)")
            return
        }

        let services = peripheral.services ?? []
        log("BLE: \(services.count) service(s)")
        for service in services
        {
            log(" service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        if let error = error
        {
            log("BLE: characteristic error: \(error.localizedDescription)")
            return
        }

        for characteristic in service.characteristics ?? []
        {
            log("  char \(characteristic.uuid.uuidString) [\(describe(characteristic.properties))]")

            if characteristic.properties.contains(.read)
            {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    {
        if let error = error
        {
            log("BLE: notify failed on \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        if let error = error
        {
            log("BLE: read error on \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        guard let value = characteristic.value else { return }

        let key = characteristic.uuid.uuidString.uppercased()

        // Route the controller's reports to the decoders.
        var isStream = false
        if key.hasPrefix("100F6C7A") { handleState(value); isStream = true }
        else if key.hasPrefix("100F6C76") { handleKeys(value); isStream = true }
        else if key.hasPrefix("100F6C75") { handleMouse(value); isStream = true }
        else if key.hasPrefix("100F6C78") || key.hasPrefix("100F6C77") || key.hasPrefix("100F6C79") { isStream = true }

        // Keep the log quiet while the wizard is recording.
        if wizardRunning && isStream { return }

        let count = (notifyCounts[key] ?? 0) + 1
        notifyCounts[key] = count

        // Log the first 20 values in full, then only every 25th so the log stays readable.
        if count <= 20 || count % 25 == 0
        {
            log("DATA \(key.prefix(8)) #\(count): \(hex(value))")
        }
    }
}

// Lets touches pass through everywhere except the probe's own buttons and panel.
private final class PassthroughWindow: UIWindow
{
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        let view = super.hitTest(point, with: event)
        if view === self || view === rootViewController?.view { return nil }
        return view
    }
}
