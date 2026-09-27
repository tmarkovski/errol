// Errol's About window: the icon, the name and version, what Errol does in
// a line, and where to read more — the website, and the licenses of the
// code Errol borrows, which ship inside the app. It wears the console's
// theme on the window's shell and its chips for the links.
// MenuBarController.showAbout builds the window, which fits this view.

import AppKit
import SwiftUI

struct AboutView: View {
    static let width = Perch.s(300)
    static let website = URL(string: "https://errol.chat")!

    /// The release and its build, as the bundle carries them; the release
    /// workflow sets both from the tag and the commit count.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let release = info["CFBundleShortVersionString"] as? String ?? "\u{2013}"
        guard let build = info["CFBundleVersion"] as? String, build != release else {
            return "Version \(release)"
        }
        return "Version \(release) (\(build))"
    }

    /// The bundle's copyright line, the one Finder's Get Info shows too.
    static var copyright: String? {
        (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The licenses of the code Errol includes: Sparkle's, and
    /// PermissionFlow's for the permission guide.
    static var notices: URL? {
        Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt")
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: Perch.s(88), height: Perch.s(88))
                .accessibilityHidden(true)
            Text("Errol")
                .font(Perch.text(18, .semibold))
                .foregroundStyle(Perch.ink)
                .padding(.top, Perch.s(6))
            Text(Self.version)
                .font(Perch.text(11))
                .foregroundStyle(Perch.secondary)
                .textSelection(.enabled)
                .padding(.top, Perch.s(2))
            Text("Let ChatGPT and Claude talk it out.")
                .font(Perch.text(12))
                .foregroundStyle(Perch.ink)
                .padding(.top, Perch.s(14))
            HStack(spacing: Perch.s(2)) {
                link("errol.chat") { NSWorkspace.shared.open(Self.website) }
                if let notices = Self.notices {
                    Text("\u{00B7}").foregroundStyle(Perch.muted)
                    link("Acknowledgements") { NSWorkspace.shared.open(notices) }
                }
            }
            .font(Perch.text(11.5))
            .padding(.top, Perch.s(8))
            VStack(spacing: Perch.s(2)) {
                if let copyright = Self.copyright { Text(copyright) }
                Text("Free software under the GNU GPL, version 3")
            }
            .font(Perch.text(10.5))
            .foregroundStyle(Perch.muted)
            .padding(.top, Perch.s(18))
        }
        .multilineTextAlignment(.center)
        // The top clears the title bar's close button.
        .padding(.top, Perch.s(34))
        .padding(.bottom, Perch.s(20))
        .frame(width: Self.width)
        .background(Perch.shell)
    }

    /// A link as the console's chips are: the accent's ink, with the
    /// rounded wash under the pointer.
    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).foregroundStyle(Perch.accentText).perchChip()
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}

#if DEBUG
#Preview("About") {
    AboutView()
}
#endif
