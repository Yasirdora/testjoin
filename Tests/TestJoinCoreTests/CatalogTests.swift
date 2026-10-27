import Foundation
import Testing
import TestJoinCore

@Test func fixtureShowsCancelRecordedAsPass() throws {
    let run = try joinRun(
        events: try fixture("cancel-as-pass.events.jsonl"),
        swiftTestingXML: try fixture("cancel-as-pass.swift-testing.xml")
    )
    let hidden = try #require(run.records.first { $0.id == "ProbeTests.cancelledTest()" })
    #expect(hidden.streamStatus == .cancelled)
    #expect(hidden.xmlStatus == .passed)
    #expect(hidden.tags == ["camera"])
    #expect(hidden.source?.filePath == "Tests/ProbeTests/ProbeTests.swift")
    #expect(run.findings == [
        Finding(
            code: "junit-records-cancel-as-pass",
            testID: "ProbeTests.cancelledTest()",
            detail: "Swift Testing cancelled this test. The JUnit testcase has no failure, error, or skipped element, so importers treat it as a pass."
        ),
    ])
    let passed = try #require(run.records.first { $0.id == "ProbeTests.fastTest()" })
    #expect(passed.streamStatus == .passed)
    #expect(passed.xmlStatus == .passed)
}

@Test func queryOnTheFixtureFindsOnlyTheHiddenCancel() throws {
    let run = try joinRun(
        events: try fixture("cancel-as-pass.events.jsonl"),
        swiftTestingXML: try fixture("cancel-as-pass.swift-testing.xml")
    )
    let query = try parseQuery("tag:camera AND xml:passed AND stream:cancelled")
    #expect(run.records.filter(query.matches).map(\.id) == ["ProbeTests.cancelledTest()"])
}

@Test func emptyJUnitIsOneFinding() throws {
    let events = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.cancelledTest()/ProbeTests.swift:1:1","name":"cancelledTest()"}}
        {"kind":"event","payload":{"kind":"testCancelled","testID":"ProbeTests.cancelledTest()/ProbeTests.swift:1:1"}}
        """
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
          <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0"></testsuite>
        </testsuites>
        """
    let run = try joinRun(events: events, swiftTestingXML: xml)
    #expect(run.findings.map(\.code) == ["junit-reports-no-tests"])
}

@Test func omittedCancelIsReportedWhenTheFileHasOtherCases() throws {
    let events = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.cancelledTest()/ProbeTests.swift:1:1","name":"cancelledTest()"}}
        {"kind":"event","payload":{"kind":"testCancelled","testID":"ProbeTests.cancelledTest()/ProbeTests.swift:1:1"}}
        """
    let xml = """
        <testsuites><testsuite tests="1"><testcase classname="ProbeTests" name="fastTest()" /></testsuite></testsuites>
        """
    let run = try joinRun(events: events, swiftTestingXML: xml)
    #expect(run.findings.map(\.code) == ["junit-omits-cancelled-test"])
}

@Test func skippedJUnitIsNotAHiddenPass() throws {
    let events = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.disabledTest()/ProbeTests.swift:1:1","name":"disabledTest()"}}
        {"kind":"event","payload":{"kind":"testSkipped","testID":"ProbeTests.disabledTest()/ProbeTests.swift:1:1"}}
        """
    let xml = """
        <testsuites><testsuite tests="1"><testcase classname="ProbeTests" name="disabledTest()"><skipped>Needs network</skipped></testcase></testsuite></testsuites>
        """
    let run = try joinRun(events: events, swiftTestingXML: xml)
    #expect(run.findings.isEmpty)
}

