//
//  EffectsStudioMetalCodeEditorView.swift
//  Hypnograph
//

import SwiftUI
import AppKit

struct MetalCodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: String?

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MetalCodeEditorView
        weak var textView: NSTextView?

        init(parent: MetalCodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.black.withAlphaComponent(0.20)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.string = text

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView ?? (nsView.documentView as? NSTextView) else { return }
        context.coordinator.textView = textView

        if textView.string != text {
            textView.string = text
        }

        if let insertion = insertionRequest {
            let selected = textView.selectedRange()
            if let storage = textView.textStorage {
                storage.replaceCharacters(in: selected, with: insertion)
                textView.setSelectedRange(NSRange(location: selected.location + (insertion as NSString).length, length: 0))
                textView.didChangeText()
            } else {
                textView.insertText(insertion, replacementRange: selected)
            }

            DispatchQueue.main.async {
                insertionRequest = nil
            }
        }
    }
}
