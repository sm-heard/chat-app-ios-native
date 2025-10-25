import Foundation
import UserNotifications
import SwiftUI
import UIKit

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private let tokenKey = "push_device_token"
    private let userKey = "push_user_id"

    private override init() {
        super.init()
        Task {
            let settings = await notificationCenter.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            registerForRemoteNotifications()
        case .denied:
            return
        case .notDetermined:
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
                authorizationStatus = granted ? .authorized : .denied
                if granted {
                    registerForRemoteNotifications()
                }
            } catch {
                authorizationStatus = .denied
            }
        @unknown default:
            return
        }
    }

    func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handleDeviceToken(_ deviceToken: Data, for userId: String) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        let lastToken = defaults.string(forKey: tokenKey)
        let lastUser = defaults.string(forKey: userKey)

        guard tokenString != lastToken || userId != lastUser else { return }

        Task {
            do {
                try await PushTokenService.shared.registerToken(userId: userId, deviceToken: tokenString, provider: "apn", providerName: AppConfig.pushProviderName)
                defaults.set(tokenString, forKey: tokenKey)
                defaults.set(userId, forKey: userKey)
            } catch {
                print("Push registration failed:", error)
            }
        }
    }

    func clearCachedToken() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: userKey)
    }
}
