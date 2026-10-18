//
//  SteamGameController.swift
//  Delta
//
//  Created by Cameron Dennis on 10/17/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import DeltaCore
import DeltaFeatures
import MelonDSDeltaCore

// A Steam Controller (2026) connected over Bluetooth LE.
//
// iPadOS doesn't recognize the Steam Controller as a game controller, so SteamControllerManager
// subscribes to its state reports directly over CoreBluetooth and passes them to `process(_:)`.
// This class decodes each report and activates/deactivates the corresponding `SteamInput`s.
class SteamGameController: NSObject, GameController
{
    let name: String = NSLocalizedString("Steam Controller", comment: "")

    var playerIndex: Int?

    let inputType: GameControllerInputType = .steam

    lazy var defaultInputMapping: GameControllerInputMappingProtocol? = SteamGameController.makeDefaultInputMapping()

    // The inputs currently activated, and their values.
    private var activatedInputs = [SteamInput: Double]()

    // Per-trackpad state, indexed by `Trackpad.rawValue`.
    private var isTouchingTrackpad = [false, false]
    private var isPressingTrackpad = [false, false]
}

extension SteamGameController
{
    // Sticks report values within this distance from center as 0.
    private static let thumbstickDeadzone = 0.12

    // Fraction of the firm press threshold a press must drop below to stop touching the screen.
    // Prevents flickering when pressing right at the threshold.
    private static let firmPressHysteresis = 0.8

    fileprivate enum Trackpad: Int
    {
        case left
        case right

        var xInput: SteamInput {
            switch self
            {
            case .left: return .leftPadX
            case .right: return .rightPadX
            }
        }

        var yInput: SteamInput {
            switch self
            {
            case .left: return .leftPadY
            case .right: return .rightPadY
            }
        }
    }

    // A decoded trackpad sample.
    fileprivate struct TrackpadState
    {
        var isTouching: Bool

        // Raw signed 16-bit values. X increases to the right, Y increases upwards.
        var x: Int
        var y: Int

        // 0 (resting) ... 32767 (full click).
        var pressure: Int
    }
}

extension SteamGameController
{
    // Decodes a 45-byte state report from the controller's "100F6C7A" characteristic.
    //
    // Layout (little-endian):
    //  0      Sequence number
    //  1...4  Button bitmasks
    //  5...8  Left and right trigger (Int16 each, unused)
    //  9...16 Left stick X/Y, right stick X/Y (Int16 each)
    //  17...22 Left trackpad X, Y, pressure (Int16 each)
    //  23...28 Right trackpad X, Y, pressure (Int16 each)
    //  29...44 Timestamp and motion data (unused)
    func process(_ report: Data)
    {
        guard report.count >= 29 else { return }

        let bytes = [UInt8](report)

        func isPressed(_ byteIndex: Int, _ mask: UInt8) -> Bool
        {
            return bytes[byteIndex] & mask != 0
        }

        func int16(at byteIndex: Int) -> Int
        {
            let value = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
            return Int(Int16(bitPattern: value))
        }

        var inputs = [SteamInput: Double]()

        let buttons: [(byteIndex: Int, mask: UInt8, input: SteamInput)] = [
            (1, 0x01, .a), (1, 0x02, .b), (1, 0x04, .x), (1, 0x08, .y),
            (2, 0x20, .up), (2, 0x04, .down), (2, 0x10, .left), (2, 0x08, .right),
            (3, 0x08, .leftShoulder), (2, 0x02, .rightShoulder), (4, 0x08, .leftTrigger), (3, 0x80, .rightTrigger),
            (3, 0x01, .menu), (1, 0x40, .start), (2, 0x40, .select),
            (2, 0x80, .l3), (1, 0x20, .r3), (3, 0x02, .l4), (3, 0x04, .l5), (1, 0x80, .r4), (2, 0x01, .r5),
            (1, 0x10, .quickAccess)
        ]

        for button in buttons where isPressed(button.byteIndex, button.mask)
        {
            inputs[button.input] = 1
        }

        let leftTrackpad = TrackpadState(isTouching: isPressed(4, 0x02), x: int16(at: 17), y: int16(at: 19), pressure: int16(at: 21))
        let rightTrackpad = TrackpadState(isTouching: isPressed(3, 0x20), x: int16(at: 23), y: int16(at: 25), pressure: int16(at: 27))

        // A trackpad used as the DS touchscreen ignores its click and touch inputs.
        // Their mappings are kept, so they work again once the touchscreen is turned off.
        if !self.isMappedToTouchscreen(.left)
        {
            if isPressed(4, 0x04) { inputs[.leftPadClick] = 1 }
            if leftTrackpad.isTouching { inputs[.leftPadTouch] = 1 }
        }

        if !self.isMappedToTouchscreen(.right)
        {
            if isPressed(3, 0x40) { inputs[.rightPadClick] = 1 }
            if rightTrackpad.isTouching { inputs[.rightPadTouch] = 1 }
        }

        self.addThumbstickAxis(int16(at: 9), negative: .leftThumbstickLeft, positive: .leftThumbstickRight, to: &inputs)
        self.addThumbstickAxis(int16(at: 11), negative: .leftThumbstickDown, positive: .leftThumbstickUp, to: &inputs)
        self.addThumbstickAxis(int16(at: 13), negative: .rightThumbstickLeft, positive: .rightThumbstickRight, to: &inputs)
        self.addThumbstickAxis(int16(at: 15), negative: .rightThumbstickDown, positive: .rightThumbstickUp, to: &inputs)

        self.addTrackpad(.left, state: leftTrackpad, to: &inputs)
        self.addTrackpad(.right, state: rightTrackpad, to: &inputs)

        self.updateActivatedInputs(to: inputs)
    }

