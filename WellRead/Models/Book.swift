//
//  Book.swift
//  WellRead
//

import Foundation

struct Book: Identifiable, Codable, Equatable {
    var id: String  // Google Books ID or ISBN
    var title: String
    var author: String
    var coverURL: String
    var pageCount: Int?
    var publishedDate: Date?
    var description: String?
    var genres: [String]
    
    var coverURLRequest: URL? { URL(string: coverURL) }
}

typealias BookID = String
