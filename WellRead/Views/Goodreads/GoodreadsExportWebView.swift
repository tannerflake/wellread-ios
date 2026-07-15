//
//  GoodreadsExportWebView.swift
//  WellRead
//
//  Embedded browser for the Goodreads export page. Three jobs:
//  1. Keep navigation inside Spine — goodreads.com registers a catch-all
//     universal link, so opening the page externally hands off to the Goodreads
//     app (where the CSV can't be downloaded). Universal links never trigger
//     from an embedded web view.
//  2. Intercept the library-export CSV download via WKDownloadDelegate and feed
//     the parsed rows straight back to the import wizard — no Files app, no
//     upload step.
//  3. Guide the two-visit dance: Goodreads bounces an unauthenticated visit to
//     its login page and then strands the user on the homepage (not back on the
//     export page), so the wizard opens this view twice — once in `.login` mode
//     ("sign in, then tap I'm logged in") and once in `.export` mode. Same URL
//     both times.
//

import SwiftUI
import WebKit

struct GoodreadsExportWebView: View {
    /// Which step of the two-visit import flow this browser visit is for.
    enum Mode {
        case login
        case export
    }

    var mode: Mode = .export
    /// Login mode only: the user tapped "I'm logged in" — the wizard advances
    /// to the export step.
    var onLoggedIn: () -> Void = {}
    /// Called with parsed rows when the user's export CSV is captured.
    let onRows: ([GoodreadsRow]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isDownloading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBanner
                GoodreadsExportWebViewRepresentable(
                    isDownloading: $isDownloading,
                    errorMessage: $errorMessage,
                    onRows: onRows
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle(mode == .login ? "Log in to Goodreads" : "Goodreads export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .login ? "Cancel" : "Close") { dismiss() }
                        .foregroundStyle(mode == .login ? Theme.textTertiary : Theme.accent)
                }
                if mode == .login {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onLoggedIn()
                        } label: {
                            Text("I’m logged in")
                                .font(Theme.callout())
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isDownloading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("Grabbing your export…")
                        .font(Theme.callout())
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                }
            } else if let errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.magentaPunch)
                    Text(errorMessage)
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(SpinesGlyphs.caps(mode == .login ? "Step 1 of 2" : "Step 2 of 2"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.chromeTeal)
                Text(mode == .login
                     ? "Sign in to Goodreads, then tap “I’m logged in” at the top. Already signed in? Tap it now."
                     : "Tap “Export Library”, then tap the “Your export from…” link when it appears — SPINE takes it from there.")
                    .font(Theme.callout())
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.chromeTeal.opacity(0.35))
                .frame(height: Theme.chromeHairline)
        }
    }
}

// MARK: - WKWebView wrapper

private struct GoodreadsExportWebViewRepresentable: UIViewRepresentable {
    @Binding var isDownloading: Bool
    @Binding var errorMessage: String?
    let onRows: ([GoodreadsRow]) -> Void

    private static let exportPageURL = URL(string: "https://www.goodreads.com/review/import")!

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Default (persistent) store so the Goodreads login survives between imports.
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: Self.exportPageURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        private let parent: GoodreadsExportWebViewRepresentable
        private var downloadDestination: URL?

        init(_ parent: GoodreadsExportWebViewRepresentable) {
            self.parent = parent
        }

        // Login providers sometimes open target=_blank windows — load them in place instead.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let mime = navigationResponse.response.mimeType?.lowercased() ?? ""
            let filename = navigationResponse.response.suggestedFilename?.lowercased() ?? ""
            let looksLikeCSV = mime.contains("csv") || filename.hasSuffix(".csv")
            if looksLikeCSV || !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
            parent.isDownloading = true
            parent.errorMessage = nil
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
            parent.isDownloading = true
            parent.errorMessage = nil
        }

        // MARK: WKDownloadDelegate

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("goodreads-export-\(UUID().uuidString).csv")
            downloadDestination = url
            completionHandler(url)
        }

        func downloadDidFinish(_ download: WKDownload) {
            parent.isDownloading = false
            guard let url = downloadDestination, let data = try? Data(contentsOf: url) else {
                parent.errorMessage = "Couldn't read the export. Tap the export link again."
                return
            }
            defer { try? FileManager.default.removeItem(at: url) }
            downloadDestination = nil
            let rows = GoodreadsCSVParser.parse(data: data)
            if rows.isEmpty {
                parent.errorMessage = "That file didn't look like a Goodreads export. Tap the “Your export from…” link, not another download."
            } else {
                parent.onRows(rows)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            parent.isDownloading = false
            parent.errorMessage = "Download failed. Check your connection and tap the export link again."
        }
    }
}
