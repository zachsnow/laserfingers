//
//  AppLog.swift
//  Laserfingers
//
//  Centralized logging configuration using LoggingKit
//

import Foundation

enum AppLog {
    static let editor = PersistentLogger(
        subsystem: "com.laserfingers.app",
        category: "LevelEditor"
    )

    static let scene = PersistentLogger(
        subsystem: "com.laserfingers.app",
        category: "Scene"
    )

    static let touch = PersistentLogger(
        subsystem: "com.laserfingers.app",
        category: "Touch"
    )

    static let zoom = PersistentLogger(
        subsystem: "com.laserfingers.app",
        category: "Zoom"
    )

    static let coordinates = PersistentLogger(
        subsystem: "com.laserfingers.app",
        category: "Coordinates"
    )

    static let game = PersistentLogger(
        subsystem: "com.laserfingers.app",
        category: "Game"
    )

    static let app = PersistentLogger(
        subsystem: "com.laserfingers.app",
        category: "App"
    )
}
