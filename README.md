# testjoin

`testjoin` joins one Swift Testing run to the JUnit XML a CI importer stores, then queries the difference.

`Test.cancel` is a cancellation in the event stream. On Swift 6.4 it is still a bare `<testcase>` with no `<failure>`, `<error>`, or `<skipped>` element, and importers store that as a pass. `swift test` for the example below exited 0. The event stream is the record that says the test was cancelled.

Use `audit` before uploading that JUnit file.

## Requirements

Swift 6.2 or later. No package dependencies.

The capture in this README was run with Apple Swift 6.4 (`swiftlang-6.4.0.34.1`) on macOS 27. The event stream from that run says Testing library 2084.

`swift test --help` on that toolchain lists `--xunit-output`, `--parallel`, and `--disable-xctest`. It does not list `--event-stream-output-path`. The `swift test` command accepts the flag anyway. `capture` passes it.

## Build

```sh
swift test
swift run testjoin --help
```

## Capture a package

`Examples/Probe` is a Swift Testing package with a passing test, a `Test.cancel`, and a tagged test.

```sh
swift run testjoin capture --package Examples/Probe --output /tmp/probe --audit
```

`capture` runs:

```sh
swift test --package-path Examples/Probe \
  --event-stream-output-path /tmp/probe/events.jsonl \
  --xunit-output /tmp/probe/results.xml \
  --disable-xctest
```

`--disable-xctest` makes Swift Testing write JUnit to the path you named. Without that flag, and without `--parallel`, `swift test` writes `<name>-swift-testing.xml` and does not create the path you passed. With `--parallel`, XCTest goes to `<name>.xml` and Swift Testing goes to `<name>-swift-testing.xml`. `capture --parallel` reads that pair.

On the toolchain above, `capture --audit` printed this and exited 1. `swift test` itself exited 0.

```
1 finding
junit-records-cancel-as-pass  ProbeTests.ProbeTests.cancelsItself()
  Swift Testing cancelled this test. The JUnit testcase has no failure, error, or skipped element, so importers treat it as a pass.
```

Query the files capture wrote:

```sh
swift run testjoin search \
  --events /tmp/probe/events.jsonl \
  --swift-testing-xml /tmp/probe/results.xml \
  'xml:passed AND stream:cancelled'
```

The saved copy of that run prints:

```
ProbeTests.ProbeTests.cancelsItself()  stream=cancelled  xml=passed  duration=0.000267s
```

A new capture reports the same finding. The duration is the length of that run. It is under a millisecond, so three decimal places would have printed `0.000s`.

`audit` exits 0 when the files agree and 1 when they do not. A bad invocation, or a capture that wrote no files, exits 2. If `swift test` exits non-zero and the files were still written, capture keeps those files and says so.

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

A second, synthetic fixture covers tags, a bug id, and a version-0 event mixed into the same stream:

```sh
swift run testjoin search \
  --events Tests/TestJoinCoreTests/Fixtures/cancel-as-pass.events.jsonl \
  --swift-testing-xml Tests/TestJoinCoreTests/Fixtures/cancel-as-pass.swift-testing.xml \
  'tag:camera AND xml:passed AND stream:cancelled'
```

```
ProbeTests.cancelledTest()  stream=cancelled  xml=passed  tags=camera  duration=0.001s
```

`Fixtures/swift64-probe.events.jsonl` and `Fixtures/swift64-probe.swift-testing.xml` are the `Examples/Probe` run measured above. Absolute paths in the event stream were rewritten to start at `Examples/Probe`. Nothing else in those two files was edited.

## Audit

- `junit-records-cancel-as-pass` — the stream recorded `testCancelled` or `testCaseCancelled`, and the JUnit testcase has no failure, error, or skipped element.
- `junit-omits-cancelled-test` — the stream recorded a cancellation and the JUnit file has other cases but not this one.
- `junit-reports-no-tests` — the JUnit file has no cases while the stream recorded tests. One finding, not one per test.
- `xctest-junit-missing` — `--expect-xctest` was set and no `--xctest-xml` file was given.

A skipped JUnit testcase is not reported. A warning issue is not a failure. Unknown event-stream kinds are ignored, which is what the ABI says to do.

## CI

GitHub Actions runs `swift test`, then `capture --audit` on `Examples/Probe`, on the `xcode-27` runner. The job fails if the package tests fail, or if capture cannot write files the parser can read. It does not fail when audit reports the cancel-as-pass finding. It does not fail if a later toolchain records the cancellation in JUnit and audit exits 0. The job does fail if the tagged example test is missing from search.

## What this is not

Peekie, xcparse, XCResultKit, and Cachi read `.xcresult` bundles. testjoin does not. swift-index searches source. `swift test --filter` selects tests before they run, and its tag filter is OR. testjoin queries one finished run, and every term is AND.

It does not fix Swift Testing, rewrite XML, scan source, or read the compiler's test-content section.

## Join key

A Swift 6.4 id looks like `ProbeTests.ProbeTests/cancelsItself()/ProbeTests.swift:12:6`. JUnit writes `classname="ProbeTests.ProbeTests"` and `name="cancelsItself()"`. The key drops a trailing `File.swift:line:col` segment and turns the remaining slashes into dots. Function names that contain `/` are not handled.
