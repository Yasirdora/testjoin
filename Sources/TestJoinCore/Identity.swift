// Swift Testing test ids look like
// `ProbeTests.cancelledTest()/ProbeTests.swift:27:2` or
// `ProbeTests.Outer/Inner/nested()/ProbeTests.swift:61:6`.
// JUnit writes the same tests as classname `ProbeTests` / `ProbeTests.Outer.Inner`
// and name `cancelledTest()` / `nested()`. The join key is classname + "." + name.
func streamIdentity(eventID: String, functionName: String) -> String {
    let parts = eventID.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let body = parts.filter { !isSourceLocation($0) }
    guard let leaf = body.last else { return functionName }
    let suite = body.dropLast().joined(separator: ".")
    if suite.isEmpty { return leaf }
    return suite + "." + leaf
}

func junitIdentity(classname: String, name: String) -> String {
    if classname.isEmpty { return name }
    return classname + "." + name
}

private func isSourceLocation(_ part: String) -> Bool {
    guard let range = part.range(of: ".swift:") else { return false }
    let rest = part[range.upperBound...]
    let bits = rest.split(separator: ":", omittingEmptySubsequences: false)
    guard bits.count == 2 else { return false }
    return bits.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
}
