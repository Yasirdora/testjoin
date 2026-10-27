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

@Test func helpExitsZero() {
    let result = TestJoinCommand.run(["--help"])
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("testjoin search"))
    #expect(result.stdout.contains("testjoin audit"))
}

private func fixturePath(_ name: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
        .path
}
