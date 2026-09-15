//
//  ClipboardItem.swift
//  SyncBoard
//

import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String, date: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.date = date
    }
}
