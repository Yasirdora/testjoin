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
