import AppKit
import Foundation

extension NSColor {
    static var safeSidebarBackground: NSColor {
        if #available(macOS 11.0, *) {
            return .controlBackgroundColor
        } else {
            return .windowBackgroundColor
        }
    }
}
