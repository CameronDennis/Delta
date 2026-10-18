//
//  SteamControllerManager.swift
//  Delta
//
//  Created by Cameron Dennis on 10/17/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import CoreBluetooth
import OSLog
import GameController

import DeltaCore
import DeltaFeatures

// Connects to a Steam Controller (2026) over Bluetooth LE and registers it with ExternalGameControllerManager.
//
// The controller must first be paired in iPadOS' Settings app. Once paired, iPadOS treats it as a
// keyboard and mouse ("lizard mode"), but not as a game controller. While connected, this class:
//  - subscribes to the controller's state reports and forwards them to SteamGameController
//  - turns off lizard mode, so buttons and trackpads don't also send keyboard and mouse events
//  - gives the controller's keyboard player slot to the Steam Controller
//
// Only active while the "Steam Controller" Experimental Feature is enabled.
class SteamControllerManager: NSObject
{
    static let shared = SteamControllerManager()

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var featureReportCharacteristic: CBCharacteristic?

    private var gameController: SteamGameController?

    private var lizardModeTimer: Timer?

    private override init()
    {
        super.init()
    }
}

private extension SteamControllerManager
{
    // Valve's custom GATT service, shared by Steam Controllers.
    static let serviceUUID = CBUUID(string: "100F6C32-1735-4313-B402-38567131E5F3")

    // Notifies with 45-byte state reports (report ID 0x45) on the 2026 Steam Controller.
    static let stateReportCharacteristicUUID = CBUUID(string: "100F6C7A-1735-4313-B402-38567131E5F3")

    // Accepts feature reports (without the leading report ID byte).
    static let featureReportCharacteristicUUID = CBUUID(string: "100F6C34-1735-4313-B402-38567131E5F3")

    // The controller turns lizard mode back on if it hasn't heard from the host for a few seconds
    // (so it keeps working as a keyboard and mouse if Delta quits), so the command is resent periodically.
    static let lizardModeRefreshInterval: TimeInterval = 3.0

    // Feature report that sets SETTING_LIZARD_MODE (9) to LIZARD_MODE_OFF (0).
    // Format: [ID_SET_SETTINGS_VALUES (0x87), payload length, setting, value (UInt16, little-endian)], zero-padded to 64 bytes.
    static let disableLizardModeReport: Data = {
        var bytes: [UInt8] = [0x87, 0x03, 0x09, 0x00, 0x00]
        bytes += [UInt8](repeating: 0, count: 64 - bytes.count)
        return Data(bytes)
    }()
}

extension SteamControllerManager
{
    // Call once at launch. Connects to the controller whenever the Experimental Feature is enabled.
    func start()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(SteamControllerManager.settingsDidChange(_:)), name: Settings.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SteamControllerManager.externalGameControllerDidConnect(_:)), name: .externalGameControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SteamControllerManager.mouseDidConnect(_:)), name: .GCMouseDidConnect, object: nil)

        self.update()
    }
}

private extension SteamControllerManager
{
    func update()
    {
        if ExperimentalFeatures.shared.steamController.isEnabled
        {
            self.connect()
        }
        else
        {
            self.disconnect()
        }
    }

    func connect()
    {
        guard let centralManager = self.centralManager else {
            // Creating CBCentralManager asks for Bluetooth permission (if not yet granted), so only create it once the feature is enabled.
            // Scanning starts once it's powered on (see centralManagerDidUpdateState()).
            self.centralManager = CBCentralManager(delegate: self, queue: .main)
            return
        }

        guard centralManager.state == .poweredOn, self.peripheral == nil else { return }

        if let peripheral = centralManager.retrieveConnectedPeripherals(withServices: [SteamControllerManager.serviceUUID]).first
        {
            // The controller is paired and already connected to iPadOS.
            self.connect(to: peripheral)
        }
        else
        {
            // Wait for the controller to turn on. It doesn't advertise the service UUID, so match by name instead.
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func connect(to peripheral: CBPeripheral)
    {
        self.centralManager?.stopScan()

        self.peripheral = peripheral
        peripheral.delegate = self

        self.centralManager?.connect(peripheral, options: nil)
    }

    func disconnect()
    {
        guard let centralManager = self.centralManager else { return }

        centralManager.stopScan()

        if let peripheral = self.peripheral
        {
            // The controller turns lizard mode back on by itself once we stop sending the command.
            centralManager.cancelPeripheralConnection(peripheral)
        }

        self.reset()
    }

    // Forgets the current controller, and unregisters it from ExternalGameControllerManager.
    func reset()
    {
        self.lizardModeTimer?.invalidate()
        self.lizardModeTimer = nil

        if let gameController = self.gameController
        {
            gameController.deactivateAllInputs()
            ExternalGameControllerManager.shared.remove(gameController)

            self.gameController = nil
        }

        self.peripheral = nil
        self.featureReportCharacteristic = nil
    }

    func reconnect(after delay: TimeInterval)
    {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard ExperimentalFeatures.shared.steamController.isEnabled else { return }
            self.connect()
        }
    }

    func isSteamController(named name: String) -> Bool
    {
        let lowercasedName = name.lowercased()
        return lowercasedName.contains("steam") || lowercasedName.contains("triton")
    }
}

private extension SteamControllerManager
{
    @objc func disableLizardMode()
    {
        guard let peripheral = self.peripheral, let characteristic = self.featureReportCharacteristic else { return }
        peripheral.writeValue(SteamControllerManager.disableLizardModeReport, for: characteristic, type: .withResponse)
    }

