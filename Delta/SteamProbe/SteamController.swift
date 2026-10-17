//
//  SteamController.swift
//
//  Makes a Steam Controller (2026, Bluetooth) show up in Delta as a regular controller.
//  It talks to the controller directly over CoreBluetooth (the controller exposes no HID
//  service on iPadOS), decodes the 45-byte state report, and feeds it to Delta as an
//  MFi-style GameController.
//
//  Pair the controller once in iPadOS Settings > Bluetooth, then just open Delta.
//

import Foundation
import CoreBluetooth
import DeltaCore

// MARK: - Controller

final class SteamGameController: NSObject, GameController
{
    let name = "Steam Controller"
    var playerIndex: Int?
    let inputType: GameControllerInputType = .mfi

    // Reuse Delta's stock MFi layout so the controller works out of the box and can be remapped in settings.
    lazy var defaultInputMapping: GameControllerInputMappingProtocol? = ExternalGameControllerManager.shared.mfiDefaultInputMapping

    /// Set to true if pushing a stick up moves characters down.
    static let invertStickY = false

    private typealias Key = MFiGameController.Input
    private var active: [Key: Double] = [:]

    func process(_ data: Data)
    {
        guard data.count >= 17 else { return }
        let b = [UInt8](data)

        func has(_ index: Int, _ mask: UInt8) -> Bool { return b[index] & mask != 0 }
        func s16(_ index: Int) -> Int { return Int(Int16(bitPattern: UInt16(b[index]) | (UInt16(b[index + 1]) << 8))) }

        var want: [Key: Double] = [:]

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

        // Center buttons: Steam = Delta menu, Menu (three lines) = Start, View (two squares) = Select
        if has(3, 0x01) { want[.menu] = 1 }
        if has(1, 0x40) { want[.start] = 1 }
        if has(2, 0x40) { want[.select] = 1 }

        // Sticks
        let yFlip: Double = SteamGameController.invertStickY ? -1 : 1
        addAxis(&want, Double(s16(9)) / 32767, negative: .leftThumbstickLeft, positive: .leftThumbstickRight)
        addAxis(&want, yFlip * Double(s16(11)) / 32767, negative: .leftThumbstickDown, positive: .leftThumbstickUp)
        addAxis(&want, Double(s16(13)) / 32767, negative: .rightThumbstickLeft, positive: .rightThumbstickRight)
        addAxis(&want, yFlip * Double(s16(15)) / 32767, negative: .rightThumbstickDown, positive: .rightThumbstickUp)

        // Diff against what is currently pressed.
        for key in Set(want.keys).union(active.keys)
        {
            if let value = want[key]
            {
                if active[key] != value
                {
                    active[key] = value
                    activate(key, value: value)
                }
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
    }

    private func addAxis(_ want: inout [Key: Double], _ raw: Double, negative: Key, positive: Key)
    {
        let deadzone = 0.12
        let magnitude = abs(raw)
        guard magnitude > deadzone else { return }
        let scaled = min(1.0, (magnitude - deadzone) / (1.0 - deadzone))
        if raw < 0 { want[negative] = scaled } else { want[positive] = scaled }
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
        }

        controller?.process(value)
    }
}
