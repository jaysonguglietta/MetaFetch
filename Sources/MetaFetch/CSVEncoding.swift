import Foundation

enum CSVEncoding {
    static func data(rows: [[String]]) -> Data {
        let csv = rows
            .map { $0.map(escapedCell).joined(separator: ",") }
            .joined(separator: "\n")
        return Data((csv + "\n").utf8)
    }

    static func escapedCell(_ value: String) -> String {
        let formulaSafeValue: String
        if let firstMeaningfulCharacter = value.first(where: { !$0.isWhitespace }),
           ["=", "+", "-", "@"].contains(firstMeaningfulCharacter) {
            formulaSafeValue = "'" + value
        } else {
            formulaSafeValue = value
        }

        let needsQuotes = formulaSafeValue.contains(",") ||
            formulaSafeValue.contains("\"") ||
            formulaSafeValue.contains("\n") ||
            formulaSafeValue.contains("\r")
        let escaped = formulaSafeValue.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}
