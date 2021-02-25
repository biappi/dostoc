// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "udis86",
    products: [
        .library(
            name: "udis86",
            targets: ["udis86"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "udis86",
            dependencies: [],
            cSettings: [
                .define("HAVE_STRING_H")
            ]
        )
    ]
)
