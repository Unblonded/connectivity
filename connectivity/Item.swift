//
//  Item.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
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
