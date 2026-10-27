import Foundation

public enum QueryError: Error, Equatable, CustomStringConvertible {
    case empty
    case unknownField(String)
    case badDuration(String)
    case badStatus(String)
    case badXMLStatus(String)
    case badFramework(String)

    public var description: String {
        switch self {
        case .empty:
            return "Query is empty. Terms are AND. Example: xml:passed AND stream:cancelled"
        case .unknownField(let field):
            return "Unknown query field '\(field)'. Fields: tag, status, stream, xml, bug, duration, framework."
        case .badDuration(let raw):
            return "Bad duration '\(raw)'. Use duration:>2, duration:>=2, duration:<2, duration:<=2, or duration:2."
        case .badStatus(let raw):
            return "Bad status '\(raw)'. Use passed, failed, skipped, or cancelled."
        case .badXMLStatus(let raw):
            return "Bad xml status '\(raw)'. Use passed, failed, skipped, or error."
        case .badFramework(let raw):
            return "Bad framework '\(raw)'. Use swift-testing or xctest."
        }
    }
}

enum Comparison: Equatable {
    case greater
    case greaterOrEqual
    case less
    case lessOrEqual
    case equal

    func matches(_ duration: Double, _ value: Double) -> Bool {
        switch self {
        case .greater: return duration > value
        case .greaterOrEqual: return duration >= value
        case .less: return duration < value
        case .lessOrEqual: return duration <= value
        case .equal: return duration == value
        }
    }
}

enum Clause: Equatable {
    case text(String)
    case tag(String)
    case stream(StreamStatus)
    case xml(XMLStatus)
    case bug(String)
    case duration(Comparison, Double)
    case framework(Framework)

    func matches(_ record: TestRecord) -> Bool {
        switch self {
        case .text(let value):
            let haystack = [record.id, record.name, record.displayName ?? "", record.suite ?? ""]
                .joined(separator: "\n")
                .lowercased()
            return haystack.contains(value.lowercased())
        case .tag("none"):
            return record.tags.isEmpty
        case .tag(let value):
            return record.tags.contains(value)
        case .stream(let status):
            return record.streamStatus == status
        case .xml(let status):
            return record.xmlStatus == status
        case .bug(let value):
            return record.bugs.contains { bug in
                bug.id == value
                    || bug.url?.contains(value) == true
                    || bug.title?.contains(value) == true
            }
        case .duration(let comparison, let value):
            guard let duration = record.duration else { return false }
            return comparison.matches(duration, value)
        case .framework(let framework):
            return record.framework == framework
        }
    }
}

public struct Query: Equatable {
    var clauses: [Clause]

    public func matches(_ record: TestRecord) -> Bool {
        clauses.allSatisfy { $0.matches(record) }
    }
}

public func parseQuery(_ text: String) throws -> Query {
    let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init).filter {
        $0.caseInsensitiveCompare("AND") != .orderedSame
    }
    if tokens.isEmpty { throw QueryError.empty }

    var clauses: [Clause] = []
    for token in tokens {
        guard let colon = token.firstIndex(of: ":") else {
            clauses.append(.text(token))
            continue
        }
        let field = String(token[..<colon]).lowercased()
        let value = String(token[token.index(after: colon)...])
        if value.isEmpty { throw QueryError.unknownField(field) }
        clauses.append(try clause(field: field, value: value))
    }
    return Query(clauses: clauses)
}

private func clause(field: String, value: String) throws -> Clause {
    switch field {
    case "tag":
        return .tag(value)
    case "status", "stream":
        guard let status = StreamStatus(rawValue: value) else { throw QueryError.badStatus(value) }
        return .stream(status)
    case "xml":
        guard let status = XMLStatus(rawValue: value) else { throw QueryError.badXMLStatus(value) }
        return .xml(status)
    case "bug":
        return .bug(value)
    case "framework":
        guard let framework = Framework(rawValue: value) else { throw QueryError.badFramework(value) }
        return .framework(framework)
    case "duration":
        let (comparison, number) = try parseDuration(value)
        return .duration(comparison, number)
    default:
        throw QueryError.unknownField(field)
    }
}

private func parseDuration(_ raw: String) throws -> (Comparison, Double) {
    let operators: [(String, Comparison)] = [
        (">=", .greaterOrEqual),
        ("<=", .lessOrEqual),
        (">", .greater),
        ("<", .less),
        ("=", .equal),
    ]
    for (prefix, comparison) in operators where raw.hasPrefix(prefix) {
        let number = String(raw.dropFirst(prefix.count))
        guard let value = Double(number) else { throw QueryError.badDuration(raw) }
        return (comparison, value)
    }
    guard let value = Double(raw) else { throw QueryError.badDuration(raw) }
    return (.equal, value)
}
