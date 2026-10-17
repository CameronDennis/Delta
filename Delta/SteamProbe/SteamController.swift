//
//  SteamController.swift
//
//  Makes a Steam Controller (2026, Bluetooth) show up in Delta as its own controller type.
//  It talks to the controller directly over CoreBluetooth (the controller exposes no HID
//  service on iPadOS), decodes the 45-byte state report, and feeds it to Delta.
//
//  Pair the controller once in iPadOS Settings > Bluetooth, then just open Delta.
//

import Foundation
import CoreBluetooth
import DeltaCore
import MelonDSDeltaCore

extension GameControllerInputType
{
    static let steam = GameControllerInputType("steam")
}

// MARK: - Inputs

struct SteamInput: Hashable, RawRepresentable, Codable
{
    let rawValue: String

    init(rawValue: String)
    {
        self.rawValue = rawValue
    }

    init(_ rawValue: String)
    {
        self.rawValue = rawValue
    }
}

extension SteamInput: Input
{
    var type: InputType {
        return .controller(.steam)
    }

    var isContinuous: Bool {
        return SteamInput.continuousInputs.contains(self.rawValue)
    }

    init(stringValue: String)
    {
        self.init(rawValue: stringValue)
    }
}

extension SteamInput
{
    static let a = SteamInput("a")
    static let b = SteamInput("b")
    static let x = SteamInput("x")
    static let y = SteamInput("y")
    static let up = SteamInput("up")
    static let down = SteamInput("down")
    static let left = SteamInput("left")
    static let right = SteamInput("right")
    static let leftShoulder = SteamInput("leftShoulder")
    static let leftTrigger = SteamInput("leftTrigger")
    static let rightShoulder = SteamInput("rightShoulder")
    static let rightTrigger = SteamInput("rightTrigger")
    static let start = SteamInput("start")
    static let select = SteamInput("select")
    static let menu = SteamInput("menu")

    static let leftThumbstickUp = SteamInput("leftThumbstickUp")
    static let leftThumbstickDown = SteamInput("leftThumbstickDown")
    static let leftThumbstickLeft = SteamInput("leftThumbstickLeft")
    static let leftThumbstickRight = SteamInput("leftThumbstickRight")
    static let rightThumbstickUp = SteamInput("rightThumbstickUp")
    static let rightThumbstickDown = SteamInput("rightThumbstickDown")
    static let rightThumbstickLeft = SteamInput("rightThumbstickLeft")
    static let rightThumbstickRight = SteamInput("rightThumbstickRight")

    // Extra inputs. These are not mapped by default; add them from the controller's settings.
    static let l3 = SteamInput("l3")
    static let r3 = SteamInput("r3")
    static let l4 = SteamInput("l4")
    static let l5 = SteamInput("l5")
    static let r4 = SteamInput("r4")
    static let r5 = SteamInput("r5")
    static let leftPadClick = SteamInput("leftPadClick")
    static let rightPadClick = SteamInput("rightPadClick")
    static let leftPadTouch = SteamInput("leftPadTouch")
    static let rightPadTouch = SteamInput("rightPadTouch")
    static let quickAccess = SteamInput("quickAccess")

    // Absolute trackpad position (0...1). Used for the touchscreen option.
    static let leftPadX = SteamInput("leftPadX")
    static let leftPadY = SteamInput("leftPadY")
    static let rightPadX = SteamInput("rightPadX")
    static let rightPadY = SteamInput("rightPadY")

    static let buttons: [SteamInput] = [.a, .b, .x, .y, .up, .down, .left, .right, .leftShoulder, .leftTrigger, .rightShoulder, .rightTrigger, .start, .select, .menu]
    static let leftThumbstick: [SteamInput] = [.leftThumbstickUp, .leftThumbstickDown, .leftThumbstickLeft, .leftThumbstickRight]
    static let rightThumbstick: [SteamInput] = [.rightThumbstickUp, .rightThumbstickDown, .rightThumbstickLeft, .rightThumbstickRight]
    static let extras: [SteamInput] = [.l3, .r3, .l4, .l5, .r4, .r5, .leftPadClick, .rightPadClick, .leftPadTouch, .rightPadTouch, .quickAccess]

