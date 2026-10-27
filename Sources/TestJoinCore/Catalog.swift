public struct Finding: Equatable, Sendable {
    public var code: String
    public var testID: String?
    public var detail: String

    public init(code: String, testID: String?, detail: String) {
        self.code = code
        self.testID = testID
        self.detail = detail
    }
}

public struct JoinedRun: Equatable, Sendable {
    public var records: [TestRecord]
    public var findings: [Finding]

    public init(records: [TestRecord], findings: [Finding]) {
        self.records = records
        self.findings = findings
    }
}

public func joinRun(
    events: String,
    swiftTestingXML: String,
    xctestXML: String? = nil,
    expectXCTest: Bool = false
) throws -> JoinedRun {
    let stream = try parseEventStream(events)
    let swiftXML = try parseJUnitXML(swiftTestingXML)
    let xctest = try xctestXML.map { try parseJUnitXML($0) }
    let records = join(stream: stream, swiftXML: swiftXML, xctestXML: xctest)
    let findings = audit(
        records: records,
        swiftXML: swiftXML,
        xctestXML: xctest,
        expectXCTest: expectXCTest
    )
    return JoinedRun(records: records, findings: findings)
}

func join(stream: [TestRecord], swiftXML: JUnitDocument, xctestXML: JUnitDocument?) -> [TestRecord] {
    var rows: [String: TestRecord] = [:]
    var order: [String] = []

    func insert(_ record: TestRecord, key: String) {
        if rows[key] == nil { order.append(key) }
        rows[key] = record
    }

    for record in stream {
        insert(record, key: "swift-testing\u{0}" + record.id)
    }

    for item in swiftXML.cases {
        let id = junitIdentity(classname: item.classname, name: item.name)
        let key = "swift-testing\u{0}" + id
        if var existing = rows[key] {
            existing.xmlStatus = item.status
            existing.xmlFile = "swift-testing"
            if existing.duration == nil { existing.duration = item.time }
            rows[key] = existing
        } else {
            insert(
                TestRecord(
                    id: id,
                    name: item.name,
                    suite: item.classname.isEmpty ? nil : item.classname,
                    duration: item.time,
                    xmlStatus: item.status,
                    xmlFile: "swift-testing",
                    framework: .swiftTesting
                ),
                key: key
            )
        }
    }

    if let xctestXML {
        for item in xctestXML.cases {
            let id = junitIdentity(classname: item.classname, name: item.name)
            insert(
                TestRecord(
                    id: id,
                    name: item.name,
                    suite: item.classname.isEmpty ? nil : item.classname,
                    duration: item.time,
                    xmlStatus: item.status,
                    xmlFile: "xctest",
                    framework: .xctest
                ),
                key: "xctest\u{0}" + id
            )
        }
    }

    return order.compactMap { rows[$0] }
}

func audit(
    records: [TestRecord],
    swiftXML: JUnitDocument,
    xctestXML: JUnitDocument?,
    expectXCTest: Bool
) -> [Finding] {
    var findings: [Finding] = []
    let streamTests = records.filter { $0.framework == .swiftTesting && $0.streamID != nil }
    let xmlIsEmpty = swiftXML.cases.isEmpty
        && (swiftXML.reportedTestCount == nil || swiftXML.reportedTestCount == 0)

    if xmlIsEmpty && !streamTests.isEmpty {
        findings.append(
            Finding(
                code: "junit-reports-no-tests",
                testID: nil,
                detail: "The Swift Testing JUnit file has no test cases. The event stream recorded \(streamTests.count) \(streamTests.count == 1 ? "test" : "tests")."
            )
        )
    }

    if !xmlIsEmpty {
        for record in records where record.framework == .swiftTesting && record.streamStatus == .cancelled {
            switch record.xmlStatus {
            case .passed:
                findings.append(
                    Finding(
                        code: "junit-records-cancel-as-pass",
                        testID: record.id,
                        detail: "Swift Testing cancelled this test. The JUnit testcase has no failure, error, or skipped element, so importers treat it as a pass."
                    )
                )
            case nil:
                findings.append(
                    Finding(
                        code: "junit-omits-cancelled-test",
                        testID: record.id,
                        detail: "Swift Testing cancelled this test and the JUnit file has no testcase for it."
                    )
                )
            case .failed, .skipped, .error:
                break
            }
        }
    }

    if expectXCTest && xctestXML == nil {
        findings.append(
            Finding(
                code: "xctest-junit-missing",
                testID: nil,
                detail: "XCTest JUnit was expected and no file was provided. swift test writes that file only when --parallel is set."
            )
        )
    }

    return findings.sorted { lhs, rhs in
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        return (lhs.testID ?? "") < (rhs.testID ?? "")
    }
}
