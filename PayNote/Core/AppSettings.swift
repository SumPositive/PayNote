import Foundation
import SwiftUI

/// AppStorage キー定数
enum AppStorageKey {
    static let enableInstallment = "setting.enableInstallment"
    static let userLevel         = "setting.userLevel"
    static let appearanceMode    = "setting.appearanceMode"
    static let shopSortMode      = "setting.shopSortMode"
    static let categorySortMode  = "setting.categorySortMode"
}

/// ユーザレベル
enum UserLevel: String, CaseIterable, Identifiable {
    case beginner = "beginner"
    case expert   = "expert"

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .beginner: "settings.userLevel.beginner"
        case .expert:   "settings.userLevel.expert"
        }
    }
}

/// 外観モード
enum AppearanceMode: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case light     = "light"
    case dark      = "dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light:     .light
        case .dark:      .dark
        }
    }

    var localizedKey: String {
        switch self {
        case .automatic: "settings.appearance.automatic"
        case .light:     "settings.appearance.light"
        case .dark:      "settings.appearance.dark"
        }
    }
}

/// 旧 GD_OptE4SortMode / GD_OptE5SortMode
enum SortMode: Int, CaseIterable, Identifiable {
    case recent = 0
    case count  = 1
    case amount = 2
    case name   = 3

    var id: Int { rawValue }

    var localizedKey: String {
        switch self {
        case .recent: "sort.recent"
        case .count:  "sort.count"
        case .amount: "sort.amount"
        case .name:   "sort.name"
        }
    }
}
