//
//  SteamTouchscreenSettingsView.swift
//  Delta
//
//  Created by Cameron Dennis on 10/17/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import SwiftUI

import DeltaFeatures

// Settings for using Steam Controller trackpads as the Nintendo DS touchscreen.
// Shown in the Steam Controller's controls editor once a trackpad is mapped to the touchscreen.
//
// Values are stored by SteamControllerOptions' @Options, and read here with @AppStorage using the same keys.
struct SteamTouchscreenSettingsView: View
{
    @AppStorage(ExperimentalFeatures.shared.steamController.$matchesDSAspectRatio.settingsKey.rawValue)
    private var matchesDSAspectRatio: Bool = false

    @AppStorage(ExperimentalFeatures.shared.steamController.$requiresFirmPress.settingsKey.rawValue)
    private var requiresFirmPress: Bool = false

    @AppStorage(ExperimentalFeatures.shared.steamController.$firmPressThreshold.settingsKey.rawValue)
    private var firmPressThreshold: Double = SteamControllerOptions.defaultFirmPressThreshold

    @AppStorage(ExperimentalFeatures.shared.steamController.$showsCursor.settingsKey.rawValue)
    private var showsCursor: Bool = true

    @AppStorage(ExperimentalFeatures.shared.steamController.$showsAdvancedCursorSettings.settingsKey.rawValue)
    private var showsAdvancedCursorSettings: Bool = false

    @AppStorage(ExperimentalFeatures.shared.steamController.$cursorFadeDuration.settingsKey.rawValue)
    private var cursorFadeDuration: Double = SteamControllerOptions.defaultCursorFadeDuration

    @AppStorage(ExperimentalFeatures.shared.steamController.$cursorSize.settingsKey.rawValue)
    private var cursorSize: Double = SteamControllerOptions.defaultCursorSize

    @AppStorage(ExperimentalFeatures.shared.steamController.$cursorOutlineWidth.settingsKey.rawValue)
    private var cursorOutlineWidth: Double = SteamControllerOptions.defaultCursorOutlineWidth

    @AppStorage(ExperimentalFeatures.shared.steamController.$cursorFillColor.settingsKey.rawValue)
    private var cursorFillColor: SteamCursorColor = .defaultFill

    @AppStorage(ExperimentalFeatures.shared.steamController.$cursorOutlineColor.settingsKey.rawValue)
    private var cursorOutlineColor: SteamCursorColor = .defaultOutline

    @AppStorage(ExperimentalFeatures.shared.steamController.$cursorPressedFillColor.settingsKey.rawValue)
    private var cursorPressedFillColor: SteamCursorColor = .defaultPressedFill

    @AppStorage(ExperimentalFeatures.shared.steamController.$cursorPressedOutlineColor.settingsKey.rawValue)
    private var cursorPressedOutlineColor: SteamCursorColor = .defaultPressedOutline

    var body: some View {
        Section {
            Toggle("Match DS Aspect Ratio (4:3)", isOn: $matchesDSAspectRatio)

            Toggle("Require Firm Press to Touch", isOn: $requiresFirmPress)

            if requiresFirmPress
            {
                SteamSliderField(title: String(localized: "Press Strength"), value: $firmPressThreshold, sliderRange: 0...1, typedRange: 0...1, step: 0.01, displayScale: 100, unit: "%", fractionDigits: 0)
            }
        } header: {
            Text("Trackpad Touch")
        } footer: {
            Text("4:3 uses a DS-shaped area of the trackpad so the screen isn't stretched. With a firm press required, the cursor still follows your finger, but the screen is only touched once you press at least this hard. A full click is 100%.")
        }

        Section {
            Toggle("Show Cursor", isOn: $showsCursor)

            if showsCursor
            {
                Toggle("Advanced Cursor Settings", isOn: $showsAdvancedCursorSettings)

                if showsAdvancedCursorSettings
                {
                    advancedCursorSettings
                }
            }
        } header: {
            Text("Cursor")
        } footer: {
            Text("The cursor appears on the bottom screen where your finger is on the trackpad. When a firm press is required, the cursor uses its normal colors until you press hard enough, then switches to its pressed colors. Otherwise it always uses its pressed colors, since every touch is sent to the game.")
        }
    }