    // Deactivates every input, e.g. when the controller disconnects.
    func deactivateAllInputs()
    {
        for input in self.activatedInputs.keys
        {
            self.deactivate(input)
        }

        self.activatedInputs.removeAll()

        for trackpad in [Trackpad.left, .right]
        {
            self.isTouchingTrackpad[trackpad.rawValue] = false
            self.isPressingTrackpad[trackpad.rawValue] = false
            SteamControllerCursor.shared.release(from: trackpad.rawValue)
        }
    }
}

private extension SteamGameController
{
    static func makeDefaultInputMapping() -> GameControllerInputMappingProtocol
    {
        // Matches Delta's default MFi controller mapping. Extra inputs are left unmapped.
        let standardInputs: [SteamInput: StandardGameControllerInput] = [
            .a: .a, .b: .b, .x: .x, .y: .y,
            .up: .up, .down: .down, .left: .left, .right: .right,
            .leftShoulder: .l1, .leftTrigger: .l2, .rightShoulder: .r1, .rightTrigger: .r2,
            .start: .start, .select: .select, .menu: .menu,
            .leftThumbstickUp: .leftThumbstickUp, .leftThumbstickDown: .leftThumbstickDown,
            .leftThumbstickLeft: .leftThumbstickLeft, .leftThumbstickRight: .leftThumbstickRight,
            .rightThumbstickUp: .rightThumbstickUp, .rightThumbstickDown: .rightThumbstickDown,
            .rightThumbstickLeft: .rightThumbstickLeft, .rightThumbstickRight: .rightThumbstickRight
        ]

        // Qualified to avoid ambiguity with Delta's Core Data GameControllerInputMapping class.
        var inputMapping = DeltaCore.GameControllerInputMapping(gameControllerInputType: .steam)
        inputMapping.name = NSLocalizedString("Default Steam Controller", comment: "")

        for (steamInput, standardInput) in standardInputs
        {
            inputMapping.set(standardInput, forControllerInput: steamInput)
        }

        return inputMapping
    }

