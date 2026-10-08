import Foundation
import Testing
@testable import CmuxUpdater

@MainActor
@Suite struct WheelhouseUpdatesTests {
    private let release = "com.cmuxterm.app.staging.wheelhouse"

    @Test func aReleaseWithItsOwnFeedUpdatesItself() {
        #expect(!UpdateController.isDevLikeBundle(identifier: release, info: ["WheelhouseUpdates": true]))
    }

    @Test func aReleaseBuiltWithoutAFeedStaysOffCmuxsFeed() {
        #expect(UpdateController.isDevLikeBundle(identifier: release, info: ["WheelhouseVersion": "0.1.3"]))
        #expect(UpdateController.isDevLikeBundle(identifier: release, info: ["WheelhouseUpdates": false]))
        #expect(UpdateController.isDevLikeBundle(identifier: release, info: ["WheelhouseUpdates": "true"]))
        #expect(UpdateController.isDevLikeBundle(identifier: release, info: nil))
    }

    @Test func aDevBuildStaysOffEveryFeed() {
        #expect(UpdateController.isDevLikeBundle(identifier: "com.cmuxterm.app.debug.ide", info: nil))
    }

    @Test func aPublicBuildIsNotAffected() {
        #expect(!UpdateController.isDevLikeBundle(identifier: "com.cmuxterm.app", info: nil))
    }
}
