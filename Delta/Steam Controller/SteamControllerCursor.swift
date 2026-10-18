//
//  SteamControllerCursor.swift
//  Delta
//
//  Created by Cameron Dennis on 10/17/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import UIKit
import CoreImage

import DeltaCore
import DeltaFeatures

// A window that never handles touches, so the cursor never blocks the game or its controller skin.
private class SteamControllerCursorWindow: UIWindow
{
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        return nil
    }
}

// Shows where a Steam Controller trackpad touches the Nintendo DS bottom screen.
//
// The cursor appears when a finger touches a trackpad mapped to the touchscreen, and fades out when it's lifted.
// It uses its "pressed" colors while the touch is being sent to the game (which may require a firm press).
class SteamControllerCursor
{
    static let shared = SteamControllerCursor()

    private var window: SteamControllerCursorWindow?
    private let cursorView = UIView()

    // Identifies the trackpad currently moving the cursor.
    private var source: Int?
    private var isVisible = false

    private init()
    {
    }
}

extension SteamControllerCursor
{
    /// Shows (or moves) the cursor to a normalized position (0...1, origin top-left) on the DS bottom screen.
    ///
    /// - Parameters:
    ///   - x: Horizontal position, from 0 (left edge) to 1 (right edge).
    ///   - y: Vertical position, from 0 (top edge) to 1 (bottom edge).
    ///   - source: Identifies the trackpad, so lifting one trackpad doesn't hide a cursor moved by the other.
    ///   - isPressed: Whether the touch is being sent to the game.
    func show(atNormalizedX x: Double, y: Double, from source: Int, isPressed: Bool)
    {
        let feature = ExperimentalFeatures.shared.steamController

        guard feature.showsCursor else {
            self.hide()
            return
        }

        // Only show the cursor while the game is running in the foreground and can receive touches.
        guard let window = self.makeWindowIfNeeded(), let screenFrame = self.bottomScreenFrame(in: window) else {
            self.hide()
            return
        }

        self.source = source
        self.cursorView.layer.removeAllAnimations()

        let size = max(2.0, feature.cursorSize)
        self.cursorView.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        self.cursorView.layer.cornerRadius = size / 2
        self.cursorView.layer.borderWidth = max(0.0, feature.cursorOutlineWidth)

        if isPressed
        {
            self.cursorView.backgroundColor = feature.cursorPressedFillColor.uiColor
            self.cursorView.layer.borderColor = feature.cursorPressedOutlineColor.uiColor.cgColor
        }
        else
        {
            self.cursorView.backgroundColor = feature.cursorFillColor.uiColor
            self.cursorView.layer.borderColor = feature.cursorOutlineColor.uiColor.cgColor
        }

        self.cursorView.center = CGPoint(x: screenFrame.minX + x * screenFrame.width, y: screenFrame.minY + y * screenFrame.height)

        if self.isVisible
        {
            self.cursorView.alpha = 1
        }
        else
        {
            // Quickly fade in.
            self.isVisible = true
            self.cursorView.alpha = 0
            window.isHidden = false

            UIView.animate(withDuration: 0.08) {
                self.cursorView.alpha = 1
            }
        }
    }

    /// Fades out the cursor after a finger is lifted from the trackpad identified by `source`.
    /// Does nothing if the other trackpad has since moved the cursor.
    func release(from source: Int)
    {
        guard self.source == source else { return }
        self.source = nil

        let fadeDuration = ExperimentalFeatures.shared.steamController.cursorFadeDuration
        guard fadeDuration > 0 else {
            self.hide()
            return
        }

        UIView.animate(withDuration: fadeDuration, delay: 0, options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction], animations: {
            self.cursorView.alpha = 0
        }, completion: { finished in
            guard finished else { return }
            self.hide()
        })
    }
}

private extension SteamControllerCursor
{
    func hide()
    {
        self.cursorView.layer.removeAllAnimations()
        self.cursorView.alpha = 0

        self.window?.isHidden = true

        self.isVisible = false
        self.source = nil
    }

