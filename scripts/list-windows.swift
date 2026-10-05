#!/usr/bin/env swift
// Prints DockShift's on-screen windows (layer and bounds) for debugging
// without needing Screen Recording access:  swift scripts/list-windows.swift
import CoreGraphics
import Foundation

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in list where (window["kCGWindowOwnerName"] as? String) == "DockShift" {
    let bounds = window["kCGWindowBounds"] as? [String: Any] ?? [:]
    print("layer=\(window["kCGWindowLayer"] ?? "?") bounds=\(bounds) alpha=\(window["kCGWindowAlpha"] ?? "?")")
}
print("main display: \(CGDisplayBounds(CGMainDisplayID()))")
