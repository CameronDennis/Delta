//
//  SteamInput.swift
//  Delta
//
//  Created by Cameron Dennis on 10/17/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import DeltaCore

extension GameControllerInputType
{
    static let steam = GameControllerInputType("steam")
}

// The inputs of a Steam Controller (2026). Defined as a struct with static members (rather than an enum)
// so that unknown values decoded from saved input mappings don't fail to load.
struct SteamInput: Hashable, RawRepresentable, Codable
{
    let rawValue: String

    init(rawValue: String)
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
        return SteamInput.continuousInputs.contains(self)
    }

    init(stringValue: String)
    {
        self.init(rawValue: stringValue)
    }
}

extension SteamInput
{
    // Buttons that share names with MFi controller inputs, so they get the same default mappings.
    static let a = SteamInput(rawValue: "a")
    static let b = SteamInput(rawValue: "b")
    static let x = SteamInput(rawValue: "x")
    static let y = SteamInput(rawValue: "y")
    static let up = SteamInput(rawValue: "up")
    static let down = SteamInput(rawValue: "down")
    static let left = SteamInput(rawValue: "left")
    static let right = SteamInput(rawValue: "right")
    static let leftShoulder = SteamInput(rawValue: "leftShoulder")
    static let leftTrigger = SteamInput(rawValue: "leftTrigger")
    static let rightShoulder = SteamInput(rawValue: "rightShoulder")
    static let rightTrigger = SteamInput(rawValue: "rightTrigger")
    static let start = SteamInput(rawValue: "start") // "Menu" (three lines) button
    static let select = SteamInput(rawValue: "select") // "View" (two squares) button
    static let menu = SteamInput(rawValue: "menu") // Steam button

    static let leftThumbstickUp = SteamInput(rawValue: "leftThumbstickUp")
    static let leftThumbstickDown = SteamInput(rawValue: "leftThumbstickDown")
    static let leftThumbstickLeft = SteamInput(rawValue: "leftThumbstickLeft")
    static let leftThumbstickRight = SteamInput(rawValue: "leftThumbstickRight")
    static let rightThumbstickUp = SteamInput(rawValue: "rightThumbstickUp")
    static let rightThumbstickDown = SteamInput(rawValue: "rightThumbstickDown")
    static let rightThumbstickLeft = SteamInput(rawValue: "rightThumbstickLeft")
    static let rightThumbstickRight = SteamInput(rawValue: "rightThumbstickRight")

    // Extra inputs. These have no default mapping.
    static let l3 = SteamInput(rawValue: "l3")
    static let r3 = SteamInput(rawValue: "r3")
    static let l4 = SteamInput(rawValue: "l4")
    static let l5 = SteamInput(rawValue: "l5")
    static let r4 = SteamInput(rawValue: "r4")
    static let r5 = SteamInput(rawValue: "r5")
    static let leftPadClick = SteamInput(rawValue: "leftPadClick")
    static let rightPadClick = SteamInput(rawValue: "rightPadClick")
    static let leftPadTouch = SteamInput(rawValue: "leftPadTouch")
    static let rightPadTouch = SteamInput(rawValue: "rightPadTouch")
    static let quickAccess = SteamInput(rawValue: "quickAccess")

    // Absolute trackpad positions (0...1, origin top-left). Mapped to the DS touchscreen.
    static let leftPadX = SteamInput(rawValue: "leftPadX")
    static let leftPadY = SteamInput(rawValue: "leftPadY")
    static let rightPadX = SteamInput(rawValue: "rightPadX")
    static let rightPadY = SteamInput(rawValue: "rightPadY")

    static let buttons: [SteamInput] = [.a, .b, .x, .y, .up, .down, .left, .right, .leftShoulder, .leftTrigger, .rightShoulder, .rightTrigger, .start, .select, .menu]
    static let leftThumbstick: [SteamInput] = [.leftThumbstickUp, .leftThumbstickDown, .leftThumbstickLeft, .leftThumbstickRight]
    static let rightThumbstick: [SteamInput] = [.rightThumbstickUp, .rightThumbstickDown, .rightThumbstickLeft, .rightThumbstickRight]
    static let extras: [SteamInput] = [.l3, .r3, .l4, .l5, .r4, .r5, .leftPadClick, .rightPadClick, .leftPadTouch, .rightPadTouch, .quickAccess]

    private static let continuousInputs: Set<SteamInput> = Set(SteamInput.leftThumbstick + SteamInput.rightThumbstick + [.leftPadX, .leftPadY, .rightPadX, .rightPadY])
}

