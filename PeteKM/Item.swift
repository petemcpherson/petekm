//
//  Item.swift
//  PeteKM
//
//  Created by Pete McPherson on 8/19/26.
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