    static let continuousInputs: Set<String> = Set((leftThumbstick + rightThumbstick + [leftPadX, leftPadY, rightPadX, rightPadY]).map { $0.rawValue })

    var displayName: String {
        switch self.rawValue
        {
        case "a": return "A Button"
        case "b": return "B Button"
        case "x": return "X Button"
        case "y": return "Y Button"
        case "up": return "D-Pad Up"
        case "down": return "D-Pad Down"
        case "left": return "D-Pad Left"
        case "right": return "D-Pad Right"
        case "leftShoulder": return "L1"
        case "leftTrigger": return "L2"
        case "rightShoulder": return "R1"
        case "rightTrigger": return "R2"
        case "start": return "Menu"
        case "select": return "View"
        case "menu": return "Steam"
        case "leftThumbstickUp": return "Left Stick Up"
        case "leftThumbstickDown": return "Left Stick Down"
        case "leftThumbstickLeft": return "Left Stick Left"
        case "leftThumbstickRight": return "Left Stick Right"
        case "rightThumbstickUp": return "Right Stick Up"
        case "rightThumbstickDown": return "Right Stick Down"
        case "rightThumbstickLeft": return "Right Stick Left"
        case "rightThumbstickRight": return "Right Stick Right"
        case "l3": return "L3 (Left Stick Click)"
        case "r3": return "R3 (Right Stick Click)"
        case "l4": return "L4"
        case "l5": return "L5"
        case "r4": return "R4"
        case "r5": return "R5"
        case "leftPadClick": return "Left Pad Click"
        case "rightPadClick": return "Right Pad Click"
        case "leftPadTouch": return "Left Pad Touch"
        case "rightPadTouch": return "Right Pad Touch"
        case "quickAccess": return "Quick Access"
        case "leftPadX": return "Left Pad X"
        case "leftPadY": return "Left Pad Y"
        case "rightPadX": return "Right Pad X"
        case "rightPadY": return "Right Pad Y"
        default: return self.rawValue
        }
    }

    var shortName: String {
        switch self.rawValue
        {
        case "up": return "Up"
        case "down": return "Down"
        case "left": return "Left"
        case "right": return "Right"
        case "a", "b", "x", "y": return self.rawValue.uppercased()
        case "leftThumbstickUp": return "L🕹↑"
        case "leftThumbstickDown": return "L🕹↓"
        case "leftThumbstickLeft": return "L🕹←"
        case "leftThumbstickRight": return "L🕹→"
        case "rightThumbstickUp": return "R🕹↑"
        case "rightThumbstickDown": return "R🕹↓"
        case "rightThumbstickLeft": return "R🕹←"
        case "rightThumbstickRight": return "R🕹→"
        default: return self.displayName
        }
    }

    var symbolName: String {
        switch self.rawValue
        {
        case "a": return "a.circle"
        case "b": return "b.circle"
        case "x": return "x.circle"
        case "y": return "y.circle"
        case "up": return "dpad.up.filled"
        case "down": return "dpad.down.filled"
        case "left": return "dpad.left.filled"
        case "right": return "dpad.right.filled"
        case "leftShoulder": return "l1.button.roundedtop.horizontal"
        case "leftTrigger": return "l2.button.roundedtop.horizontal"
        case "rightShoulder": return "r1.button.roundedtop.horizontal"
        case "rightTrigger": return "r2.button.roundedtop.horizontal"
        case "start": return "line.3.horizontal.circle"
        case "select": return "rectangle.on.rectangle.circle"
        case "menu": return "gamecontroller"
        case "l3": return "l.joystick.press.down"
        case "r3": return "r.joystick.press.down"
        case "l4", "l5", "r4", "r5": return "circle.fill"
        case "leftPadClick", "rightPadClick", "leftPadTouch", "rightPadTouch", "leftPadX", "leftPadY", "rightPadX", "rightPadY": return "hand.point.up.left"
        case "quickAccess": return "ellipsis.circle"
        default:
            if self.rawValue.hasPrefix("left") { return "l.joystick" }
            if self.rawValue.hasPrefix("right") { return "r.joystick" }
            return "gamecontroller"
        }
    }
}

