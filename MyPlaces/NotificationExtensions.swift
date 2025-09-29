//
//  NotificationExtensions.swift
//  MyPlaces
//
//  Created by Jon Guler on 29.09.2025.
//

import Foundation

extension Notification.Name {
    /// User and data management notifications
    static let userDidChange = Notification.Name("userDidChange")
    static let favoritesDidChange = Notification.Name("favoritesDidChange")
    static let themeDidChange = Notification.Name("themeDidChange")
    
    /// Navigation notifications
    static let navigateToPOI = Notification.Name("navigateToPOI")
}
