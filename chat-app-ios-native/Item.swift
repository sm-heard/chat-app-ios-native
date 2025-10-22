//
//  Item.swift
//  chat-app-ios-native
//
//  Created by Sami Heard on 10/22/25.
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
