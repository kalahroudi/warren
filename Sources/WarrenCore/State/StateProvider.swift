// SPDX-License-Identifier: Apache-2.0

/// The only way UI code reads or changes Warren's state.
/// The app shell uses `FixtureProvider`; later specs add providers backed by the real helper.
@MainActor
public protocol StateProvider {
    func snapshot() -> StateSnapshot
    func setSite(_ id: String, running: Bool)
    func setService(_ id: String, running: Bool)
    func setPaused(_ paused: Bool)
    func applyUpdate()
}
