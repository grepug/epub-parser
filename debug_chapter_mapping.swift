#!/usr/bin/env swift

import Foundation

// Quick debug script to examine EPUB structure
let epubPath = "/Users/kai/Downloads/Atomic Habits (James Clear) (Z-Library).epub"

if FileManager.default.fileExists(atPath: epubPath) {
    print("Found EPUB at: \(epubPath)")

    // Simple ZIP signature check
    if let data = try? Data(contentsOf: URL(fileURLWithPath: epubPath)) {
        let signature = data.prefix(4)
        let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])
        print("Valid ZIP signature: \(signature == zipSignature)")
    }
} else {
    print("EPUB not found at expected path")
}