    func startDisablingLizardMode()
    {
        self.disableLizardMode()

        self.lizardModeTimer?.invalidate()
        self.lizardModeTimer = Timer.scheduledTimer(timeInterval: SteamControllerManager.lizardModeRefreshInterval, target: self, selector: #selector(SteamControllerManager.disableLizardMode), userInfo: nil, repeats: true)
    }
}

private extension SteamControllerManager
{
    // While paired, iPadOS also lists the Steam Controller as a keyboard and a mouse. Keyboards can't be told apart
    // (they're all coalesced into one), but its mouse is named after the controller (e.g. "Steam Ctrl (BT) …").
    var isSteamControllerKeyboardConnected: Bool {
        let isSteamControllerMouseConnected = GCMouse.mice().contains { mouse in
            guard let vendorName = mouse.vendorName else { return false }
            return self.isSteamController(named: vendorName)
        }

        return isSteamControllerMouseConnected && ExternalGameControllerManager.shared.isKeyboardConnected
    }

    // If the keyboard has a player slot, give it to the Steam Controller instead, since the keyboard is (most likely) the
    // Steam Controller itself. Players can still re-assign the keyboard in Settings.
    func takePlayerIndexFromSteamControllerKeyboard()
    {
        guard let gameController = self.gameController, self.isSteamControllerKeyboardConnected else { return }

        for case let keyboardController as KeyboardGameController in ExternalGameControllerManager.shared.connectedControllers
        {
            guard let keyboardPlayerIndex = keyboardController.playerIndex else { continue }

            keyboardController.playerIndex = nil

            if let playerIndex = gameController.playerIndex, playerIndex < keyboardPlayerIndex
            {
                // Steam Controller already has an earlier player slot.
                continue
            }

            gameController.playerIndex = keyboardPlayerIndex
        }
    }

    @objc func settingsDidChange(_ notification: Notification)
    {
        guard let settingsName = notification.userInfo?[Settings.NotificationUserInfoKey.name] as? Settings.Name,
              settingsName == ExperimentalFeatures.shared.steamController.settingsKey
        else { return }

        DispatchQueue.main.async {
            self.update()
        }
    }

    @objc func externalGameControllerDidConnect(_ notification: Notification)
    {
        guard notification.object is KeyboardGameController else { return }

        DispatchQueue.main.async {
            // Keyboard (re)connected while the Steam Controller is in use.
            self.takePlayerIndexFromSteamControllerKeyboard()
        }
    }

    @objc func mouseDidConnect(_ notification: Notification)
    {
        DispatchQueue.main.async {
            // Steam Controller's mouse may connect after the Steam Controller itself.
            self.takePlayerIndexFromSteamControllerKeyboard()
        }
    }
}

extension SteamControllerManager: CBCentralManagerDelegate
{
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    {
        guard central.state == .poweredOn else { return }
        guard ExperimentalFeatures.shared.steamController.isEnabled else { return }

        self.connect()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    {
        guard self.peripheral == nil else { return }

        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard self.isSteamController(named: name) else { return }

        self.connect(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        peripheral.discoverServices([SteamControllerManager.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    {
        Logger.main.error("Failed to connect to Steam Controller. \(error?.localizedDescription ?? "", privacy: .public)")

        self.reset()
        self.reconnect(after: 2.0)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        self.reset()
        self.reconnect(after: 1.0)
    }
}

extension SteamControllerManager: CBPeripheralDelegate
{
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        for service in peripheral.services ?? [] where service.uuid == SteamControllerManager.serviceUUID
        {
            peripheral.discoverCharacteristics([SteamControllerManager.stateReportCharacteristicUUID, SteamControllerManager.featureReportCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        for characteristic in service.characteristics ?? []
        {
            switch characteristic.uuid
            {
            case SteamControllerManager.stateReportCharacteristicUUID:
                peripheral.setNotifyValue(true, for: characteristic)

            case SteamControllerManager.featureReportCharacteristicUUID:
                self.featureReportCharacteristic = characteristic
                self.startDisablingLizardMode()

            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        guard error == nil, characteristic.uuid == SteamControllerManager.stateReportCharacteristicUUID, let report = characteristic.value else { return }

        if self.gameController == nil
        {
            // Register the controller once it starts sending reports.
            let gameController = SteamGameController()
            self.gameController = gameController

            ExternalGameControllerManager.shared.add(gameController)
            self.takePlayerIndexFromSteamControllerKeyboard()
        }

        self.gameController?.process(report)
    }
}
