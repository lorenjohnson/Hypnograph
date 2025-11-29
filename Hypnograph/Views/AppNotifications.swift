//
//  AppNotifications.swift
//  Hypnograph
//
//  Unified notification system - in-app overlay + optional system notifications.
//  Works on both macOS and iOS via UserNotifications framework.
//

import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Notification Item

struct NotificationItem: Identifiable {
    let id = UUID()
    let message: String
    let flash: Bool
}

// MARK: - AppNotifications

/// Unified notification manager for in-app and system notifications.
/// - Foreground: shows in-app overlay (stacked, with dismiss button)
/// - Background: sends system notification (if authorized)
final class AppNotifications: ObservableObject {
    static let shared = AppNotifications()

    // MARK: - In-app overlay state

    @Published private(set) var notifications: [NotificationItem] = []

    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - System notification state

    private(set) var systemNotificationsAuthorized: Bool = false

    private init() {
        checkSystemNotificationAuthorization()
    }

    // MARK: - App state

    private var isAppActive: Bool {
        #if os(macOS)
        return NSApp.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }

    // MARK: - Show notification

    /// Show a notification. Automatically chooses delivery method:
    /// - If app is active/foreground: shows in-app overlay
    /// - If app is in background: sends system notification (if authorized)
    /// - Parameters:
    ///   - message: The message to display
    ///   - flash: If true, auto-dismiss after duration. If false (default), requires manual dismiss.
    ///   - duration: How long to show if flash is true (default 2 seconds)
    func show(_ message: String, flash: Bool = false, duration: TimeInterval = 2.0) {
        if isAppActive {
            showInApp(message, flash: flash, duration: duration)
        } else {
            sendSystemNotification(message)
        }
    }

    // MARK: - In-app overlay

    private func showInApp(_ message: String, flash: Bool, duration: TimeInterval) {
        let item = NotificationItem(message: message, flash: flash)

        Task { @MainActor in
            withAnimation(.easeIn(duration: 0.15)) {
                notifications.append(item)
            }
        }

        // Schedule auto-dismiss if flash
        if flash {
            dismissTasks[item.id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.dismiss(id: item.id)
            }
        }
    }

    /// Dismiss a specific notification by ID.
    func dismiss(id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.15)) {
                notifications.removeAll { $0.id == id }
            }
        }
    }

    /// Dismiss all notifications.
    func dismissAll() {
        for (id, task) in dismissTasks {
            task.cancel()
            dismissTasks.removeValue(forKey: id)
        }
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.15)) {
                notifications.removeAll()
            }
        }
    }

    // MARK: - System notifications

    /// Request authorization for system notifications.
    func requestSystemNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                self.systemNotificationsAuthorized = granted
                if let error = error {
                    print("AppNotifications: authorization error - \(error)")
                } else {
                    print("AppNotifications: system notifications \(granted ? "authorized" : "denied")")
                }
            }
        }
    }

    private func checkSystemNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.systemNotificationsAuthorized = (settings.authorizationStatus == .authorized)
            }
        }
    }

    private func sendSystemNotification(_ message: String) {
        guard systemNotificationsAuthorized else {
            print("AppNotifications: system notifications not authorized, skipping")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Hypnograph"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("AppNotifications: failed to send system notification - \(error)")
            }
        }
    }

    // MARK: - Static convenience

    static func show(_ message: String, flash: Bool = false, duration: TimeInterval = 2.0) {
        shared.show(message, flash: flash, duration: duration)
    }

    static func requestAuthorization() {
        shared.requestSystemNotificationAuthorization()
    }
}

// MARK: - AppNotificationOverlay

/// The in-app notification overlay view - shows stacked notifications.
struct AppNotificationOverlay: View {
    @ObservedObject var manager: AppNotifications

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(manager.notifications) { item in
                NotificationBubble(item: item) {
                    manager.dismiss(id: item.id)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

/// A single notification bubble with dismiss button.
private struct NotificationBubble: View {
    let item: NotificationItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(item.message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .background(
            Color.black.opacity(0.75)
                .cornerRadius(10)
        )
    }
}

// MARK: - View Extension

extension View {
    /// Adds the app notification overlay to the view (bottom right corner).
    func appNotifications(manager: AppNotifications = .shared) -> some View {
        self.overlay(alignment: .bottomTrailing) {
            AppNotificationOverlay(manager: manager)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
        }
    }
}

