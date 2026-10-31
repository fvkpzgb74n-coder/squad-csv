import Foundation

/// Minimal RFC 4180 CSV reader/writer.
enum CSV {
    /// Guesses the delimiter from the first line: semicolon-separated files are common
    /// from spreadsheet apps in European locales.
    static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
        let commas = firstLine.filter { $0 == "," }.count
        let semicolons = firstLine.filter { $0 == ";" }.count
        let tabs = firstLine.filter { $0 == "\t" }.count
        if tabs > commas && tabs > semicolons { return "\t" }
        return semicolons > commas ? ";" : ","
    }

    static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let delimiter = delimiter ?? detectDelimiter(in: text)

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var index = 0

        func endRow() {
            row.append(field)
            field = ""
            // Skip completely blank lines.
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while index < chars.count {
            let char = chars[index]
            index += 1

            if inQuotes {
                if char == "\"" {
                    if index < chars.count && chars[index] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }

            switch char {
            case "\"" where field.isEmpty:
                inQuotes = true
            case delimiter:
                row.append(field)
                field = ""
            // Note: "\r\n" is a single Character in Swift.
            case "\n", "\r", "\r\n":
                endRow()
            default:
                field.append(char)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }

    static func escape(_ field: String) -> String {
        let needsQuoting = field.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" || $0 == ";" }
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }
}
