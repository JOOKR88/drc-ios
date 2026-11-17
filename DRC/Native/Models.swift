import Foundation

struct SessionInfo: Codable {
    struct User: Codable {
        let id: String?
        let name: String?
        let image: String?
    }
    let user: User?
}

struct MeSummary: Codable {
    struct WeeklyRow: Codable, Hashable {
        let name: String
        let avatar: String?
        let points: Int
    }
    struct Txn: Codable, Hashable {
        let amount: Int
        let source: String
        let note: String?
        let at: String
    }
    struct SoulCard: Codable, Hashable {
        let href: String
        let title: String
        let image: String?
        let game: String
        var slug: String { href.replacingOccurrences(of: "/souls/", with: "") }
    }

    let points: Int
    let level: Int
    let intoLevel: Int
    let needed: Int
    let rank: Int?
    let today: Int
    let weekly: [WeeklyRow]
    let myWeek: Int
    let recent: [Txn]
    let souls: [SoulCard]
}

struct LbRow: Codable, Identifiable, Hashable {
    let rank: Int
    let userId: String?
    let name: String
    let avatar: String?
    let points: Int
    let total: Int?
    let isMe: Bool?
    var id: String { (userId ?? name) + "-\(rank)" }
}

struct LeaderboardResponse: Codable {
    struct Me: Codable, Hashable {
        let rank: Int
        let xp: Int
        let level: Int
    }
    let board: String
    let rows: [LbRow]
    let me: Me?
}

struct SearchResponse: Codable {
    let rows: [LbRow]
}

struct SoulsGame: Codable, Hashable, Identifiable {
    let key: String
    let name: String
    let accent: String
    var id: String { key }
}

struct ArticleSummary: Codable, Hashable, Identifiable {
    let id: String
    let slug: String
    let title: String
    let excerpt: String
    let image: String?
    let game: String
    let section: String
    let views: Int
    let createdAt: String
    let updatedAt: String
}

struct SoulsIndex: Codable {
    let games: [SoulsGame]
    let articles: [ArticleSummary]
}

struct Article: Codable {
    struct Author: Codable {
        let name: String?
        let avatar: String?
    }
    let id: String
    let slug: String
    let title: String
    let image: String?
    let game: String
    let gameName: String
    let accent: String
    let section: String
    let tags: [String]
    let views: Int
    let minutes: Int
    let author: Author
    let createdAt: String
    let updatedAt: String
    let content: String
}
