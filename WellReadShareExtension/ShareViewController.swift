//
//  ShareViewController.swift
//  WellReadShareExtension
//
//  Receives shared Goodreads link (or file), saves it, shows a modal with "Open Spines" so the user can return to the app.
//

import UIKit
import UniformTypeIdentifiers
import Security

private let appGroupId = "group.com.wellread.app"
private let keychainService = "WellReadGoodreadsImport"
private let keychainAccount = "PendingURL"
private let wellReadImportURL = URL(string: "wellread://goodreads-import")!
private let sharedFileName = "incoming_goodreads.csv"
private let pendingImportURLFileName = "pending_import_url.txt"
private let pendingImportKey = "PendingGoodreadsImport"
private let pendingImportErrorKey = "PendingGoodreadsImportError"
private let pendingImportURLKey = "PendingGoodreadsImportURL"
private let keychainAccountCSVPasteboard = "PendingCSVFromPasteboard"
private let keychainAccountError = "PendingError"
private let pasteboardTypeCSV = "com.wellread.goodreads-csv"

final class ShareViewController: UIViewController {

    private let modalCard = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let openButton = UIButton(type: .system)

    private static func isGoodreadsCSV(_ data: Data) -> Bool {
        guard data.count > 10, let head = String(data: data.prefix(1024), encoding: .utf8) else { return false }
        return head.contains("Book Id") || head.contains("Title,")
    }

    /// If the string looks like a Goodreads export CSV URL (e.g. from Share in Goodreads app), return a URL. Accepts with or without https.
    private static func goodreadsExportURL(from string: String?) -> URL? {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        let lower = s.lowercased()
        guard lower.contains("goodreads.com") && (lower.contains("review_porter/export") || lower.contains("goodreads_export") || lower.contains(".csv")),
              let url = URL(string: s.hasPrefix("http") ? s : "https://\(s)") else { return nil }
        return url
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        setupModalCard()
        processInputItems()
    }

    private func setupModalCard() {
        modalCard.backgroundColor = UIColor.systemBackground
        modalCard.layer.cornerRadius = 16
        modalCard.clipsToBounds = true
        modalCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modalCard)

        titleLabel.text = "Import from Goodreads"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        modalCard.addSubview(titleLabel)

        messageLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 15, weight: .regular)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        modalCard.addSubview(messageLabel)

        openButton.setTitle("Open Spines", for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        openButton.addTarget(self, action: #selector(openThenFinish), for: .touchUpInside)
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.backgroundColor = .systemBlue
        openButton.setTitleColor(.white, for: .normal)
        openButton.layer.cornerRadius = 10
        modalCard.addSubview(openButton)

        NSLayoutConstraint.activate([
            modalCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modalCard.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            modalCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            modalCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: modalCard.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: modalCard.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: modalCard.trailingAnchor, constant: -20),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: modalCard.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: modalCard.trailingAnchor, constant: -20),
            openButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            openButton.leadingAnchor.constraint(equalTo: modalCard.leadingAnchor, constant: 20),
            openButton.trailingAnchor.constraint(equalTo: modalCard.trailingAnchor, constant: -20),
            openButton.heightAnchor.constraint(equalToConstant: 48),
            openButton.bottomAnchor.constraint(equalTo: modalCard.bottomAnchor, constant: -24),
        ])
        modalCard.alpha = 0
    }

    /// Show the modal with message and "Open Spines" button. Call on main thread after saving URL or error.
    private func showModal(message: String, linkReceived: Bool) {
        messageLabel.text = message
        modalCard.alpha = 1
    }

    @objc private func openThenFinish() {
        extensionContext?.open(wellReadImportURL) { [weak self] _ in
            DispatchQueue.main.async {
                self?.finish()
            }
        }
    }

    private func processInputItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            saveErrorAndShowModal(message: "No content was shared. Try sharing the Goodreads CSV file again.")
            return
        }
        for item in items {
            guard let attachments = item.attachments, !attachments.isEmpty else { continue }
            for provider in attachments {
                // Prefer URL (Goodreads often shares the export link as URL or plain text); then file/data.
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] url, _ in
                        guard let self = self, let link = url as? URL else { self?.saveErrorAndShowModal(message: "Couldn't read the link. Try sharing again from Goodreads."); return }
                        if link.isFileURL {
                            self.handleFileURL(link)
                        } else {
                            self.saveURLAndShowModal(link)
                        }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        guard let self = self else { self?.saveErrorAndShowModal(message: "Couldn't process the share."); return }
                        self.handleTextOrDataItem(item)
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { [weak self] payload, _ in
                        guard let self = self else { self?.saveErrorAndShowModal(message: "Couldn't process the share."); return }
                        if let data = payload as? Data {
                            self.handleCSVData(data)
                        } else if let url = payload as? URL {
                            if url.isFileURL { self.handleFileURL(url) } else { self.saveURLAndShowModal(url) }
                        } else {
                            self.saveErrorAndShowModal(message: "Couldn't read the shared content. Share the Goodreads export link or CSV file to Spines.")
                        }
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.commaSeparatedText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.commaSeparatedText.identifier, options: nil) { [weak self] item, _ in
                        guard let self = self else { self?.saveErrorAndShowModal(message: "Couldn't process the share."); return }
                        self.handleTextOrDataItem(item)
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] url, _ in
                        guard let self = self, let fileURL = url as? URL else { self?.saveErrorAndShowModal(message: "Couldn't read the file. Try sharing again from Files."); return }
                        self.handleFileURL(fileURL)
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.content.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.content.identifier, options: nil) { [weak self] payload, _ in
                        guard let self = self else { self?.saveErrorAndShowModal(message: "Couldn't process the share."); return }
                        if let data = payload as? Data {
                            self.handleCSVData(data)
                        } else if let url = payload as? URL {
                            if url.isFileURL { self.handleFileURL(url) } else { self.saveURLAndShowModal(url) }
                        } else {
                            self.saveErrorAndShowModal(message: "Couldn't read the shared content. Save the CSV to Files, then share that file to Spines.")
                        }
                    }
                    return
                }
                // Native app (e.g. Goodreads) may use a different UTI; try loading with the first registered type that we haven't tried.
                tryLoadWithRegisteredTypes(provider: provider)
                return
            }
        }
        saveErrorAndShowModal(message: "No file or link was received. In Goodreads, download your library CSV, save it to Files, then share that file to Spines.")
    }

    /// Try loading the item using the provider's registered type identifiers (for native app shares that use custom UTIs).
    private func tryLoadWithRegisteredTypes(provider: NSItemProvider) {
        let preferred = [UTType.url.identifier, "public.url", UTType.plainText.identifier, "public.text", UTType.data.identifier, UTType.commaSeparatedText.identifier, UTType.fileURL.identifier, "public.file-url", UTType.content.identifier, "public.data", "public.delimited-values-text", "public.comma-separated-values-text"]
        let registered = provider.registeredTypeIdentifiers
        for typeId in preferred {
            guard registered.contains(typeId), provider.hasItemConformingToTypeIdentifier(typeId) else { continue }
            loadItemFromProvider(provider, typeId: typeId)
            return
        }
        for typeId in registered {
            guard provider.hasItemConformingToTypeIdentifier(typeId) else { continue }
            loadItemFromProvider(provider, typeId: typeId)
            return
        }
        saveErrorAndShowModal(message: "No CSV file was received. Goodreads often shares a link, not the file. Download the CSV, save to Files, then share that file to Spines.")
    }

    private func loadItemFromProvider(_ provider: NSItemProvider, typeId: String) {
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] payload, _ in
            guard let self = self else { self?.saveErrorAndShowModal(message: "Couldn't process the share."); return }
            if let data = payload as? Data {
                self.handleCSVData(data)
            } else if let url = payload as? URL {
                if url.isFileURL { self.handleFileURL(url) } else { self.saveURLAndShowModal(url) }
            } else if let str = payload as? String {
                if let url = Self.goodreadsExportURL(from: str) {
                    self.saveURLAndShowModal(url)
                } else if let data = str.data(using: .utf8) {
                    self.handleCSVData(data)
                } else {
                    self.saveErrorAndShowModal(message: "Couldn't read the shared content. Share the Goodreads export link or CSV file to Spines.")
                }
            } else {
                self.saveErrorAndShowModal(message: "Couldn't read the shared content. Share the Goodreads export link or CSV file to Spines.")
            }
        }
    }

    private func handleTextOrDataItem(_ item: Any?) {
        if let data = item as? Data {
            handleCSVData(data)
            return
        }
        if let str = item as? String {
            if let url = Self.goodreadsExportURL(from: str) {
                saveURLAndShowModal(url)
                return
            }
            if let data = str.data(using: .utf8) {
                handleCSVData(data)
                return
            }
        }
        saveErrorAndShowModal(message: "Couldn't read the shared text. Make sure you're sharing the Goodreads export link or CSV.")
    }

    /// Handle file URL: read contents (in case copy fails due to sandbox). If CSV, save and show modal; else copy file and show modal.
    private func handleFileURL(_ fileURL: URL) {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL), Self.isGoodreadsCSV(data) else {
            copyToAppGroupAndShowModal(fileURL: fileURL)
            return
        }
        handleCSVData(data)
    }

    /// Save CSV data to app group or pasteboard, then show modal with "Open Spines".
    private func handleCSVData(_ data: Data) {
        guard Self.isGoodreadsCSV(data) else {
            saveErrorAndShowModal(message: "That didn't look like a Goodreads export. Download your library CSV from goodreads.com/review/import, then share the file to Spines.")
            return
        }
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let destURL = container.appendingPathComponent(sharedFileName)
            _ = try? FileManager.default.removeItem(at: destURL)
            do {
                try data.write(to: destURL)
                UserDefaults(suiteName: appGroupId)?.set(true, forKey: pendingImportKey)
                UserDefaults(suiteName: appGroupId)?.removeObject(forKey: pendingImportErrorKey)
                UserDefaults(suiteName: appGroupId)?.removeObject(forKey: pendingImportURLKey)
                UserDefaults(suiteName: appGroupId)?.synchronize()
                clearCSVPasteboardKeychainFlag()
                DispatchQueue.main.async { [weak self] in
                    self?.showModal(message: "Import ready. Tap Open Spines to continue.", linkReceived: true)
                }
                return
            } catch { }
        }
        UIPasteboard.general.setData(data, forPasteboardType: pasteboardTypeCSV)
        setKeychainCSVPasteboardFlag()
        DispatchQueue.main.async { [weak self] in
            self?.showModal(message: "Import ready. Tap Open Spines to continue.", linkReceived: true)
        }
    }

    private func setKeychainCSVPasteboardFlag() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccountCSVPasteboard
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data([1])
        SecItemAdd(add as CFDictionary, nil)
    }

    private func clearCSVPasteboardKeychainFlag() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccountCSVPasteboard
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func copyToAppGroupAndShowModal(fileURL: URL) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            saveErrorAndShowModal(message: "Couldn't save the file. Save the CSV to Files, then share that file to Spines.")
            return
        }
        let destURL = container.appendingPathComponent(sharedFileName)
        _ = try? FileManager.default.removeItem(at: destURL)
        do {
            if fileURL.startAccessingSecurityScopedResource() {
                defer { fileURL.stopAccessingSecurityScopedResource() }
            }
            try FileManager.default.copyItem(at: fileURL, to: destURL)
        } catch {
            saveErrorAndShowModal(message: "Couldn't read the file. Save the Goodreads CSV to Files, then share that file to Spines.")
            return
        }
        UserDefaults(suiteName: appGroupId)?.set(true, forKey: pendingImportKey)
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: pendingImportErrorKey)
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: pendingImportURLKey)
        UserDefaults(suiteName: appGroupId)?.synchronize()
        if let c = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            try? FileManager.default.removeItem(at: c.appendingPathComponent(pendingImportURLFileName))
        }
        DispatchQueue.main.async { [weak self] in
            self?.showModal(message: "Import ready. Tap Open Spines to continue.", linkReceived: true)
        }
    }

    /// Save shared URL (keychain + UserDefaults + file), then show modal. User taps "Open Spines" to go back to the app.
    private func saveURLAndShowModal(_ url: URL) {
        let urlString = url.absoluteString
        writePendingImportURLToKeychain(urlString)
        let defaults = UserDefaults(suiteName: appGroupId)
        defaults?.set(urlString, forKey: pendingImportURLKey)
        defaults?.set(false, forKey: pendingImportKey)
        defaults?.removeObject(forKey: pendingImportErrorKey)
        defaults?.synchronize()
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let fileURL = container.appendingPathComponent(pendingImportURLFileName)
            try? urlString.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.async { [weak self] in
            self?.showModal(message: "Link received. Tap Open Spines to continue.", linkReceived: true)
        }
    }

    /// Save error message, then show modal so user can still tap Open Spines and see the error in the app.
    private func saveErrorAndShowModal(message: String) {
        writeErrorToKeychain(message)
        UserDefaults(suiteName: appGroupId)?.set(false, forKey: pendingImportKey)
        UserDefaults(suiteName: appGroupId)?.set(message, forKey: pendingImportErrorKey)
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: pendingImportURLKey)
        UserDefaults(suiteName: appGroupId)?.synchronize()
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            try? FileManager.default.removeItem(at: container.appendingPathComponent(pendingImportURLFileName))
        }
        DispatchQueue.main.async { [weak self] in
            self?.showModal(message: message + "\n\nTap Open Spines to try again or use a CSV file.", linkReceived: false)
        }
    }

    private func writePendingImportURLToKeychain(_ urlString: String) {
        guard let data = urlString.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func writeErrorToKeychain(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccountError
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
