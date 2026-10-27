import Testing
@testable import TestJoinCore

@Test func flatEventIDMatchesJUnitClassname() {
    let id = streamIdentity(
        eventID: "ProbeTests.cancelledTest()/ProbeTests.swift:27:2",
        functionName: "cancelledTest()"
    )
    #expect(id == "ProbeTests.cancelledTest()")
    #expect(id == junitIdentity(classname: "ProbeTests", name: "cancelledTest()"))
}

@Test func nestedEventIDUsesDotsLikeJUnit() {
    let id = streamIdentity(
        eventID: "ProbeTests.Outer/Inner/nested()/ProbeTests.swift:61:6",
        functionName: "nested()"
    )
    #expect(id == "ProbeTests.Outer.Inner.nested()")
    #expect(id == junitIdentity(classname: "ProbeTests.Outer.Inner", name: "nested()"))
}

@Test func sourceLocationSegmentIsNotPartOfTheName() {
    let id = streamIdentity(
        eventID: "Module.suiteTest()/Module.swift:4:1",
        functionName: "suiteTest()"
    )
    #expect(!id.contains(".swift"))
}
