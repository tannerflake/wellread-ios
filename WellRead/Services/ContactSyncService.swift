//
//  ContactSyncService.swift
//  WellRead
//
//  Reads the device address book (with permission) and matches contacts
//  against Spine members by phone number, so users can find friends already
//  on the app and invite the rest by text.
//

import Foundation
import Contacts

/// One address-book entry relevant to friend discovery/invites.
struct SyncedContact: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// Raw numbers as entered in the address book (used for the SMS recipient).
    let phoneNumbers: [String]
    /// Last-10-digit match keys derived from `phoneNumbers`.
    let matchKeys: Set<String>
}

/// A contact matched to an existing Spine member.
struct MatchedMember: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let user: User
    let contact: SyncedContact
}

enum ContactSyncService {

    /// Digits only. "+1 (512) 555-0199" → "15125550199".
    static func normalizePhoneNumber(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    /// Numbers match when their last 10 digits agree (folds "+1"/leading
    /// country codes into one key); shorter numbers must match exactly.
    static func matchKey(_ raw: String) -> String? {
        let digits = normalizePhoneNumber(raw)
        guard digits.count >= 7 else { return nil }
        return String(digits.suffix(10))
    }

    static var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    static func requestAccess() async -> Bool {
        let store = CNContactStore()
        return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    /// All contacts that have at least one phone number, sorted by name.
    /// Call only after access is granted.
    static func fetchContacts() async -> [SyncedContact] {
        await Task.detached(priority: .userInitiated) { () -> [SyncedContact] in
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var contacts: [SyncedContact] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                let numbers = contact.phoneNumbers.map { $0.value.stringValue }
                guard !numbers.isEmpty else { return }
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let displayName = name.isEmpty
                    ? (contact.organizationName.isEmpty ? numbers[0] : contact.organizationName)
                    : name
                contacts.append(SyncedContact(
                    id: contact.identifier,
                    displayName: displayName,
                    phoneNumbers: numbers,
                    matchKeys: Set(numbers.compactMap { matchKey($0) })
                ))
            }
            return contacts
        }.value
    }

    /// Splits contacts into members already on Spine (matched by phone) and
    /// everyone else (invite candidates). `readers` come from
    /// UserRepository.fetchAllReaderProfiles.
    static func match(
        contacts: [SyncedContact],
        readers: [(uid: String, user: User)]
    ) -> (onSpine: [MatchedMember], toInvite: [SyncedContact]) {
        var keyToReader: [String: (uid: String, user: User)] = [:]
        for reader in readers {
            guard let phone = reader.user.phoneNumber, let key = matchKey(phone) else { continue }
            keyToReader[key] = reader
        }
        var onSpine: [MatchedMember] = []
        var matchedUids = Set<String>()
        var toInvite: [SyncedContact] = []
        for contact in contacts {
            if let reader = contact.matchKeys.compactMap({ keyToReader[$0] }).first {
                if matchedUids.insert(reader.uid).inserted {
                    onSpine.append(MatchedMember(uid: reader.uid, user: reader.user, contact: contact))
                }
            } else {
                toInvite.append(contact)
            }
        }
        return (onSpine, toInvite)
    }
}
