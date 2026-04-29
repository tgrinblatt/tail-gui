import Foundation

enum DateFormatting {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .numeric
        return f
    }()

    static func relativeString(from date: Date, to reference: Date = Date()) -> String {
        relative.localizedString(for: date, relativeTo: reference)
    }
}