    func makeWindowIfNeeded() -> SteamControllerCursorWindow?
    {
        if let window = self.window
        {
            return window
        }

        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = windowScenes.first(where: { $0.activationState == .foregroundActive }) ?? windowScenes.first else { return nil }

        let rootViewController = UIViewController()
        rootViewController.view.backgroundColor = .clear
        rootViewController.view.isUserInteractionEnabled = false
        rootViewController.view.addSubview(self.cursorView)

        self.cursorView.isUserInteractionEnabled = false
        self.cursorView.alpha = 0

        // Above the game, its controller skin, and alerts.
        let window = SteamControllerCursorWindow(windowScene: windowScene)
        window.windowLevel = .alert + 2
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.rootViewController = rootViewController
        window.isHidden = true
        self.window = window

        return window
    }
}

private extension SteamControllerCursor
{
    /// Finds the DS bottom screen in `cursorWindow`'s coordinate space.
    ///
    /// Each DS screen is drawn by its own GameView, which crops its screen out of the combined 256x384 DS frame
    /// (see GameView.update(for:) in DeltaCore). The bottom screen is the GameView whose crop starts lowest, so this
    /// works for any controller skin layout: stacked, side-by-side, or reversed.
    func bottomScreenFrame(in cursorWindow: UIWindow) -> CGRect?
    {
        guard UIApplication.shared.applicationState == .active,
              let windowScene = cursorWindow.windowScene, windowScene.activationState == .foregroundActive
        else { return nil }

        var gameViews = [GameView]()
        for window in windowScene.windows where window !== cursorWindow
        {
            self.collectVisibleGameViews(in: window, into: &gameViews)
        }

        var screens = [(frame: CGRect, cropRect: CGRect?)]()
        for gameView in gameViews
        {
            guard let window = gameView.window, gameView.bounds.width > 10, gameView.bounds.height > 10 else { continue }
            guard self.isEmulationRunning(for: gameView) else { continue }

            let frameInWindow = window.convert(gameView.bounds, from: gameView)
            let frame = cursorWindow.convert(frameInWindow, from: window)
            screens.append((frame, self.cropRect(for: gameView)))
        }

        // Usually, every DS screen is cropped from the combined frame. The bottom screen's crop starts at y = 192.
        let croppedScreens = screens.filter { $0.cropRect != nil }
        if let bottomScreen = croppedScreens.max(by: { $0.cropRect!.minY < $1.cropRect!.minY }),
           croppedScreens.count >= 2 || bottomScreen.cropRect!.minY > 100
        {
            return bottomScreen.frame
        }

        // A single uncropped GameView showing both screens stacked (2:3 aspect ratio): use its lower half.
        if let stackedScreens = screens.first(where: { $0.cropRect == nil && abs($0.frame.width / $0.frame.height - 2.0 / 3.0) < 0.08 })
        {
            let frame = stackedScreens.frame
            return CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: frame.height / 2)
        }

        return nil
    }

    func collectVisibleGameViews(in view: UIView, into gameViews: inout [GameView])
    {
        if let gameView = view as? GameView, !gameView.isHidden, gameView.alpha > 0
        {
            gameViews.append(gameView)
        }

        for subview in view.subviews
        {
            self.collectVisibleGameViews(in: subview, into: &gameViews)
        }
    }

    // False while the pause menu (or anything else) has paused emulation, since touches can't reach the game.
    func isEmulationRunning(for gameView: GameView) -> Bool
    {
        var responder: UIResponder? = gameView
        while let currentResponder = responder
        {
            if let gameViewController = currentResponder as? DeltaCore.GameViewController
            {
                return gameViewController.emulatorCore?.state == .running
            }

            responder = currentResponder.next
        }

        return true
    }

    // The rectangle (in DS frame coordinates, origin top-left) that `gameView` crops out of the full DS frame, if any.
    func cropRect(for gameView: GameView) -> CGRect?
    {
        let filters: [CIFilter]

        if let filterChain = gameView.filter as? FilterChain
        {
            filters = filterChain.inputFilters
        }
        else if let filter = gameView.filter
        {
            filters = [filter]
        }
        else
        {
            filters = []
        }

        for filter in filters where filter.name == "CICrop"
        {
            if let rectangle = filter.value(forKey: "inputRectangle") as? CIVector
            {
                return rectangle.cgRectValue
            }
        }

        return nil
    }
}
