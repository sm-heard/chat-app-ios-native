import Foundation

enum AppConfig {
    private static func value(for key: String) -> String? {
        if let override = ProcessInfo.processInfo.environment[key], !override.isEmpty {
            return override
        }
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: key) as? String, !infoValue.isEmpty {
            return infoValue
        }
        return nil
    }

    static var streamAPIKey: String {
        guard
            let value = value(for: "STREAM_API_KEY"),
            value != "YOUR_STREAM_API_KEY"
        else {
            fatalError("Set STREAM_API_KEY in Info.plist or as an environment variable before running the app.")
        }
        return value
    }

    static var tokenEndpoint: URL {
        guard
            let string = value(for: "TOKEN_ENDPOINT"),
            string != "https://YOUR-VERCEL-APP.vercel.app/api/stream/token",
            let url = URL(string: string),
            url.scheme?.hasPrefix("http") == true
        else {
            fatalError("Set TOKEN_ENDPOINT in Info.plist or as an environment variable before running the app.")
        }
        return url
    }

    static var pushProviderName: String? {
        value(for: "PUSH_PROVIDER_NAME")
    }
}
