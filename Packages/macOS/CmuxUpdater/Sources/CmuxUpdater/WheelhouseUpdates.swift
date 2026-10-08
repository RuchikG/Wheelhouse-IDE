import Foundation

/// A Wheelhouse IDE release has cmux's staging bundle id and an update feed of its own.
/// `wheelhouse/release.sh` writes the feed, its public key and this key into the Info.plist,
/// and such a build updates itself from that feed like a public build.
enum WheelhouseUpdates {
    static let infoKey = "WheelhouseUpdates"

    static func hasOwnFeed(info: [String: Any]?) -> Bool {
        info?[infoKey] as? Bool == true
    }
}