extension SteamInput
{
    var localizedName: String {
        switch self
        {
        case .a: return NSLocalizedString("A Button", comment: "")
        case .b: return NSLocalizedString("B Button", comment: "")
        case .x: return NSLocalizedString("X Button", comment: "")
        case .y: return NSLocalizedString("Y Button", comment: "")
        case .up: return NSLocalizedString("D-Pad Up", comment: "")
        case .down: return NSLocalizedString("D-Pad Down", comment: "")
        case .left: return NSLocalizedString("D-Pad Left", comment: "")
        case .right: return NSLocalizedString("D-Pad Right", comment: "")
        case .leftShoulder: return NSLocalizedString("L1", comment: "")
        case .leftTrigger: return NSLocalizedString("L2", comment: "")
        case .rightShoulder: return NSLocalizedString("R1", comment: "")
        case .rightTrigger: return NSLocalizedString("R2", comment: "")
        case .start: return NSLocalizedString("Menu", comment: "")
        case .select: return NSLocalizedString("View", comment: "")
        case .menu: return NSLocalizedString("Steam", comment: "")
        case .leftThumbstickUp: return NSLocalizedString("Left Stick Up", comment: "")
        case .leftThumbstickDown: return NSLocalizedString("Left Stick Down", comment: "")
        case .leftThumbstickLeft: return NSLocalizedString("Left Stick Left", comment: "")
        case .leftThumbstickRight: return NSLocalizedString("Left Stick Right", comment: "")
        case .rightThumbstickUp: return NSLocalizedString("Right Stick Up", comment: "")
        case .rightThumbstickDown: return NSLocalizedString("Right Stick Down", comment: "")
        case .rightThumbstickLeft: return NSLocalizedString("Right Stick Left", comment: "")
        case .rightThumbstickRight: return NSLocalizedString("Right Stick Right", comment: "")
        case .l3: return NSLocalizedString("L3 (Left Stick Click)", comment: "")
        case .r3: return NSLocalizedString("R3 (Right Stick Click)", comment: "")
        case .l4: return NSLocalizedString("L4", comment: "")
        case .l5: return NSLocalizedString("L5", comment: "")
        case .r4: return NSLocalizedString("R4", comment: "")
        case .r5: return NSLocalizedString("R5", comment: "")
        case .leftPadClick: return NSLocalizedString("Left Pad Click", comment: "")
        case .rightPadClick: return NSLocalizedString("Right Pad Click", comment: "")
        case .leftPadTouch: return NSLocalizedString("Left Pad Touch", comment: "")
        case .rightPadTouch: return NSLocalizedString("Right Pad Touch", comment: "")
        case .quickAccess: return NSLocalizedString("Quick Access", comment: "")
        case .leftPadX: return NSLocalizedString("Left Pad X", comment: "")
        case .leftPadY: return NSLocalizedString("Left Pad Y", comment: "")
        case .rightPadX: return NSLocalizedString("Right Pad X", comment: "")
        case .rightPadY: return NSLocalizedString("Right Pad Y", comment: "")
        default: return self.rawValue
        }
    }

    // Shorter names, matching the style Delta uses for MFi controller inputs.
    var localizedShortName: String {
        switch self
        {
        case .up: return NSLocalizedString("Up", comment: "")
        case .down: return NSLocalizedString("Down", comment: "")
        case .left: return NSLocalizedString("Left", comment: "")
        case .right: return NSLocalizedString("Right", comment: "")
        case .a, .b, .x, .y: return self.rawValue.uppercased()
        case .leftThumbstickUp: return "L🕹↑"
        case .leftThumbstickDown: return "L🕹↓"
        case .leftThumbstickLeft: return "L🕹←"
        case .leftThumbstickRight: return "L🕹→"
        case .rightThumbstickUp: return "R🕹↑"
        case .rightThumbstickDown: return "R🕹↓"
        case .rightThumbstickLeft: return "R🕹←"
        case .rightThumbstickRight: return "R🕹→"
        default: return self.localizedName
        }
    }

    var symbolName: String {
        switch self
        {
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .up: return "dpad.up.filled"
        case .down: return "dpad.down.filled"
        case .left: return "dpad.left.filled"
        case .right: return "dpad.right.filled"
        case .leftShoulder: return "l1.button.roundedtop.horizontal"
        case .leftTrigger: return "l2.button.roundedtop.horizontal"
        case .rightShoulder: return "r1.button.roundedtop.horizontal"
        case .rightTrigger: return "r2.button.roundedtop.horizontal"
        case .start: return "line.3.horizontal.circle"
        case .select: return "rectangle.on.rectangle.circle"
        case .menu: return "gamecontroller"
        case .l3: return "l.joystick.press.down"
        case .r3: return "r.joystick.press.down"
        case .l4, .l5, .r4, .r5: return "circle.fill"
        case .leftPadClick, .rightPadClick, .leftPadTouch, .rightPadTouch, .leftPadX, .leftPadY, .rightPadX, .rightPadY: return "hand.point.up.left"
        case .quickAccess: return "ellipsis.circle"
        case _ where SteamInput.leftThumbstick.contains(self): return "l.joystick"
        case _ where SteamInput.rightThumbstick.contains(self): return "r.joystick"
        default: return "gamecontroller"
        }
    }
}