// MARK: - Controller

final class SteamGameController: NSObject, GameController
{
    let name = "Steam Controller"
    var playerIndex: Int? {
        didSet {
            // The controller also shows up as a keyboard on iPadOS. Once it is assigned to a player,
            // take the keyboard away from every player. It can still be turned back on in Delta's settings.
            if playerIndex != nil { SteamGameController.unassignKeyboards() }
        }
    }

    let inputType: GameControllerInputType = .steam

    // The core buttons start with Delta's stock layout. Extras are left unmapped until the user adds them.
    lazy var defaultInputMapping: GameControllerInputMappingProtocol? = SteamGameController.makeDefaultMapping()

    /// Set to true if pushing a stick up moves characters down.
    static let invertStickY = false

    /// Set to true if the trackpads feel upside down when used as the DS touchscreen.
    static let invertPadY = false

    private var active: [SteamInput: Double] = [:]
    private var padWasTouching = [false, false]
    private var padPressed = [false, false]

    static func unassignKeyboards()
    {
        for case let keyboard as KeyboardGameController in ExternalGameControllerManager.shared.connectedControllers
        {
            keyboard.playerIndex = nil
        }
    }

    /// Moves this controller to the lowest player slot nobody else is using (e.g. the keyboard's old slot).
    func claimLowestFreePlayerIndex()
    {
        let taken = Set(ExternalGameControllerManager.shared.connectedControllers.filter { $0 !== self }.compactMap { $0.playerIndex })

        var index = 0
        while taken.contains(index) { index += 1 }

        if let current = playerIndex, index < current { playerIndex = index }
    }

    private static func makeDefaultMapping() -> GameControllerInputMappingProtocol?
    {
        guard let mfi = ExternalGameControllerManager.shared.mfiDefaultInputMapping as? DeltaCore.GameControllerInputMapping else { return nil }

        var mapping = DeltaCore.GameControllerInputMapping(gameControllerInputType: .steam)
        mapping.name = "Default Steam Controller"

        for input in mfi.supportedControllerInputs
        {
            mapping.set(mfi.input(forControllerInput: input), forControllerInput: SteamInput(stringValue: input.stringValue))
        }

        return mapping
    }

