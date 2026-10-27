import Foundation

public struct JUnitCase: Equatable, Sendable {
    public var classname: String
    public var name: String
    public var time: Double?
    public var status: XMLStatus

    public init(classname: String, name: String, time: Double?, status: XMLStatus) {
        self.classname = classname
        self.name = name
        self.time = time
        self.status = status
    }
}

public struct JUnitDocument: Equatable, Sendable {
    public var cases: [JUnitCase]
    public var reportedTestCount: Int?

    public init(cases: [JUnitCase], reportedTestCount: Int?) {
        self.cases = cases
        self.reportedTestCount = reportedTestCount
    }
}

public enum JUnitXMLError: Error, Equatable, CustomStringConvertible {
    case notXML(String)

    public var description: String {
        switch self {
        case .notXML(let message):
            return "JUnit XML could not be parsed: \(message)"
        }
    }
}

public func parseJUnitXML(_ text: String) throws -> JUnitDocument {
    let parser = XMLParser(data: Data(text.utf8))
    let sax = JUnitSAX()
    parser.delegate = sax
    guard parser.parse() else {
        throw JUnitXMLError.notXML(parser.parserError?.localizedDescription ?? "invalid XML")
    }
    let reported: Int? = sax.missingCount || sax.suiteCounts.isEmpty ? nil : sax.suiteCounts.reduce(0, +)
    return JUnitDocument(cases: sax.cases, reportedTestCount: reported)
}

private final class JUnitSAX: NSObject, XMLParserDelegate {
    var cases: [JUnitCase] = []
    var suiteCounts: [Int] = []
    var missingCount = false
    private var current: Partial?

    private struct Partial {
        var classname = ""
        var name = ""
        var time: Double?
        var failure = false
        var error = false
        var skipped = false
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "testsuite":
            if let raw = attributeDict["tests"], let count = Int(raw) {
                suiteCounts.append(count)
            } else {
                missingCount = true
            }
        case "testcase":
            var item = Partial()
            item.classname = attributeDict["classname"] ?? ""
            item.name = attributeDict["name"] ?? ""
            if let raw = attributeDict["time"] { item.time = Double(raw) }
            current = item
        case "failure":
            current?.failure = true
        case "error":
            current?.error = true
        case "skipped":
            current?.skipped = true
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "testcase", let item = current {
            let status: XMLStatus
            if item.error {
                status = .error
            } else if item.failure {
                status = .failed
            } else if item.skipped {
                status = .skipped
            } else {
                status = .passed
            }
            cases.append(JUnitCase(classname: item.classname, name: item.name, time: item.time, status: status))
            current = nil
        }
    }
}
