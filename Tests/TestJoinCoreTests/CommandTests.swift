import Foundation
import Testing
import TestJoinCore

@Test func searchPrintsTheHiddenCancel() throws {
    let result = TestJoinCommand.run([
        "search",
        "--events", fixturePath("cancel-as-pass.events.jsonl"),
        "--swift-testing-xml", fixturePath("cancel-as-pass.swift-testing.xml"),
        "xml:passed AND stream:cancelled",
    ])
    #expect(result.exitCode == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout == "ProbeTests.cancelledTest()  stream=cancelled  xml=passed  tags=camera  duration=0.001s\n")
}

@Test func auditExitsOneWhenTheReportDisagrees() throws {
    let result = TestJoinCommand.run([
        "audit",
        "--events", fixturePath("cancel-as-pass.events.jsonl"),
        "--swift-testing-xml", fixturePath("cancel-as-pass.swift-testing.xml"),
    ])
    #expect(result.exitCode == 1)
    #expect(result.stdout.hasPrefix("1 finding\njunit-records-cancel-as-pass  ProbeTests.cancelledTest()\n"))
}

@Test func auditJSONListsTheCode() throws {
    let result = TestJoinCommand.run([
        "audit",
        "--format", "json",
        "--events", fixturePath("cancel-as-pass.events.jsonl"),
        "--swift-testing-xml", fixturePath("cancel-as-pass.swift-testing.xml"),
        "--expect-xctest",
    ])
    #expect(result.exitCode == 1)
    #expect(result.stdout.contains("\"code\" : \"junit-records-cancel-as-pass\""))
    #expect(result.stdout.contains("\"code\" : \"xctest-junit-missing\""))
}

@Test func unknownFieldExitsTwo() throws {
    let result = TestJoinCommand.run([
        "search",
        "--events", fixturePath("cancel-as-pass.events.jsonl"),
        "--swift-testing-xml", fixturePath("cancel-as-pass.swift-testing.xml"),
        "nope:1",
    ])
    #expect(result.exitCode == 2)
    #expect(result.stdout.isEmpty)
    #expect(result.stderr.contains("Unknown query field"))
}

@Test func subMillisecondDurationIsNotPrintedAsZero() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let events = directory.appendingPathComponent("events.jsonl")
    let xml = directory.appendingPathComponent("results.xml")
    try """
    {"kind":"test","version":"6.4.0","payload":{"kind":"function","id":"ProbeTests.ProbeTests/cancelsItself()/ProbeTests.swift:4:4","name":"cancelsItself()"}}
    {"kind":"event","version":"6.4.0","payload":{"kind":"testStarted","instant":{"since1970":1000},"testID":"ProbeTests.ProbeTests/cancelsItself()/ProbeTests.swift:4:4"}}
    {"kind":"event","version":"6.4.0","payload":{"kind":"testEnded","instant":{"since1970":1000.00026},"messages":[{"symbol":"pass","text":"passed"}],"testID":"ProbeTests.ProbeTests/cancelsItself()/ProbeTests.swift:4:4"}}
    """.write(to: events, atomically: true, encoding: .utf8)
    try """
    <testsuites><testsuite tests="1"><testcase classname="ProbeTests.ProbeTests" name="cancelsItself()" time="0.00026"></testcase></testsuite></testsuites>
    """.write(to: xml, atomically: true, encoding: .utf8)
    let result = TestJoinCommand.run([
        "search",
        "--events", events.path,
        "--swift-testing-xml", xml.path,
        "stream:passed",
    ])
    #expect(result.exitCode == 0)
    #expect(result.stdout == "ProbeTests.ProbeTests.cancelsItself()  stream=passed  xml=passed  duration=0.00026s\n")
}

@Test func swift64CapturePrintsTheHiddenCancel() throws {
    let result = TestJoinCommand.run([
        "search",
        "--events", fixturePath("swift64-probe.events.jsonl"),
        "--swift-testing-xml", fixturePath("swift64-probe.swift-testing.xml"),
        "xml:passed AND stream:cancelled",
    ])
    #expect(result.exitCode == 0)
    #expect(result.stderr.isEmpty)
    #expect(result.stdout == "ProbeTests.ProbeTests.cancelsItself()  stream=cancelled  xml=passed  duration=0.000267s\n")
}

@Test func helpExitsZero() {
    let result = TestJoinCommand.run(["--help"])
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("testjoin search"))
    #expect(result.stdout.contains("testjoin audit"))
    #expect(result.stdout.contains("testjoin capture"))
}

