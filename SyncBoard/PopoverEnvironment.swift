//
//  PopoverEnvironment.swift
//  SyncBoard
//

import SwiftUI

private struct DismissPopoverKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Closes the menu-bar popover itself, as opposed to `\.dismiss`, which
    /// only pops the current NavigationStack destination.
    var dismissPopover: () -> Void {
        get { self[DismissPopoverKey.self] }
        set { self[DismissPopoverKey.self] = newValue }
    }
}
