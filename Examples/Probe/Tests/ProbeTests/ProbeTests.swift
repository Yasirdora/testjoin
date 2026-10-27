import Testing

extension Tag {
    @Tag static var camera: Self
}

struct ProbeTests {
    @Test func passes() {
        #expect(1 + 1 == 2)
    }

    @Test func cancelsItself() throws {
        try Test.cancel("Needs a camera")
    }

    @Test(.tags(.camera)) func taggedPass() {
        #expect("camera".isEmpty == false)
    }
}
