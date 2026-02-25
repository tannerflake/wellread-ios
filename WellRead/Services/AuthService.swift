//
//  AuthService.swift
//  WellRead
//
//  Firebase Auth: state listener, Apple/Google sign-in, sign-out.
//

import Foundation
import SwiftUI
import FirebaseCore
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import GoogleSignIn

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var firebaseUser: FirebaseAuth.User?
    @Published private(set) var isLoading = true
    @Published var authError: String?

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private let userRepo: UserRepository

    init(userRepository: UserRepository = UserRepository()) {
        self.userRepo = userRepository
        self.firebaseUser = Auth.auth().currentUser
        isLoading = true
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.firebaseUser = user
                self?.isLoading = false
                if let uid = user?.uid {
                    await self?.userRepo.ensureUserDocument(uid: uid)
                }
            }
        }
    }

    deinit {
        if let handle = authStateListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Apple Sign-In (nonce required)

    /// Call from SignInWithAppleButton onRequest: configures nonce and scopes on the request.
    func makeAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        authError = nil
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let idTokenData = appleIDCredential.identityToken,
                  let idTokenString = String(data: idTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                authError = "Apple sign-in: missing token or nonce."
                return
            }
            currentNonce = nil
            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            do {
                _ = try await Auth.auth().signIn(with: credential)
            } catch {
                authError = error.localizedDescription
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                authError = error.localizedDescription
            }
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle(presentingViewController: UIViewController) async {
        authError = nil
        let clientID = FirebaseApp.app()?.options.clientID
            ?? Self.clientIDFromGoogleServicePlist()
        guard let clientID else {
            authError = "Google Sign-In needs CLIENT_ID. In Firebase Console, re-download GoogleService-Info.plist for your iOS app (with Google Sign-In enabled)."
            return
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: nil)
            guard let idToken = result.user.idToken?.tokenString else {
                authError = "Google sign-in: no ID token."
                return
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            _ = try await Auth.auth().signIn(with: credential)
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Sign Out

    func signOut() {
        authError = nil
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return randomBytes.map { byte in String(charset[Int(byte) % charset.count]) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Reads CLIENT_ID from Firebase config plist in the app bundle (for Google Sign-In).
    /// Checks GoogleService-Info.plist first, then WellRead Firebase Service Info.plist.
    private static func clientIDFromGoogleServicePlist() -> String? {
        let names = ["GoogleService-Info", "WellRead Firebase Service Info"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
                  let plist = NSDictionary(contentsOf: url) as? [String: Any],
                  let clientID = plist["CLIENT_ID"] as? String else { continue }
            return clientID
        }
        return nil
    }
}
