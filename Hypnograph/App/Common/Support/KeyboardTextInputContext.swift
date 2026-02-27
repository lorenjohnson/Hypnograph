import AppKit

enum KeyboardTextInputContext {
    static func isTyping(in window: NSWindow?) -> Bool {
        guard let window, let responder = window.firstResponder else { return false }
        guard let textView = responder as? NSTextView else { return false }
        return textView.isEditable
    }

    static func isTypingInKeyOrMainWindow() -> Bool {
        if isTyping(in: NSApp.keyWindow) {
            return true
        }
        return isTyping(in: NSApp.mainWindow)
    }
}
