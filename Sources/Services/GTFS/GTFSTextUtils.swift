import Foundation

enum GTFSTextUtils {
    /// Mirrors the reference server's ` #\s*\w+$` stripping, used both on
    /// GTFS stop names and on route long names when deriving destinations.
    static func stripTrailingHashCode(_ value: String) -> String {
        guard let range = value.range(of: #" #\s*\w+$"#, options: .regularExpression) else {
            return value.trimmingCharacters(in: .whitespaces)
        }
        var result = value
        result.removeSubrange(range)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Mirrors `stopName.split(/[|!(]/)[0].trim()`.
    static func extractLocalityFromStopName(_ stopName: String) -> String {
        let separators = CharacterSet(charactersIn: "|!(")
        let first = stopName.components(separatedBy: separators).first ?? stopName
        return first.trimmingCharacters(in: .whitespaces)
    }
}
