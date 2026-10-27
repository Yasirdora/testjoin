public enum Framework: String, Equatable, Sendable {
    case swiftTesting = "swift-testing"
    case xctest = "xctest"
}

public enum StreamStatus: String, Equatable, Sendable {
    case passed
    case failed
    case skipped
    case cancelled
}

public enum XMLStatus: String, Equatable, Sendable {
    case passed
    case failed
    case skipped
    case error
}

public struct SourceLocation: Equatable, Sendable {
    public var filePath: String
    public var line: Int
    public var column: Int

    public init(filePath: String, line: Int, column: Int) {
        self.filePath = filePath
        self.line = line
        self.column = column
    }
}

public struct Bug: Equatable, Sendable {
    public var id: String?
    public var url: String?
    public var title: String?

    public init(id: String? = nil, url: String? = nil, title: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
    }
}

public struct TestRecord: Equatable, Sendable {
    public var id: String
    public var streamID: String?
    public var name: String
    public var displayName: String?
    public var suite: String?
    public var source: SourceLocation?
    public var tags: [String]
    public var bugs: [Bug]
    public var timeLimit: Double?
    public var isParameterized: Bool
    public var duration: Double?
    public var streamStatus: StreamStatus?
    public var xmlStatus: XMLStatus?
    public var xmlFile: String?
    public var framework: Framework

    public init(
        id: String,
        streamID: String? = nil,
        name: String,
        displayName: String? = nil,
        suite: String? = nil,
        source: SourceLocation? = nil,
        tags: [String] = [],
        bugs: [Bug] = [],
        timeLimit: Double? = nil,
        isParameterized: Bool = false,
        duration: Double? = nil,
        streamStatus: StreamStatus? = nil,
        xmlStatus: XMLStatus? = nil,
        xmlFile: String? = nil,
        framework: Framework
    ) {
        self.id = id
        self.streamID = streamID
        self.name = name
        self.displayName = displayName
        self.suite = suite
        self.source = source
        self.tags = tags
        self.bugs = bugs
        self.timeLimit = timeLimit
        self.isParameterized = isParameterized
        self.duration = duration
        self.streamStatus = streamStatus
        self.xmlStatus = xmlStatus
        self.xmlFile = xmlFile
        self.framework = framework
    }
}
