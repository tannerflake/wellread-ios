//
//  ApiKeys.swift
//  WellRead
//
//  Reads API keys from Secrets.plist (gitignored) or Info.plist. Do not commit real keys.
//

import Foundation

enum ApiKeys {
    /// Claude (Anthropic) API key for AI features. From Secrets.plist "CLAUDE_API_KEY" or Info.plist.
    static var claude: String? {
        if let key = keyFromPlist(named: "Secrets", key: "CLAUDE_API_KEY"), !key.isEmpty { return key }
        if let key = keyFromPlist(named: "Info", key: "CLAUDE_API_KEY"), !key.isEmpty { return key }
        return nil
    }

    private static func keyFromPlist(named name: String, key: String) -> String? {
        guard let path = Bundle.main.path(forResource: name, ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let value = plist[key] as? String else { return nil }
        return value
    }
}
