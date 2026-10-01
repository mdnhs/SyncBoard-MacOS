//
//  GoogleDriveConfig.swift
//  SyncBoard
//

import Foundation

/// Fill in `clientID` with the OAuth 2.0 Client ID from your Google Cloud
/// Console project (APIs & Services > Credentials). Create it as an "iOS"
/// application type — that gives a client-secret-free installed-app flow
/// that works fine for a native macOS app too, via the reversed-client-id
/// custom URL scheme computed below.
///
/// After filling this in, update the `CFBundleURLTypes` entry in the
/// SyncBoard target's Info.plist so its URL scheme matches
/// `GoogleDriveConfig.redirectURLScheme` exactly — otherwise the OAuth
/// callback has nowhere to land.
///
/// `clientSecret` only needs filling in if you created a "Desktop app"
/// credential instead (Google issues a secret for that type). Leave it
/// empty for an "iOS" credential.
enum GoogleDriveConfig {
    static let clientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    static let clientSecret = ""

    /// `drive.appdata` keeps the synced file in a hidden, app-only area of
    /// Drive (not visible in the user's regular Drive UI) and only needs
    /// this low-sensitivity scope, which doesn't require Google's full
    /// OAuth verification review before shipping. `openid`/`email` let us
    /// show which account is connected.
    static let scope = "https://www.googleapis.com/auth/drive.appdata openid email"

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!

    private static var clientIDPrefix: String {
        clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    /// Google's convention for installed-app redirects: the client ID's
    /// unique prefix, dot-segments reversed, as a custom URL scheme.
    static var redirectURLScheme: String {
        "com.googleusercontent.apps.\(clientIDPrefix)"
    }

    static var redirectURI: String {
        "\(redirectURLScheme):/oauth2redirect"
    }

    static var isConfigured: Bool {
        !clientID.contains("YOUR_CLIENT_ID")
    }
}
