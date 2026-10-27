import Testing
import TestJoinCore

@Test func termsAreAND() throws {
    let query = try parseQuery("tag:camera AND stream:cancelled duration:>0.5")
    let hit = TestRecord(
        id: "ProbeTests.cancelledTest()",
        name: "cancelledTest()",
        tags: ["camera"],
        duration: 1,
        streamStatus: .cancelled,
        framework: .swiftTesting
    )
    let miss = TestRecord(
        id: "ProbeTests.fastTest()",
        name: "fastTest()",
        tags: ["camera"],
        duration: 1,
        streamStatus: .passed,
        framework: .swiftTesting
    )
    #expect(query.matches(hit))
    #expect(!query.matches(miss))
}

@Test func durationBoundaryIsExclusiveForGreaterThan() throws {
    let query = try parseQuery("duration:>2")
    let two = TestRecord(id: "a", name: "a", duration: 2, framework: .swiftTesting)
    let above = TestRecord(id: "b", name: "b", duration: 2.01, framework: .swiftTesting)
    #expect(!query.matches(two))
    #expect(query.matches(above))
    let inclusive = try parseQuery("duration:>=2")
    #expect(inclusive.matches(two))
}

@Test func missingDurationDoesNotMatch() throws {
    let query = try parseQuery("duration:>0")
    let record = TestRecord(id: "a", name: "a", framework: .swiftTesting)
    #expect(!query.matches(record))
}

@Test func tagNoneMeansUntagged() throws {
    let query = try parseQuery("tag:none")
    let bare = TestRecord(id: "a", name: "a", framework: .swiftTesting)
    let tagged = TestRecord(id: "b", name: "b", tags: ["camera"], framework: .swiftTesting)
    #expect(query.matches(bare))
    #expect(!query.matches(tagged))
}

@Test func textMatchesDisplayNameIgnoringCase() throws {
    let query = try parseQuery("camera")
    let record = TestRecord(
        id: "ProbeTests.cancelledTest()",
        name: "cancelledTest()",
        displayName: "Cancels when the Camera is missing",
        framework: .swiftTesting
    )
    #expect(query.matches(record))
}

@Test func xmlAndStreamAreDifferentFields() throws {
    let query = try parseQuery("xml:passed AND stream:cancelled")
    let hidden = TestRecord(
        id: "a",
        name: "a",
        streamStatus: .cancelled,
        xmlStatus: .passed,
        framework: .swiftTesting
    )
    let realPass = TestRecord(
        id: "b",
        name: "b",
        streamStatus: .passed,
        xmlStatus: .passed,
        framework: .swiftTesting
    )
    #expect(query.matches(hidden))
    #expect(!query.matches(realPass))
}

@Test func unknownFieldIsRejected() {
    #expect(throws: QueryError.unknownField("nope")) {
        try parseQuery("nope:1")
    }
}

@Test func emptyQueryIsRejected() {
    #expect(throws: QueryError.empty) {
        try parseQuery("   ")
    }
}

@Test func badDurationIsRejected() {
    #expect(throws: QueryError.badDuration(">nope")) {
        try parseQuery("duration:>nope")
    }
}
