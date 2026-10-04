//
//  AppPillTabs.swift
//  SyncBoard
//

import SwiftUI

/// A reusable, polished pill-style segmented tab picker matching the macOS modern / popover look.
struct AppPillTabs<T: Hashable>: View {
    @Binding var selection: T
    let items: [T]
    var title: ((T) -> String)?
    var icon: ((T) -> String?)?
    var isCompact: Bool = false

    init(
        selection: Binding<T>,
        items: [T],
        title: ((T) -> String)? = nil,
        icon: ((T) -> String?)? = nil,
        isCompact: Bool = false
    ) {
        self._selection = selection
        self.items = items
        self.title = title
        self.icon = icon
        self.isCompact = isCompact
    }

    init(
        selection: Binding<T>,
        title: @escaping (T) -> String,
        icon: ((T) -> String?)? = nil,
        isCompact: Bool = false
    ) where T: CaseIterable, T.AllCases: RandomAccessCollection {
        self._selection = selection
        self.items = Array(T.allCases)
        self.title = title
        self.icon = icon
        self.isCompact = isCompact
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: isCompact ? 11 : 12, weight: isSelected ? .semibold : .medium))
                        }
                        if let titleText = title?(item) {
                            Text(titleText)
                                .font(isCompact ? .subheadline : .callout)
                                .fontWeight(isSelected ? .semibold : .regular)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isCompact ? 4 : 6)
                    .padding(.horizontal, isCompact ? 6 : 8)
                    .background(
                        isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                    )
                    .shadow(color: isSelected ? Color.black.opacity(0.06) : Color.clear, radius: 2, y: 1)
                    .contentShape(RoundedRectangle(cornerRadius: isCompact ? 6 : 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: isCompact ? 8 : 10))
    }
}
