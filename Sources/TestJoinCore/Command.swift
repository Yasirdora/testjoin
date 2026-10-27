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

public struct LaunchedProcess: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public struct ProcessOutput: Equatable, Sendable {
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
        testjoin capture --package <path> --output <dir> [--audit] [--parallel] [--swift <path>] [--format text|json]

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

        capture runs swift test. On this toolchain, swift test --help does not list
        --event-stream-output-path, and the command accepts it anyway:
          swift test --package-path <path> --event-stream-output-path <dir>/events.jsonl --xunit-output <dir>/results.xml --disable-xctest
        --disable-xctest writes Swift Testing JUnit to the path you named.
        --parallel omits --disable-xctest. XCTest is then <dir>/results.xml and Swift Testing is <dir>/results-swift-testing.xml.
        --audit prints the audit and uses its exit code. A non-zero swift test exit does not fail capture when those files were written.

        audit exits 0 when it finds nothing and 1 when it finds a disagreement.
        A bad invocation exits 2.

        """

    public static func run(_ arguments: [String]) -> CommandResult {
        run(arguments, runner: liveProcess)
    }

    public static func run(
        _ arguments: [String],
        runner: (LaunchedProcess) throws -> ProcessOutput
    ) -> CommandResult {
        do {
            return try execute(arguments, runner: runner)
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

private struct Invocation {
    var command: String?
    var eventsPath: String?
    var swiftXMLPath: String?
    var xctestXMLPath: String?
    var expectXCTest = false
    var format = Format.text
    var formatWasSet = false
    var positionals: [String] = []
    var packagePath: String?
    var outputPath: String?
    var auditAfterCapture = false
    var parallel = false
    var swiftPath = "swift"
    var swiftWasSet = false
}

private func execute(
    _ arguments: [String],
    runner: (LaunchedProcess) throws -> ProcessOutput
) throws -> CommandResult {
    if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
        return CommandResult(exitCode: 0, stdout: TestJoinCommand.help, stderr: "")
    }

    let invocation = try parse(arguments)
    guard let command = invocation.command else { throw CommandError.usage(TestJoinCommand.help) }
    switch command {
    case "search":
        return try runSearch(invocation)
    case "audit":
        return try runAudit(invocation)
    case "capture":
        return try runCapture(invocation, runner: runner)
    default:
        throw CommandError.usage("Unknown command '\(command)'. Use search, audit, or capture.\n" + TestJoinCommand.help)
    }
}

private func parse(_ arguments: [String]) throws -> Invocation {
    var index = 0
    var invocation = Invocation()

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
            invocation.eventsPath = try take()
        case "--swift-testing-xml":
            invocation.swiftXMLPath = try take()
        case "--xctest-xml":
            invocation.xctestXMLPath = try take()
        case "--format":
            invocation.formatWasSet = true
            switch try take() {
            case "text": invocation.format = .text
            case "json": invocation.format = .json
            case let other:
                throw CommandError.usage("Unknown format '\(other)'. Use text or json.")
            }
        case "--expect-xctest":
            invocation.expectXCTest = true
        case "--package":
            invocation.packagePath = try take()
        case "--output":
            invocation.outputPath = try take()
        case "--audit":
            invocation.auditAfterCapture = true
        case "--parallel":
            invocation.parallel = true
        case "--swift":
            invocation.swiftWasSet = true
            invocation.swiftPath = try take()
        default:
            if argument.hasPrefix("-") {
                throw CommandError.usage("Unknown option '\(argument)'.\n" + TestJoinCommand.help)
            }
            if invocation.command == nil {
                invocation.command = argument
            } else {
                invocation.positionals.append(argument)
            }
        }
    }
    return invocation
}

private func runSearch(_ invocation: Invocation) throws -> CommandResult {
    try rejectCaptureOptions(invocation, command: "search")
    let run = try joined(invocation)
    let queryText = invocation.positionals.joined(separator: " ")
    let query = try parseQuery(queryText)
    let hits = run.records.filter { query.matches($0) }.sorted(by: displayOrder)
    return CommandResult(exitCode: 0, stdout: renderSearch(hits, format: invocation.format), stderr: "")
}

private func runAudit(_ invocation: Invocation) throws -> CommandResult {
    try rejectCaptureOptions(invocation, command: "audit")
    if !invocation.positionals.isEmpty {
        throw CommandError.usage("audit does not take a query.\n" + TestJoinCommand.help)
    }
    let run = try joined(invocation)
    let exit: Int32 = run.findings.isEmpty ? 0 : 1
    return CommandResult(exitCode: exit, stdout: renderAudit(run.findings, format: invocation.format), stderr: "")
}

private func rejectCaptureOptions(_ invocation: Invocation, command: String) throws {
    if invocation.packagePath != nil || invocation.outputPath != nil || invocation.auditAfterCapture
        || invocation.parallel || invocation.swiftWasSet
    {
        throw CommandError.usage("\(command) does not take capture options.\n" + TestJoinCommand.help)
    }
}

private func joined(_ invocation: Invocation) throws -> JoinedRun {
    guard let eventsPath = invocation.eventsPath else {
        throw CommandError.usage("Missing --events.\n" + TestJoinCommand.help)
    }
    guard let swiftXMLPath = invocation.swiftXMLPath else {
        throw CommandError.usage("Missing --swift-testing-xml.\n" + TestJoinCommand.help)
    }
    let events = try readFile(eventsPath)
    let swiftXML = try readFile(swiftXMLPath)
    let xctestXML = try invocation.xctestXMLPath.map { try readFile($0) }
    return try joinRun(
        events: events,
        swiftTestingXML: swiftXML,
        xctestXML: xctestXML,
        expectXCTest: invocation.expectXCTest
    )
}

private struct CapturePaths {
    var launch: LaunchedProcess
    var events: String
    var swiftXML: String
    var xctestXML: String?
}

private func capturePaths(package: String, output: String, swift: String, parallel: Bool) -> CapturePaths {
    let root = URL(fileURLWithPath: output)
    let events = root.appendingPathComponent("events.jsonl").path
    let requestedXML = root.appendingPathComponent("results.xml").path
    var testArguments = [
        "test",
        "--package-path", package,
        "--event-stream-output-path", events,
        "--xunit-output", requestedXML,
    ]
    let swiftXML: String
    let xctestXML: String?
    if parallel {
        testArguments.append("--parallel")
        swiftXML = root.appendingPathComponent("results-swift-testing.xml").path
        xctestXML = requestedXML
    } else {
        testArguments.append("--disable-xctest")
        swiftXML = requestedXML
        xctestXML = nil
    }
    let launch: LaunchedProcess
    if swift == "swift" {
        launch = LaunchedProcess(executable: "/usr/bin/env", arguments: ["swift"] + testArguments)
    } else {
        launch = LaunchedProcess(executable: swift, arguments: testArguments)
    }
    return CapturePaths(launch: launch, events: events, swiftXML: swiftXML, xctestXML: xctestXML)
}

private func runCapture(
    _ invocation: Invocation,
    runner: (LaunchedProcess) throws -> ProcessOutput
) throws -> CommandResult {
    if invocation.eventsPath != nil || invocation.swiftXMLPath != nil || invocation.xctestXMLPath != nil
        || invocation.expectXCTest
    {
        throw CommandError.usage("capture reads the files swift test writes. Pass --package and --output.\n" + TestJoinCommand.help)
    }
    if !invocation.positionals.isEmpty {
        throw CommandError.usage("capture does not take a query.\n" + TestJoinCommand.help)
    }
    if invocation.formatWasSet && !invocation.auditAfterCapture {
        throw CommandError.usage("--format applies to capture --audit.\n" + TestJoinCommand.help)
    }
    guard let package = invocation.packagePath else {
        throw CommandError.usage("Missing --package.\n" + TestJoinCommand.help)
    }
    guard let output = invocation.outputPath else {
        throw CommandError.usage("Missing --output.\n" + TestJoinCommand.help)
    }
    do {
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    } catch {
        throw CommandError.input("Could not create \(output).")
    }

    let paths = capturePaths(
        package: package,
        output: output,
        swift: invocation.swiftPath,
        parallel: invocation.parallel
    )
    let process = try runner(paths.launch)
    let log = URL(fileURLWithPath: output).appendingPathComponent("swift-test.log")
    try writeCaptureLog(process, to: log)

    var missing: [String] = []
    if !nonemptyFile(paths.events) { missing.append(paths.events) }
    if !nonemptyFile(paths.swiftXML) { missing.append(paths.swiftXML) }
    if let xctestXML = paths.xctestXML, !nonemptyFile(xctestXML) { missing.append(xctestXML) }
    if !missing.isEmpty {
        var message = "swift test exited \(process.exitCode) and did not write \(missing.joined(separator: ", ")).\n"
        let tail = suffix(process.stderr, limit: 4000)
        if !tail.isEmpty { message += tail }
        if !message.hasSuffix("\n") { message += "\n" }
        return CommandResult(exitCode: 2, stdout: "", stderr: message)
    }

    var notes = ""
    if process.exitCode != 0 {
        notes = "swift test exited \(process.exitCode). The event stream and JUnit file were still written. Output: \(log.path)\n"
    }
    var lines = [
        "events: \(paths.events)",
        "swift-testing-xml: \(paths.swiftXML)",
    ]
    if let xctestXML = paths.xctestXML {
        lines.append("xctest-xml: \(xctestXML)")
    }
    let pathText = lines.joined(separator: "\n") + "\n"

    guard invocation.auditAfterCapture else {
        return CommandResult(exitCode: 0, stdout: pathText, stderr: notes)
    }

    let run = try joinRun(
        events: try readFile(paths.events),
        swiftTestingXML: try readFile(paths.swiftXML),
        xctestXML: try paths.xctestXML.map { try readFile($0) },
        expectXCTest: paths.xctestXML != nil
    )
    let exit: Int32 = run.findings.isEmpty ? 0 : 1
    return CommandResult(
        exitCode: exit,
        stdout: renderAudit(run.findings, format: invocation.format),
        stderr: pathText + notes
    )
}

private func writeCaptureLog(_ process: ProcessOutput, to url: URL) throws {
    var text = ""
    if !process.stdout.isEmpty {
        text += "stdout:\n"
        text += process.stdout
        if !process.stdout.hasSuffix("\n") { text += "\n" }
    }
    if !process.stderr.isEmpty {
        text += "stderr:\n"
        text += process.stderr
        if !process.stderr.hasSuffix("\n") { text += "\n" }
    }
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        throw CommandError.input("Could not write \(url.path).")
    }
}

private func nonemptyFile(_ path: String) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? NSNumber
    else { return false }
    return size.int64Value > 0
}

private func suffix(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.suffix(limit))
}

private func liveProcess(_ launch: LaunchedProcess) throws -> ProcessOutput {
    let stdoutURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".out")
    let stderrURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".err")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launch.executable)
    process.arguments = launch.arguments
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    do {
        try process.run()
    } catch {
        try? stdoutHandle.close()
        try? stderrHandle.close()
        try? FileManager.default.removeItem(at: stdoutURL)
        try? FileManager.default.removeItem(at: stderrURL)
        throw CommandError.input("Could not run \(launch.executable).")
    }
    process.waitUntilExit()
    try stdoutHandle.close()
    try stderrHandle.close()
    let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
    let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(at: stdoutURL)
    try? FileManager.default.removeItem(at: stderrURL)
    return ProcessOutput(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
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
        parts.append(formatDuration(duration))
    }
    return parts.joined(separator: "  ")
}

// Three digits match times at or above one millisecond (0.001s stays 0.001s).
// Shorter runs keep enough digits that a sub-millisecond test is not printed as 0.000s.
func formatDuration(_ seconds: Double) -> String {
    if seconds >= 0.001 {
        return String(format: "duration=%.3fs", seconds)
    }
    if seconds > 0 {
        var trimmed = String(format: "%.6f", seconds)
        if trimmed.contains(".") {
            while trimmed.hasSuffix("0") { trimmed.removeLast() }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
        }
        if trimmed != "0" {
            return "duration=\(trimmed)s"
        }
        return String(format: "duration=%.3es", seconds)
    }
    return "duration=0s"
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
