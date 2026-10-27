# testjoin

`testjoin` reads one Swift Testing run from two places and lets you query the difference.

The JSON Lines event stream is the record Swift Testing documents for tools. JUnit XML is the record most CI importers store. Those files do not carry the same facts. A test cancelled with `Test.cancel(_:)` can be a bare `<testcase>` with no `<failure>`, `<error>`, or `<skipped>` element. Importers treat that as a pass. `swift test --xunit-output` also writes the XCTest file only when `--parallel` is set, so a mixed suite can upload a report that dropped XCTest.

This is a search tool for one finished run. It does not run tests.

## Requirements

Swift 6.2 or later. No package dependencies. Checked with Swift 6.4 (`swift test --help` on that toolchain lists `--xunit-output` and `--parallel`, and does not list an event-stream flag).

## Build

```sh
swift test
swift run testjoin --help
```

## Use

```sh
swift run testjoin search \
  --events events.jsonl \
  --swift-testing-xml results-swift-testing.xml \
  'xml:passed AND stream:cancelled'

swift run testjoin audit \
  --events events.jsonl \
  --swift-testing-xml results-swift-testing.xml \
  --expect-xctest
```

`audit` exits 0 when the files agree and 1 when they do not. A bad invocation exits 2.

The event stream is the JSON Lines file written when the built test executable is passed `--event-stream-output-path`. The schema is Swift Testing's `Documentation/ABI/JSON.md`. `swift test` itself does not expose that flag. JUnit comes from `swift test --xunit-output`. Swift Testing results go to `<name>-swift-testing.xml`. XCTest results go to `<name>.xml` only with `--parallel`.

The checked-in fixture is synthetic. It follows that schema, including a cancelled test written as a passing JUnit testcase:

```sh
swift run testjoin search \
  --events Tests/TestJoinCoreTests/Fixtures/cancel-as-pass.events.jsonl \
  --swift-testing-xml Tests/TestJoinCoreTests/Fixtures/cancel-as-pass.swift-testing.xml \
  'tag:camera AND xml:passed AND stream:cancelled'
```

```
ProbeTests.cancelledTest()  stream=cancelled  xml=passed  tags=camera  duration=0.001s
```

## Query

Every term is AND. The word `AND` is optional.

| Term | Matches |
| --- | --- |
| `tag:camera` | that tag, exact |
| `tag:none` | no tags |
| `status:cancelled` | event-stream status: `passed`, `failed`, `skipped`, `cancelled` |
| `stream:cancelled` | same as `status` |
| `xml:passed` | JUnit status: `passed`, `failed`, `skipped`, `error` |
| `bug:12345` | bug id, or a url or title containing the text |
| `duration:>2` | also `>=`, `<`, `<=`, or a bare number |
| `framework:xctest` | `swift-testing` or `xctest` |
| `camera` | case-insensitive text on id, name, display name, or suite |

`status` is the event stream. A JUnit pass is `xml:passed`, not `status:passed`.

## Audit

- `junit-records-cancel-as-pass` — the stream recorded `testCancelled` or `testCaseCancelled`, and the JUnit testcase has no failure, error, or skipped element.
- `junit-omits-cancelled-test` — the stream recorded a cancellation and the JUnit file has other cases but not this one.
- `junit-reports-no-tests` — the JUnit file has no cases while the stream recorded tests. One finding, not one per test.
- `xctest-junit-missing` — `--expect-xctest` was set and no `--xctest-xml` file was given.

A skipped JUnit testcase is not reported. A warning issue is not a failure. Unknown event-stream kinds are ignored, which is what the ABI says to do.

## What this is not

Peekie, xcparse, XCResultKit, and Cachi read `.xcresult` bundles. testjoin does not. swift-index searches source. `swift test --filter` selects tests before they run. testjoin queries one finished run.

It does not fix Swift Testing, rewrite XML, scan source, or read the compiler's test-content section.

## Join key

Swift Testing ids look like `ProbeTests.cancelledTest()/ProbeTests.swift:27:2` and `ProbeTests.Outer/Inner/nested()/ProbeTests.swift:61:6`. JUnit writes `classname="ProbeTests"` / `classname="ProbeTests.Outer.Inner"` and `name="cancelledTest()"` / `name="nested()"`. The key is classname, a dot, and the test name. Function names that contain `/` are not handled.
