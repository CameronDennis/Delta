//
//  SteamProbe.swift
//
//  Debug overlay for the Steam Controller experiment. Shows a floating "SC" button on top of
//  every screen; tapping it opens a log of everything the iPad can see about the controller:
//    - GameController framework: gamepads, keyboards, mice
//    - CoreBluetooth: anything named like a Steam Controller, with all of its GATT services,
//      characteristics, and live notification bytes.
//

import UIKit
import CoreBluetooth
import GameController

final class SteamProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate
{
    static let shared = SteamProbe()

    private var window: PassthroughWindow?
    private let panel = UIView()
    private let textView = UITextView()

    private var lines: [String] = []
    private var refreshPending = false
    private var installed = false

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var seen = Set<UUID>()
    private var unnamedCount = 0
    private var notifyCounts: [String: Int] = [:]
    private var mouseMoveCount = 0

    private let steamKeywords = ["steam", "valve", "triton", "proteus", "nereid"]

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

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
        let copyButton = makeButton("Copy log") { [weak self] in
            guard let self = self else { return }
            UIPasteboard.general.string = self.lines.joined(separator: "\n")
            self.log("Log copied to clipboard (\(self.lines.count) lines)")
        }
        let clearButton = makeButton("Clear") { [weak self] in
            self?.lines.removeAll()
            self?.refreshText()
        }

        let stack = UIStackView(arrangedSubviews: [scanButton, copyButton, clearButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textColor = UIColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1.0)
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(stack)
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
            panel.heightAnchor.constraint(equalTo: root.view.heightAnchor, multiplier: 0.55),

            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalToConstant: 32),

            textView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6),
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
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }

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
        log("BLE: scanning for 25 s. Put the controller in Bluetooth pairing mode now.")

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

        let key = characteristic.uuid.uuidString
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
