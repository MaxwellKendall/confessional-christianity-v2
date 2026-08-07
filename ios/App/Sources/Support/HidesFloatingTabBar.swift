// Lets a pushed screen opt itself out of the floating tab bar (RootView's
// FloatingTabBarView) regardless of which tab's NavigationPath it landed on.
// Needed because the same screen (e.g. SessionView) can be reached from
// multiple tabs' navigationDestination(for:) — visibility has to be a
// property of the screen, not of the tab it happened to be pushed from.
import SwiftUI

private struct HidesFloatingTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func hidesFloatingTabBar(_ hidden: Bool = true) -> some View {
        preference(key: HidesFloatingTabBarKey.self, value: hidden)
    }

    func onHidesFloatingTabBarChange(_ action: @escaping (Bool) -> Void) -> some View {
        onPreferenceChange(HidesFloatingTabBarKey.self, perform: action)
    }
}
