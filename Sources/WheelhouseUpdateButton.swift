import CmuxUpdater
import SwiftUI

/// The one control at the foot of the sidebar in Wheelhouse IDE: it looks for a newer
/// version. While a check, a download or an offer is showing, the update pill next to it
/// takes its place.
struct WheelhouseUpdateButton: View {
    var model: UpdateStateModel

    private let title = String(localized: "wheelhouse.updateButton.help", defaultValue: "Check for Updates")
    private let size = SidebarFooterButtonMetrics.buttonSize

    var body: some View {
        if !model.showsPill {
            Button {
                AppDelegate.shared?.checkForUpdates(nil)
            } label: {
                CmuxSystemSymbolImage(
                    magnified: "arrow.down.circle", pointSize: 12, weight: .medium,
                    tint: Color(nsColor: .secondaryLabelColor)
                )
                .frame(width: size, height: size, alignment: .center)
            }
            .buttonStyle(SidebarFooterIconButtonStyle())
            .frame(width: size, height: size, alignment: .center)
            .safeHelp(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier("WheelhouseUpdateButton")
        }
    }
}
