//
//  SteamControllerCursor.swift
//  Delta
//
//  Created by Cameron Dennis on 10/17/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import UIKit

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
        guard let window = self.makeWindowIfNeeded(), let screenFrame = self.touchScreenFrame(in: window) else {
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
    /// Finds the DS touch screen (the bottom screen) in `cursorWindow`'s coordinate space.
    ///
    /// Like `GameViewController.updateGameViews()`, this pairs the controller skin's screens with the game views that
    /// display them, then picks the screen the skin marks as the touch screen. This works for any controller skin layout.
    func touchScreenFrame(in cursorWindow: UIWindow) -> CGRect?
    {
        guard UIApplication.shared.applicationState == .active,
              let windowScene = cursorWindow.windowScene, windowScene.activationState == .foregroundActive,
              let gameViewController = self.gameViewController(in: windowScene, excluding: cursorWindow),
              gameViewController.emulatorCore?.state == .running, // False while the pause menu has paused emulation, since touches can't reach the game.
              let traits = gameViewController.controllerView.controllerSkinTraits,
              let controllerSkin = gameViewController.controllerView.controllerSkin,
              let supportedTraits = controllerSkin.supportedTraits(for: traits),
              let screens = controllerSkin.screens(for: supportedTraits)
        else { return nil }

        // Screens and game views only line up when there is exactly one game view per screen.
        let gameViews = gameViewController.gameViews
        guard screens.count == gameViews.count else { return nil }

        for (screen, gameView) in zip(screens, gameViews) where screen.isTouchScreen
        {
            guard let window = gameView.window, !gameView.isHidden, gameView.alpha > 0, gameView.bounds.width > 10, gameView.bounds.height > 10 else { return nil }

            let frameInWindow = window.convert(gameView.bounds, from: gameView)
            return cursorWindow.convert(frameInWindow, from: window)
        }

        return nil
    }

    func gameViewController(in windowScene: UIWindowScene, excluding cursorWindow: UIWindow) -> DeltaCore.GameViewController?
    {
        for window in windowScene.windows where window !== cursorWindow
        {
            if let gameViewController = self.findGameViewController(in: window.rootViewController)
            {
                return gameViewController
            }
        }

        return nil
    }

    func findGameViewController(in viewController: UIViewController?) -> DeltaCore.GameViewController?
    {
        guard let viewController else { return nil }

        if let gameViewController = viewController as? DeltaCore.GameViewController
        {
            return gameViewController
        }

        for child in viewController.children
        {
            if let gameViewController = self.findGameViewController(in: child)
            {
                return gameViewController
            }
        }

        return self.findGameViewController(in: viewController.presentedViewController)
    }
}