@Test func nestedJUnitClassnameJoins() throws {
    let events = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.Outer/Inner/nested()/ProbeTests.swift:61:6","name":"nested()"}}
        {"kind":"event","payload":{"kind":"testEnded","messages":[{"symbol":"pass","text":"passed"}],"testID":"ProbeTests.Outer/Inner/nested()/ProbeTests.swift:61:6"}}
        """
    let xml = """
        <testsuites><testsuite tests="1"><testcase classname="ProbeTests.Outer.Inner" name="nested()" time="0.25" /></testsuite></testsuites>
        """
    let run = try joinRun(events: events, swiftTestingXML: xml)
    let record = try #require(run.records.first)
    #expect(record.xmlStatus == .passed)
    #expect(record.streamStatus == .passed)
    #expect(run.findings.isEmpty)
}

@Test func decodedXMLNameJoins() throws {
    let events = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.größe()/ProbeTests.swift:1:1","name":"größe()"}}
        {"kind":"event","payload":{"kind":"testEnded","messages":[{"symbol":"fail","text":"failed"}],"testID":"ProbeTests.größe()/ProbeTests.swift:1:1"}}
        {"kind":"event","payload":{"kind":"issueRecorded","messages":[{"symbol":"fail","text":"failed"}],"testID":"ProbeTests.größe()/ProbeTests.swift:1:1"}}
        """
    let xml = """
        <testsuites><testsuite tests="1"><testcase classname="ProbeTests" name="gr&#246;&#223;e()"><failure message="no" /></testcase></testsuite></testsuites>
        """
    let run = try joinRun(events: events, swiftTestingXML: xml)
    #expect(run.records.first?.xmlStatus == .failed)
    #expect(run.findings.isEmpty)
}

@Test func swift64CaptureJoinsCancelToAPassingTestcase() throws {
    let run = try joinRun(
        events: try fixture("swift64-probe.events.jsonl"),
        swiftTestingXML: try fixture("swift64-probe.swift-testing.xml")
    )
    let cancelled = try #require(run.records.first { $0.id == "ProbeTests.ProbeTests.cancelsItself()" })
    #expect(cancelled.streamStatus == .cancelled)
    #expect(cancelled.xmlStatus == .passed)
    #expect(cancelled.source?.filePath == "Examples/Probe/Tests/ProbeTests/ProbeTests.swift")
    let tagged = try #require(run.records.first { $0.id == "ProbeTests.ProbeTests.taggedPass()" })
    #expect(tagged.tags == ["camera"])
    #expect(tagged.streamStatus == .passed)
    #expect(tagged.xmlStatus == .passed)
    #expect(run.findings == [
        Finding(
            code: "junit-records-cancel-as-pass",
            testID: "ProbeTests.ProbeTests.cancelsItself()",
            detail: "Swift Testing cancelled this test. The JUnit testcase has no failure, error, or skipped element, so importers treat it as a pass."
        ),
    ])
}

@Test func missingXCTestFileIsAFindingOnlyWhenAsked() throws {
    let events = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.fastTest()/ProbeTests.swift:1:1","name":"fastTest()"}}
        {"kind":"event","payload":{"kind":"testEnded","messages":[{"symbol":"pass","text":"passed"}],"testID":"ProbeTests.fastTest()/ProbeTests.swift:1:1"}}
        """
    let xml = """
        <testsuites><testsuite tests="1"><testcase classname="ProbeTests" name="fastTest()" /></testsuite></testsuites>
        """
    let quiet = try joinRun(events: events, swiftTestingXML: xml)
    #expect(quiet.findings.isEmpty)
    let asked = try joinRun(events: events, swiftTestingXML: xml, expectXCTest: true)
    #expect(asked.findings.map(\.code) == ["xctest-junit-missing"])
}

@Test func xctestCasesStayOnTheirOwnFramework() throws {
    let events = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.fastTest()/ProbeTests.swift:1:1","name":"fastTest()"}}
        {"kind":"event","payload":{"kind":"testEnded","messages":[{"symbol":"pass","text":"passed"}],"testID":"ProbeTests.fastTest()/ProbeTests.swift:1:1"}}
        """
    let swiftXML = """
        <testsuites><testsuite tests="1"><testcase classname="ProbeTests" name="fastTest()" /></testsuite></testsuites>
        """
    let xctestXML = """
        <testsuites><testsuite tests="1"><testcase classname="ProbeTests" name="testFast" time="2.5" /></testsuite></testsuites>
        """
    let run = try joinRun(events: events, swiftTestingXML: swiftXML, xctestXML: xctestXML)
    let xctest = try #require(run.records.first { $0.framework == .xctest })
    #expect(xctest.id == "ProbeTests.testFast")
    #expect(xctest.duration == 2.5)
    let query = try parseQuery("framework:xctest duration:>2")
    #expect(run.records.filter(query.matches).map(\.id) == ["ProbeTests.testFast"])
}

private func fixture(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try String(contentsOf: url, encoding: .utf8)
}