    func process(_ data: Data)
    {
        guard data.count >= 29 else { return }
        let b = [UInt8](data)

        func has(_ index: Int, _ mask: UInt8) -> Bool { return b[index] & mask != 0 }
        func s16(_ index: Int) -> Int { return Int(Int16(bitPattern: UInt16(b[index]) | (UInt16(b[index + 1]) << 8))) }

        var want: [SteamInput: Double] = [:]

        // Face buttons
        if has(1, 0x01) { want[.a] = 1 }
        if has(1, 0x02) { want[.b] = 1 }
        if has(1, 0x04) { want[.x] = 1 }
        if has(1, 0x08) { want[.y] = 1 }

        // D-pad
        if has(2, 0x20) { want[.up] = 1 }
        if has(2, 0x04) { want[.down] = 1 }
        if has(2, 0x10) { want[.left] = 1 }
        if has(2, 0x08) { want[.right] = 1 }

        // Shoulders and digital trigger clicks
        if has(3, 0x08) { want[.leftShoulder] = 1 }
        if has(2, 0x02) { want[.rightShoulder] = 1 }
        if has(4, 0x08) { want[.leftTrigger] = 1 }
        if has(3, 0x80) { want[.rightTrigger] = 1 }

        // Center buttons: Steam, Menu (three lines), View (two squares)
        if has(3, 0x01) { want[.menu] = 1 }
        if has(1, 0x40) { want[.start] = 1 }
        if has(2, 0x40) { want[.select] = 1 }

        // Extras
        if has(2, 0x80) { want[.l3] = 1 }
        if has(1, 0x20) { want[.r3] = 1 }
        if has(3, 0x02) { want[.l4] = 1 }
        if has(3, 0x04) { want[.l5] = 1 }
        if has(1, 0x80) { want[.r4] = 1 }
        if has(2, 0x01) { want[.r5] = 1 }
        // A trackpad acting as the touchscreen ignores its click/touch bindings (they are kept, just inactive).
        let leftIsTouchscreen = isMappedToTouchscreen(.leftPadX)
        let rightIsTouchscreen = isMappedToTouchscreen(.rightPadX)
        if has(4, 0x04), !leftIsTouchscreen { want[.leftPadClick] = 1 }
        if has(3, 0x40), !rightIsTouchscreen { want[.rightPadClick] = 1 }
        if has(4, 0x02), !leftIsTouchscreen { want[.leftPadTouch] = 1 }
        if has(3, 0x20), !rightIsTouchscreen { want[.rightPadTouch] = 1 }
        if has(1, 0x10) { want[.quickAccess] = 1 }

        // Sticks
        let yFlip: Double = SteamGameController.invertStickY ? -1 : 1
        addAxis(&want, Double(s16(9)) / 32767, negative: .leftThumbstickLeft, positive: .leftThumbstickRight)
        addAxis(&want, yFlip * Double(s16(11)) / 32767, negative: .leftThumbstickDown, positive: .leftThumbstickUp)
        addAxis(&want, Double(s16(13)) / 32767, negative: .rightThumbstickLeft, positive: .rightThumbstickRight)
        addAxis(&want, yFlip * Double(s16(15)) / 32767, negative: .rightThumbstickDown, positive: .rightThumbstickUp)

        // Trackpad positions (and the touchscreen cursor), only while a finger is on the pad.
        handlePad(&want, index: 0, touching: has(4, 0x02), x: s16(17), y: s16(19), pressure: s16(21), xInput: .leftPadX, yInput: .leftPadY)
        handlePad(&want, index: 1, touching: has(3, 0x20), x: s16(23), y: s16(25), pressure: s16(27), xInput: .rightPadX, yInput: .rightPadY)

        // Diff against what is currently pressed.
        for key in Set(want.keys).union(active.keys)
        {
            if let value = want[key]
            {
                if let previous = active[key], abs(previous - value) < 0.002 { continue }
                active[key] = value
                activate(key, value: value)
            }
            else if active[key] != nil
            {
                active[key] = nil
                deactivate(key)
            }
        }
    }

    func releaseAll()
    {
        for key in active.keys { deactivate(key) }
        active.removeAll()

        for index in 0..<2
        {
            padWasTouching[index] = false
            padPressed[index] = false
            SteamCursor.shared.release(source: index)
        }
    }

    private func addAxis(_ want: inout [SteamInput: Double], _ raw: Double, negative: SteamInput, positive: SteamInput)
    {
        let deadzone = 0.12
        let magnitude = abs(raw)
        guard magnitude > deadzone else { return }
        let scaled = min(1.0, (magnitude - deadzone) / (1.0 - deadzone))
        if raw < 0 { want[negative] = scaled } else { want[positive] = scaled }
    }

    private func isMappedToTouchscreen(_ input: SteamInput) -> Bool
    {
        let touchX = MelonDSGameInput.touchScreenX.stringValue

        for receiver in receivers
        {
            if let mapping = inputMapping(for: receiver), mapping.input(forControllerInput: input)?.stringValue == touchX
            {
                return true
            }
        }

        return false
    }