    func addThumbstickAxis(_ rawValue: Int, negative: SteamInput, positive: SteamInput, to inputs: inout [SteamInput: Double])
    {
        let value = Double(rawValue) / Double(Int16.max)

        let magnitude = abs(value)
        guard magnitude > SteamGameController.thumbstickDeadzone else { return }

        // Rescale so values start at 0 just outside the deadzone.
        let scaledMagnitude = min(1.0, (magnitude - SteamGameController.thumbstickDeadzone) / (1.0 - SteamGameController.thumbstickDeadzone))

        if value < 0
        {
            inputs[negative] = scaledMagnitude
        }
        else
        {
            inputs[positive] = scaledMagnitude
        }
    }

    // Adds the trackpad's position (when it should touch the screen) and updates the on-screen cursor.
    func addTrackpad(_ trackpad: Trackpad, state: TrackpadState, to inputs: inout [SteamInput: Double])
    {
        guard state.isTouching else {
            if self.isTouchingTrackpad[trackpad.rawValue]
            {
                self.isTouchingTrackpad[trackpad.rawValue] = false
                self.isPressingTrackpad[trackpad.rawValue] = false
                SteamControllerCursor.shared.release(from: trackpad.rawValue)
            }

            return
        }

        self.isTouchingTrackpad[trackpad.rawValue] = true

        let feature = ExperimentalFeatures.shared.steamController

        // Normalize to 0...1 with the origin in the top-left corner, like the DS touchscreen.
        let x = min(1.0, max(0.0, (Double(state.x) - Double(Int16.min)) / Double(UInt16.max)))
        var y = 1.0 - min(1.0, max(0.0, (Double(state.y) - Double(Int16.min)) / Double(UInt16.max)))

        if feature.matchesDSAspectRatio
        {
            // Use the middle 75% of the trackpad's height, so a 4:3 area maps to the 4:3 screen.
            y = min(1.0, max(0.0, (y - 0.125) / 0.75))
        }

        var isTouchingScreen = true

        if feature.requiresFirmPress
        {
            let pressure = Double(max(0, state.pressure)) / Double(Int16.max)
            let threshold = feature.firmPressThreshold

            if self.isPressingTrackpad[trackpad.rawValue]
            {
                isTouchingScreen = pressure >= threshold * SteamGameController.firmPressHysteresis
            }
            else
            {
                isTouchingScreen = pressure >= threshold
            }

            self.isPressingTrackpad[trackpad.rawValue] = isTouchingScreen
        }

        guard self.isMappedToTouchscreen(trackpad) else { return }

        // The cursor follows your finger, and uses its "pressed" colors while the screen is being touched.
        SteamControllerCursor.shared.show(atNormalizedX: x, y: y, from: trackpad.rawValue, isPressed: isTouchingScreen)

        if isTouchingScreen
        {
            inputs[trackpad.xInput] = x
            inputs[trackpad.yInput] = y
        }
    }

    // Whether the trackpad is mapped to the DS touchscreen for any receiver.
    func isMappedToTouchscreen(_ trackpad: Trackpad) -> Bool
    {
        let touchScreenX = MelonDSGameInput.touchScreenX.stringValue

        for receiver in self.receivers
        {
            if let inputMapping = self.inputMapping(for: receiver), inputMapping.input(forControllerInput: trackpad.xInput)?.stringValue == touchScreenX
            {
                return true
            }
        }

        return false
    }

    // Activates new or changed inputs, and deactivates inputs that are no longer active.
    func updateActivatedInputs(to inputs: [SteamInput: Double])
    {
        for input in Set(inputs.keys).union(self.activatedInputs.keys)
        {
            if let value = inputs[input]
            {
                // Ignore tiny changes to continuous inputs to avoid flooding the emulator with updates.
                if let previousValue = self.activatedInputs[input], abs(previousValue - value) < 0.002
                {
                    continue
                }

                self.activatedInputs[input] = value
                self.activate(input, value: value)
            }
            else if self.activatedInputs[input] != nil
            {
                self.activatedInputs[input] = nil
                self.deactivate(input)
            }
        }
    }
}
