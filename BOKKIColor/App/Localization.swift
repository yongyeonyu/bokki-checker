import Foundation

/// Looks up a user-facing string in `Localizable.xcstrings`. The Korean source text is the key, so a
/// device language without a translation falls back to the Korean original.
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
