// Sources/Alveo/Models/HistoryItem.swift
import Foundation
import SwiftData

@Model
final class HistoryItem {
    @Attribute(.unique) var urlString: String // L'URL elle-même peut être l'ID si vous la normalisez
    var title: String?
    var lastVisitedDate: Date
    var visitCount: Int

    init(urlString: String, title: String? = nil, lastVisitedDate: Date = Date(), visitCount: Int = 1) {
        self.urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() // Normaliser
        self.title = title
        self.lastVisitedDate = lastVisitedDate
        self.visitCount = visitCount
    }
}