@Test func captureAsksSwiftTestForTheEventStream() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: output) }
    let seen = LaunchBox()
    let result = TestJoinCommand.run([
        "capture",
        "--package", "Examples/Probe",
        "--output", output.path,
    ]) { launch in
        seen.launch = launch
        try "not-empty\n".write(to: output.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        try "<testsuites></testsuites>".write(to: output.appendingPathComponent("results.xml"), atomically: true, encoding: .utf8)
        return ProcessOutput(exitCode: 1, stdout: "", stderr: "cancelled\n")
    }
    let events = output.appendingPathComponent("events.jsonl").path
    let xml = output.appendingPathComponent("results.xml").path
    #expect(result.exitCode == 0)
    #expect(seen.launch == LaunchedProcess(
        executable: "/usr/bin/env",
        arguments: [
            "swift", "test",
            "--package-path", "Examples/Probe",
            "--event-stream-output-path", events,
            "--xunit-output", xml,
            "--disable-xctest",
        ]
    ))
    #expect(result.stdout == "events: \(events)\nswift-testing-xml: \(xml)\n")
    #expect(result.stderr == "swift test exited 1. The event stream and JUnit file were still written. Output: \(output.appendingPathComponent("swift-test.log").path)\n")
}

@Test func captureParallelExpectsBothJUnitFiles() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: output) }
    let seen = LaunchBox()
    let result = TestJoinCommand.run([
        "capture",
        "--package", "Examples/Probe",
        "--output", output.path,
        "--parallel",
        "--swift", "/usr/bin/swift",
    ]) { launch in
        seen.launch = launch
        try "events\n".write(to: output.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        try "<x/>".write(to: output.appendingPathComponent("results.xml"), atomically: true, encoding: .utf8)
        try "<s/>".write(to: output.appendingPathComponent("results-swift-testing.xml"), atomically: true, encoding: .utf8)
        return ProcessOutput(exitCode: 0, stdout: "", stderr: "")
    }
    #expect(result.exitCode == 0)
    #expect(seen.launch?.executable == "/usr/bin/swift")
    #expect(seen.launch?.arguments.contains("--parallel") == true)
    #expect(seen.launch?.arguments.contains("--disable-xctest") == false)
    #expect(result.stdout.contains("xctest-xml: \(output.appendingPathComponent("results.xml").path)"))
    #expect(result.stdout.contains("swift-testing-xml: \(output.appendingPathComponent("results-swift-testing.xml").path)"))
    #expect(result.stderr.isEmpty)
}

@Test func captureAuditReadsTheFilesSwiftTestWrote() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: output) }
    let result = TestJoinCommand.run([
        "capture",
        "--package", "Examples/Probe",
        "--output", output.path,
        "--audit",
    ]) { _ in
        try String(contentsOfFile: fixturePath("cancel-as-pass.events.jsonl"), encoding: .utf8).write(
            to: output.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try String(contentsOfFile: fixturePath("cancel-as-pass.swift-testing.xml"), encoding: .utf8).write(
            to: output.appendingPathComponent("results.xml"),
            atomically: true,
            encoding: .utf8
        )
        return ProcessOutput(exitCode: 1, stdout: "", stderr: "")
    }
    #expect(result.exitCode == 1)
    #expect(result.stdout.hasPrefix("1 finding\njunit-records-cancel-as-pass  ProbeTests.cancelledTest()\n"))
    #expect(result.stderr.contains("events:"))
}

@Test func captureExitsTwoWhenTheFilesAreMissing() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: output) }
    let result = TestJoinCommand.run([
        "capture",
        "--package", "Examples/Probe",
        "--output", output.path,
    ]) { _ in
        ProcessOutput(exitCode: 1, stdout: "", stderr: "error: no such module\n")
    }
    #expect(result.exitCode == 2)
    #expect(result.stdout.isEmpty)
    #expect(result.stderr.contains("did not write"))
    #expect(result.stderr.contains("no such module"))
}

@Test func captureWithoutAPackageExitsTwo() {
    let result = TestJoinCommand.run(["capture", "--output", "/tmp/testjoin-unused"])
    #expect(result.exitCode == 2)
    #expect(result.stderr.contains("Missing --package"))
}

private final class LaunchBox {
    var launch: LaunchedProcess?
}

private func fixturePath(_ name: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
        .path
}