    @ViewBuilder
    private var advancedCursorSettings: some View {
        SteamSliderField(title: String(localized: "Fade Out Time"), value: $cursorFadeDuration, sliderRange: 0...3, typedRange: 0...30, step: 0.05, displayScale: 1, unit: "s", fractionDigits: 2)
        SteamSliderField(title: String(localized: "Size"), value: $cursorSize, sliderRange: 8...80, typedRange: 2...300, step: 1, displayScale: 1, unit: "pt", fractionDigits: 0)
        SteamSliderField(title: String(localized: "Outline Width"), value: $cursorOutlineWidth, sliderRange: 0...8, typedRange: 0...40, step: 0.5, displayScale: 1, unit: "pt", fractionDigits: 1)

        if requiresFirmPress
        {
            ColorPicker("Fill Color", selection: Binding(steamCursorColor: $cursorFillColor), supportsOpacity: true)
            ColorPicker("Outline Color", selection: Binding(steamCursorColor: $cursorOutlineColor), supportsOpacity: true)
            ColorPicker("Pressed Fill Color", selection: Binding(steamCursorColor: $cursorPressedFillColor), supportsOpacity: true)
            ColorPicker("Pressed Outline Color", selection: Binding(steamCursorColor: $cursorPressedOutlineColor), supportsOpacity: true)
        }
        else
        {
            // Every touch is sent to the game, so only the pressed colors are ever shown.
            ColorPicker("Fill Color", selection: Binding(steamCursorColor: $cursorPressedFillColor), supportsOpacity: true)
            ColorPicker("Outline Color", selection: Binding(steamCursorColor: $cursorPressedOutlineColor), supportsOpacity: true)
        }

        cursorPreview

        Button("Reset Cursor to Defaults", role: .destructive) {
            resetCursorSettings()
        }
    }

    private var cursorPreview: some View {
        HStack {
            Text("Preview")

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: requiresFirmPress ? 170 : 110, height: 70)

                HStack(spacing: 24) {
                    if requiresFirmPress
                    {
                        previewCursor(fillColor: cursorFillColor, outlineColor: cursorOutlineColor)
                    }

                    previewCursor(fillColor: cursorPressedFillColor, outlineColor: cursorPressedOutlineColor)
                }
            }
        }
    }

    private func previewCursor(fillColor: SteamCursorColor, outlineColor: SteamCursorColor) -> some View
    {
        // Limit size so large cursors still fit in the row.
        let size = min(cursorSize, 60)

        return Circle()
            .fill(Color(uiColor: fillColor.uiColor))
            .overlay(Circle().inset(by: cursorOutlineWidth / 2).stroke(Color(uiColor: outlineColor.uiColor), lineWidth: cursorOutlineWidth))
            .frame(width: size, height: size)
    }

    // Resets cursor appearance and timing (but not whether it's shown).
    private func resetCursorSettings()
    {
        cursorFadeDuration = SteamControllerOptions.defaultCursorFadeDuration
        cursorSize = SteamControllerOptions.defaultCursorSize
        cursorOutlineWidth = SteamControllerOptions.defaultCursorOutlineWidth

        cursorFillColor = .defaultFill
        cursorOutlineColor = .defaultOutline
        cursorPressedFillColor = .defaultPressedFill
        cursorPressedOutlineColor = .defaultPressedOutline
    }
}

private extension Binding where Value == Color
{
    // Converts between a SteamCursorColor binding and the Color binding ColorPicker expects.
    init(steamCursorColor: Binding<SteamCursorColor>)
    {
        self.init(get: {
            Color(uiColor: steamCursorColor.wrappedValue.uiColor)
        }, set: { newColor in
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            UIColor(newColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            steamCursorColor.wrappedValue = SteamCursorColor(red: red, green: green, blue: blue, alpha: alpha)
        })
    }
}

// A slider with a text field for typing an exact value, which may go beyond the slider's range.
private struct SteamSliderField: View
{
    let title: String
    @Binding var value: Double

    let sliderRange: ClosedRange<Double>
    let typedRange: ClosedRange<Double>
    let step: Double

    // Multiplier applied to `value` for display (e.g. 100 to show 0...1 as a percentage).
    let displayScale: Double
    let unit: String
    let fractionDigits: Int

    @SwiftUI.State
    private var text = ""

    @FocusState
    private var isFocused: Bool

    private var sliderValue: Binding<Double> {
        Binding(get: {
            min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
        }, set: { newValue in
            value = newValue
        })
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
            text = formattedValue
        }
        .onChange(of: value) { _, _ in
            guard !isFocused else { return }
            text = formattedValue
        }
        .onChange(of: text) { _, newText in
            // Accept either decimal separator.
            guard isFocused, let typedValue = Double(newText.replacingOccurrences(of: ",", with: ".")) else { return }
            value = min(max(typedValue / displayScale, typedRange.lowerBound), typedRange.upperBound)
        }
        .onChange(of: isFocused) { _, newValue in
            guard !newValue else { return }
            text = formattedValue
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isFocused
                {
                    Spacer()

                    Button("Done") {
                        isFocused = false
                    }
                }
            }
        }
    }

    private var formattedValue: String {
        return String(format: "%.\(fractionDigits)f", value * displayScale)
    }
}
