//
//  EffectDropDelegate.swift
//  Hypnograph
//

import SwiftUI

struct EffectDropDelegate: DropDelegate {
    let currentIndex: Int
    @Binding var draggingIndex: Int?
    let onReorder: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let fromIndex = draggingIndex, fromIndex != currentIndex else { return }
        onReorder(fromIndex, currentIndex)
        draggingIndex = currentIndex
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // No action needed
    }
}
