//
//  Item.swift
//  MyPlaces
//
//  Created by Jon Guler on 27.01.2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
