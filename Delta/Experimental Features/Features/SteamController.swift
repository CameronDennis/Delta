//
//  SteamController.swift
//  Delta
//
//  Created by Cameron Dennis on 10/17/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import UIKit

import DeltaFeatures

// An RGBA color stored as a single string ("red,green,blue,alpha", each 0...1),
// so it can be persisted by @Option and read with @AppStorage.
struct SteamCursorColor: RawRepresentable, Equatable, OptionValue
{
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var rawValue: String {
        return [self.red, self.green, self.blue, self.alpha].map { String($0) }.joined(separator: ",")
    }

    var uiColor: UIColor {
        return UIColor(red: self.red, green: self.green, blue: self.blue, alpha: self.alpha)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double)
    {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(rawValue: String)
    {
        let components = rawValue.split(separator: ",").compactMap { Double($0) }
        guard components.count == 4 else { return nil }

        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}

extension SteamCursorColor
{
    // Shown while a touch is not (yet) being sent to the game.
    static let defaultFill = SteamCursorColor(red: 1, green: 1, blue: 1, alpha: 0.5)
    static let defaultOutline = SteamCursorColor(red: 0, green: 0, blue: 0, alpha: 0.8)

    // Shown while a touch is being sent to the game.
    static let defaultPressedFill = SteamCursorColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.7)
    static let defaultPressedOutline = SteamCursorColor(red: 0.5, green: 0, blue: 0, alpha: 0.9)
}

// All options are hidden from the Experimental Features screen. They are configured
// in the Steam Controller's controls editor instead (Settings > Controllers > Nintendo DS).
struct SteamControllerOptions
{
    static let defaultFirmPressThreshold = 0.15
    static let defaultCursorFadeDuration = 1.0
    static let defaultCursorSize = 26.0
    static let defaultCursorOutlineWidth = 2.0

    // MARK: Trackpad Touch

    // Only use a 4:3 region of the (roughly square) trackpad, so the DS screen isn't stretched.
    @Option
    var matchesDSAspectRatio: Bool = false

    // Only touch the screen once the trackpad is pressed at least `firmPressThreshold` hard.
    @Option
    var requiresFirmPress: Bool = false

    // 0...1, where 1 is a full click.
    @Option
    var firmPressThreshold: Double = SteamControllerOptions.defaultFirmPressThreshold

    // MARK: Cursor

    @Option
    var showsCursor: Bool = true

    @Option
    var showsAdvancedCursorSettings: Bool = false

    // Seconds the cursor takes to fade out after lifting your finger.
    @Option
    var cursorFadeDuration: Double = SteamControllerOptions.defaultCursorFadeDuration

    // Points.
    @Option
    var cursorSize: Double = SteamControllerOptions.defaultCursorSize

    // Points.
    @Option
    var cursorOutlineWidth: Double = SteamControllerOptions.defaultCursorOutlineWidth

    @Option
    var cursorFillColor: SteamCursorColor = .defaultFill

    @Option
    var cursorOutlineColor: SteamCursorColor = .defaultOutline

    @Option
    var cursorPressedFillColor: SteamCursorColor = .defaultPressedFill

    @Option
    var cursorPressedOutlineColor: SteamCursorColor = .defaultPressedOutline
}