    private func handlePad(_ want: inout [SteamInput: Double], index: Int, touching: Bool, x: Int, y: Int, pressure: Int, xInput: SteamInput, yInput: SteamInput)
    {
        guard touching else
        {
            if padWasTouching[index]
            {
                padWasTouching[index] = false
                padPressed[index] = false
                SteamCursor.shared.release(source: index)
            }
            return
        }

        padWasTouching[index] = true

        var nx = min(1.0, max(0.0, (Double(x) + 32768) / 65535))
        var ny = min(1.0, max(0.0, (Double(y) + 32768) / 65535))

        // Pad Y is up-positive; screens count down from the top.
        if !SteamGameController.invertPadY { ny = 1 - ny }

        // Optionally use a 4:3 area of the (roughly square) pad so the DS screen isn't stretched.
        if SteamTouchSettings.aspect43 { ny = min(1.0, max(0.0, (ny - 0.125) / 0.75)) }

        nx = min(1.0, max(0.0, nx))

        var passes = true

        if SteamTouchSettings.requirePress
        {
            let level = Double(max(0, pressure)) / 32767
            let threshold = SteamTouchSettings.pressThreshold

            // A little hysteresis so the touch doesn't flicker right at the threshold.
            passes = padPressed[index] ? (level >= threshold * 0.8) : (level >= threshold)
            padPressed[index] = passes
        }

        if isMappedToTouchscreen(xInput)
        {
            // With a firm press required, the cursor changes color once the touch is actually sent.
            SteamCursor.shared.show(x: nx, y: ny, source: index, pressed: SteamTouchSettings.requirePress && passes)
        }

        if passes
        {
            want[xInput] = nx
            want[yInput] = ny
        }
    }
}

// MARK: - Bluetooth connection

final class SteamController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate
{
    static let shared = SteamController()

    private let serviceUUID = CBUUID(string: "100F6C32-1735-4313-B402-38567131E5F3")
    private let stateUUID = CBUUID(string: "100F6C7A-1735-4313-B402-38567131E5F3")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var controller: SteamGameController?

    func start()
    {
        SteamTouchSettings.registerDefaults()

        // If the keyboard (re)connects while the Steam Controller is in use, keep it unassigned.
        NotificationCenter.default.addObserver(forName: .externalGameControllerDidConnect, object: nil, queue: .main) { [weak self] notification in
            guard let keyboard = notification.object as? KeyboardGameController,
                  let steam = self?.controller, steam.playerIndex != nil else { return }
            keyboard.playerIndex = nil
        }

        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func beginSearch()
    {
        guard let central = central, central.state == .poweredOn, peripheral == nil else { return }

        // Already connected to the system (paired controller that is awake)?
        if let known = central.retrieveConnectedPeripherals(withServices: [serviceUUID]).first
        {
            connect(known)
            return
        }

        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func connect(_ found: CBPeripheral)
    {
        central?.stopScan()
        peripheral = found
        found.delegate = self
        central?.connect(found, options: nil)
    }

    private func isSteamController(_ name: String) -> Bool
    {
        let lower = name.lowercased()
        return lower.contains("steam") || lower.contains("triton")
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager)
    {
        if central.state == .poweredOn { beginSearch() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        if isSteamController(name), self.peripheral == nil { connect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    {
        self.peripheral = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.beginSearch() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        if let controller = controller
        {
            controller.releaseAll()
            ExternalGameControllerManager.shared.removeExternal(controller)
            self.controller = nil
        }

        self.peripheral = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.beginSearch() }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        for service in peripheral.services ?? [] where service.uuid == serviceUUID
        {
            peripheral.discoverCharacteristics([stateUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == stateUUID
        {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        guard error == nil, characteristic.uuid == stateUUID, let value = characteristic.value else { return }

        if controller == nil
        {
            let newController = SteamGameController()
            controller = newController
            ExternalGameControllerManager.shared.addExternal(newController)
            newController.claimLowestFreePlayerIndex()
        }

        controller?.process(value)
    }
}
