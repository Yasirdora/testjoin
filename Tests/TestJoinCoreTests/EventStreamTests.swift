import Testing
import TestJoinCore

@Test func ignoresUnknownKindsAndReadsBothLocationSpellings() throws {
    let text = """
        {"kind":"_metadata","payload":{"name":"OS","value":"test"},"version":0}
        {"kind":"test","version":0,"payload":{"kind":"suite","id":"ProbeTests","name":"ProbeTests"}}
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.known()/File.swift:3:1","name":"known()","sourceLocation":{"_filePath":"File.swift","line":3,"column":1}}}
        {"kind":"future","payload":{"hello":true}}
        {"kind":"event","version":"6.4","payload":{"kind":"testStarted","instant":{"since1970":10},"testID":"ProbeTests.known()/File.swift:3:1"}}
        {"kind":"event","version":"6.4","payload":{"kind":"issueRecorded","issue":{"isFailure":false,"severity":"warning"},"messages":[{"symbol":"warning","text":"heads up"}],"testID":"ProbeTests.known()/File.swift:3:1"}}
        {"kind":"event","version":"6.4","payload":{"kind":"testEnded","instant":{"since1970":11},"messages":[{"symbol":"pass","text":"passed"}],"testID":"ProbeTests.known()/File.swift:3:1"}}
        """
    let records = try parseEventStream(text)
    #expect(records.count == 1)
    #expect(records[0].id == "ProbeTests.known()")
    #expect(records[0].source?.filePath == "File.swift")
    #expect(records[0].streamStatus == .passed)
    #expect(records[0].duration == 1)
}

@Test func cancelWinsOverLaterSkipSymbol() throws {
    let text = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.cancelledTest()/ProbeTests.swift:27:2","name":"cancelledTest()"}}
        {"kind":"event","payload":{"kind":"testEnded","instant":{"since1970":2},"messages":[{"symbol":"skip","text":"was cancelled"}],"testID":"ProbeTests.cancelledTest()/ProbeTests.swift:27:2"}}
        {"kind":"event","payload":{"kind":"testCancelled","instant":{"since1970":1},"testID":"ProbeTests.cancelledTest()/ProbeTests.swift:27:2"}}
        """
    let records = try parseEventStream(text)
    #expect(records[0].streamStatus == .cancelled)
}

@Test func oneCancelledCaseMarksTheFunction() throws {
    let text = """
        {"kind":"test","version":"6.4","payload":{"kind":"function","id":"ProbeTests.someCasesCancelled(value:)/ProbeTests.swift:32:2","name":"someCasesCancelled(value:)","isParameterized":true,"tags":["night"],"bugs":[{"id":"99","url":"https://example.test/99"}]}}
        {"kind":"event","payload":{"kind":"testCaseCancelled","testID":"ProbeTests.someCasesCancelled(value:)/ProbeTests.swift:32:2"}}
        {"kind":"event","payload":{"kind":"testEnded","messages":[{"symbol":"pass","text":"passed"}],"testID":"ProbeTests.someCasesCancelled(value:)/ProbeTests.swift:32:2"}}
        """
    let records = try parseEventStream(text)
    #expect(records[0].streamStatus == .cancelled)
    #expect(records[0].isParameterized)
    #expect(records[0].tags == ["night"])
    #expect(records[0].bugs == [Bug(id: "99", url: "https://example.test/99")])
}

@Test func missingIsFailureUsesFailSymbol() throws {
    let text = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.threeFailures()/ProbeTests.swift:12:2","name":"threeFailures()"}}
        {"kind":"event","version":0,"payload":{"kind":"issueRecorded","issue":{"isKnown":false},"messages":[{"symbol":"fail","text":"Expectation failed"}],"testID":"ProbeTests.threeFailures()/ProbeTests.swift:12:2"}}
        {"kind":"event","version":0,"payload":{"kind":"testEnded","messages":[{"symbol":"fail","text":"failed"}],"testID":"ProbeTests.threeFailures()/ProbeTests.swift:12:2"}}
        """
    let records = try parseEventStream(text)
    #expect(records[0].streamStatus == .failed)
}

@Test func nestedSuiteJoinsWithDots() throws {
    let text = """
        {"kind":"test","version":0,"payload":{"kind":"function","id":"ProbeTests.Outer/Inner/nested()/ProbeTests.swift:61:6","name":"nested()"}}
        {"kind":"event","payload":{"kind":"testSkipped","testID":"ProbeTests.Outer/Inner/nested()/ProbeTests.swift:61:6"}}
        """
    let records = try parseEventStream(text)
    #expect(records[0].id == "ProbeTests.Outer.Inner.nested()")
    #expect(records[0].suite == "ProbeTests.Outer.Inner")
    #expect(records[0].streamStatus == .skipped)
}

@Test func invalidLineNamesItsNumber() {
    #expect(throws: EventStreamError.invalidJSON(line: 2)) {
        try parseEventStream("{\"kind\":\"_metadata\"}\nnot json\n")
    }
}
