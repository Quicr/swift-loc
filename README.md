# MoqLoc

Swift implementation of [draft-mzanaty-moq-loc](https://datatracker.ietf.org/doc/draft-mzanaty-moq-loc/).

## Using in your project

Add MoqLoc to your project as a dependency, e.g:

```swift
// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MyPackage",
    products: [
        .library(
            name: "MyPackage",
            targets: ["MyPackage"])
    ],
    dependencies: [
        .package(url: "https://github.com/Quicr/swift-loc.git", from: "main"),
    ],
    targets: [
        .target(
            name: "MyPackage",
            dependencies: [
                .product(name: "MoqLoc", package: "MoqLoc")
            ],
        )
    ]
)
```

You can make and consume a LOC like:

```swift
import Foundation
import MoqLoc
let now = Date.now
let header = LowOverheadContainer.Header(timestamp: now,
                                            sequenceNumber: 101)
let payload = Data([1, 2, 3, 4])
let loc = LowOverheadContainer(header: header,
                                payload: [payload])

// Encode.
var buffer = Data(count: loc.getRequiredBytes())
_ = try buffer.withUnsafeMutableBytes {
    try loc.serialize(into: $0)
}

// Decode.
try buffer.withUnsafeBytes {
    let decoded = try LowOverheadContainer(encoded: $0, noCopy: true)
}
```

## Development

Build and test using `swift` or `make`.
