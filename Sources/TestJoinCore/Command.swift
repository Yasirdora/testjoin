import Foundation

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum TestJoinCommand {
    public static let help = """
        testjoin search --events <events.jsonl> --swift-testing-xml <file> [--xctest-xml <file>] [--format text|json] <query>
        testjoin audit --events <events.jsonl> --swift-testing-xml <file> [--xctest-xml <file>] [--expect-xctest] [--format text|json]

        Joins a Swift Testing JSON Lines event stream to JUnit XML and queries the result.
        Every query term is AND. The word AND is optional.

          tag:<name>          exact tag, or tag:none
          status:<status>     event-stream status: passed, failed, skipped, cancelled
          stream:<status>     same as status
          xml:<status>        JUnit status: passed, failed, skipped, error
          bug:<text>          bug id, or a url or title containing the text
          duration:>N         also >=, <, <=, or a bare number for equality
          framework:<name>    swift-testing or xctest
          <text>              case-insensitive match on id, name, display name, or suite

        audit exits 0 when it finds nothing and 1 when it finds a disagreement.
        A bad invocation exits 2.

        """

    public static func run(_ arguments: [String]) -> CommandResult {
        do {
            return try execute(arguments)
        } catch {
            return CommandResult(exitCode: 2, stdout: "", stderr: String(describing: error) + "\n")
        }
    }
}

private enum Format {
    case text
    case json
}

private enum CommandError: Error, CustomStringConvertible {
    case usage(String)
    case input(String)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .input(let message): return message
        }
    }
}

private func execute(_ arguments: [String]) throws -> CommandResult {
    if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
        return CommandResult(exitCode: 0, stdout: TestJoinCommand.help, stderr: "")
    }

    var index = 0
    var command: String?
    var eventsPath: String?
    var swiftXMLPath: String?
    var xctestXMLPath: String?
    var expectXCTest = false
    var format = Format.text
    var positionals: [String] = []

    func take() throws -> String {
        guard index < arguments.count else { throw CommandError.usage(TestJoinCommand.help) }
        let value = arguments[index]
        index += 1
        return value
    }

    while index < arguments.count {
        let argument = arguments[index]
        index += 1
        switch argument {
        case "--events":
            eventsPath = try take()
        case "--swift-testing-xml":
            swiftXMLPath = try take()
        case "--xctest-xml":
            xctestXMLPath = try take()
        case "--format":
            switch try take() {
            case "text": format = .text
            case "json": format = .json
            case let other:
                throw CommandError.usage("Unknown format '\(other)'. Use text or json.")
            }
        case "--expect-xctest":
            expectXCTest = true
        default:
            if argument.hasPrefix("-") {
                throw CommandError.usage("Unknown option '\(argument)'.\n" + TestJoinCommand.help)
            }
            if command == nil {
                command = argument
            } else {
                positionals.append(argument)
            }
        }
    }

    guard let command else { throw CommandError.usage(TestJoinCommand.help) }
    guard let eventsPath else { throw CommandError.usage("Missing --events.\n" + TestJoinCommand.help) }
    guard let swiftXMLPath else {
        throw CommandError.usage("Missing --swift-testing-xml.\n" + TestJoinCommand.help)
    }

    let events = try readFile(eventsPath)
    let swiftXML = try readFile(swiftXMLPath)
    let xctestXML = try xctestXMLPath.map { try readFile($0) }
    let run = try joinRun(
        events: events,
        swiftTestingXML: swiftXML,
        xctestXML: xctestXML,
        expectXCTest: expectXCTest
    )

    switch command {
    case "search":
        let queryText = positionals.joined(separator: " ")
        let query = try parseQuery(queryText)
        let hits = run.records.filter { query.matches($0) }.sorted(by: displayOrder)
        return CommandResult(exitCode: 0, stdout: renderSearch(hits, format: format), stderr: "")
    case "audit":
        if !positionals.isEmpty {
            throw CommandError.usage("audit does not take a query.\n" + TestJoinCommand.help)
        }
        let exit: Int32 = run.findings.isEmpty ? 0 : 1
        return CommandResult(exitCode: exit, stdout: renderAudit(run.findings, format: format), stderr: "")
    default:
        throw CommandError.usage("Unknown command '\(command)'. Use search or audit.\n" + TestJoinCommand.help)
    }
}

private func readFile(_ path: String) throws -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        throw CommandError.input("Could not read \(path).")
    }
}

private func displayOrder(_ lhs: TestRecord, _ rhs: TestRecord) -> Bool {
    if lhs.framework != rhs.framework { return lhs.framework.rawValue < rhs.framework.rawValue }
    return lhs.id < rhs.id
}

private func renderSearch(_ records: [TestRecord], format: Format) -> String {
    switch format {
    case .text:
        if records.isEmpty { return "0 tests\n" }
        return records.map(textLine).joined(separator: "\n") + "\n"
    case .json:
        return prettyJSON(records.map(recordObject)) + "\n"
    }
}

private func renderAudit(_ findings: [Finding], format: Format) -> String {
    switch format {
    case .text:
        var lines = ["\(findings.count) finding\(findings.count == 1 ? "" : "s")"]
        for finding in findings {
            if let testID = finding.testID {
                lines.append("\(finding.code)  \(testID)")
            } else {
                lines.append(finding.code)
            }
            lines.append("  \(finding.detail)")
        }
        return lines.joined(separator: "\n") + "\n"
    case .json:
        let objects = findings.map { finding -> [String: Any] in
            var object: [String: Any] = ["code": finding.code, "detail": finding.detail]
            if let testID = finding.testID { object["id"] = testID }
            return object
        }
        return prettyJSON(["findings": objects]) + "\n"
    }
}

private func textLine(_ record: TestRecord) -> String {
    var parts = [record.id]
    if let status = record.streamStatus { parts.append("stream=\(status.rawValue)") }
    if let status = record.xmlStatus { parts.append("xml=\(status.rawValue)") }
    if !record.tags.isEmpty { parts.append("tags=\(record.tags.joined(separator: ","))") }
    if let duration = record.duration {
        parts.append(String(format: "duration=%.3fs", duration))
    }
    return parts.joined(separator: "  ")
}

private func recordObject(_ record: TestRecord) -> [String: Any] {
    var object: [String: Any] = [
        "framework": record.framework.rawValue,
        "id": record.id,
        "name": record.name,
        "tags": record.tags,
    ]
    if let displayName = record.displayName { object["displayName"] = displayName }
    if let suite = record.suite { object["suite"] = suite }
    if let status = record.streamStatus { object["streamStatus"] = status.rawValue }
    if let status = record.xmlStatus { object["xmlStatus"] = status.rawValue }
    if let duration = record.duration { object["duration"] = duration }
    if !record.bugs.isEmpty {
        object["bugs"] = record.bugs.map { bug -> [String: String] in
            var item: [String: String] = [:]
            if let id = bug.id { item["id"] = id }
            if let url = bug.url { item["url"] = url }
            if let title = bug.title { item["title"] = title }
            return item
        }
    }
    return object
}

private func prettyJSON(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
        return "{}\n"
    }
    return text
}
