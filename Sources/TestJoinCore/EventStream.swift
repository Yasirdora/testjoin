import Foundation

public enum EventStreamError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(line: Int)
    case missingField(line: Int, field: String)

    public var description: String {
        switch self {
        case .invalidJSON(let line):
            return "Event stream line \(line) is not a JSON object."
        case .missingField(let line, let field):
            return "Event stream line \(line) is missing \(field)."
        }
    }
}

// Reads Swift Testing's JSON Lines ABI. Version may be 0 or a semver string.
// Schema 0 uses `_filePath` and often omits `isFailure`. Unknown kinds are ignored.
public func parseEventStream(_ text: String) throws -> [TestRecord] {
    var records: [String: MutableTest] = [:]
    var order: [String] = []
    var events: [(testID: String, payload: [String: Any])] = []
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (offset, rawLine) in lines.enumerated() {
        let lineNumber = offset + 1
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        let object = try jsonObject(line, line: lineNumber)
        guard let kind = object["kind"] as? String else {
            throw EventStreamError.missingField(line: lineNumber, field: "kind")
        }
        switch kind {
        case "test":
            guard let payload = object["payload"] as? [String: Any] else {
                throw EventStreamError.missingField(line: lineNumber, field: "payload")
            }
            guard (payload["kind"] as? String) == "function" else { continue }
            let record = try functionRecord(payload, line: lineNumber)
            guard let streamID = record.streamID, records[streamID] == nil else { continue }
            order.append(streamID)
            records[streamID] = MutableTest(record: record)
        case "event":
            guard let payload = object["payload"] as? [String: Any] else {
                throw EventStreamError.missingField(line: lineNumber, field: "payload")
            }
            if let testID = payload["testID"] as? String {
                events.append((testID, payload))
            }
        default:
            continue
        }
    }

    for event in events {
        guard var mutable = records[event.testID] else { continue }
        apply(event.payload, to: &mutable)
        records[event.testID] = mutable
    }

    return order.compactMap { key in
        guard var mutable = records[key] else { return nil }
        mutable.finish()
        return mutable.record
    }
}

private struct MutableTest {
    var record: TestRecord
    var cancelled = false
    var failed = false
    var skipped = false
    var ended = false
    var started: Double?
    var endedAt: Double?

    // Cancel wins over a later testEnded whose message symbol is "skip".
    // A warning issue (isFailure false, or symbol warning) is not a failure.
    mutating func finish() {
        if cancelled {
            record.streamStatus = .cancelled
        } else if failed {
            record.streamStatus = .failed
        } else if skipped {
            record.streamStatus = .skipped
        } else if ended {
            record.streamStatus = .passed
        }
        if let started, let endedAt, endedAt >= started {
            record.duration = endedAt - started
        }
    }
}

private func functionRecord(_ payload: [String: Any], line: Int) throws -> TestRecord {
    guard let name = payload["name"] as? String else {
        throw EventStreamError.missingField(line: line, field: "name")
    }
    guard let streamID = payload["id"] as? String else {
        throw EventStreamError.missingField(line: line, field: "id")
    }
    let identity = streamIdentity(eventID: streamID, functionName: name)
    return TestRecord(
        id: identity,
        streamID: streamID,
        name: name,
        displayName: payload["displayName"] as? String,
        suite: suiteName(identity: identity, functionName: name),
        source: sourceLocation(payload["sourceLocation"]),
        tags: stringArray(payload["tags"]),
        bugs: bugs(payload["bugs"]),
        timeLimit: jsonDouble(payload["timeLimit"]),
        isParameterized: jsonBool(payload["isParameterized"]) ?? false,
        framework: .swiftTesting
    )
}

private func suiteName(identity: String, functionName: String) -> String? {
    let suffix = "." + functionName
    guard identity.hasSuffix(suffix) else { return nil }
    let suite = String(identity.dropLast(suffix.count))
    return suite.isEmpty ? nil : suite
}

private func apply(_ payload: [String: Any], to mutable: inout MutableTest) {
    let kind = payload["kind"] as? String ?? ""
    switch kind {
    case "testCancelled", "testCaseCancelled":
        mutable.cancelled = true
    case "testSkipped":
        mutable.skipped = true
    case "issueRecorded":
        if issueIsFailure(payload) { mutable.failed = true }
    case "testStarted":
        if mutable.started == nil { mutable.started = instant(payload) }
    case "testEnded":
        mutable.ended = true
        mutable.endedAt = instant(payload)
    default:
        break
    }
}

private func issueIsFailure(_ payload: [String: Any]) -> Bool {
    if let issue = payload["issue"] as? [String: Any], let flag = jsonBool(issue["isFailure"]) {
        return flag
    }
    return messageSymbol(payload) == "fail"
}

private func messageSymbol(_ payload: [String: Any]) -> String? {
    guard let messages = payload["messages"] as? [Any] else { return nil }
    for message in messages {
        guard let object = message as? [String: Any], let symbol = object["symbol"] as? String else { continue }
        if symbol != "default" && symbol != "details" { return symbol }
    }
    return nil
}

private func instant(_ payload: [String: Any]) -> Double? {
    guard let instant = payload["instant"] as? [String: Any] else { return nil }
    return jsonDouble(instant["since1970"]) ?? jsonDouble(instant["absolute"])
}

private func sourceLocation(_ value: Any?) -> SourceLocation? {
    guard let object = value as? [String: Any] else { return nil }
    let path = (object["filePath"] as? String) ?? (object["_filePath"] as? String) ?? ""
    guard !path.isEmpty else { return nil }
    return SourceLocation(
        filePath: path,
        line: jsonInt(object["line"]) ?? 0,
        column: jsonInt(object["column"]) ?? 0
    )
}

private func stringArray(_ value: Any?) -> [String] {
    guard let array = value as? [Any] else { return [] }
    return array.compactMap { $0 as? String }
}

private func bugs(_ value: Any?) -> [Bug] {
    guard let array = value as? [Any] else { return [] }
    return array.compactMap { item in
        guard let object = item as? [String: Any] else { return nil }
        return Bug(
            id: object["id"] as? String,
            url: object["url"] as? String,
            title: object["title"] as? String
        )
    }
}

private func jsonObject(_ line: String, line number: Int) throws -> [String: Any] {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw EventStreamError.invalidJSON(line: number)
    }
    return object
}

func jsonBool(_ value: Any?) -> Bool? {
    guard let value else { return nil }
    if let bool = value as? Bool { return bool }
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

func jsonDouble(_ value: Any?) -> Double? {
    guard let value else { return nil }
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    return number.doubleValue
}

func jsonInt(_ value: Any?) -> Int? {
    guard let number = jsonDouble(value) else { return nil }
    return Int(number)
}
