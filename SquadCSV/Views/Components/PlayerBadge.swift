import SwiftUI

/// Circular shirt-number badge coloured by position group.
struct PlayerBadge: View {
    let player: Player
    var size: CGFloat = 36

    var body: some View {
        let color = player.primaryPosition?.group.color ?? .gray
        Text(player.number.map(String.init) ?? player.initials)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .opacity(player.isAvailable ? 1 : 0.45)
    }
}

/// A row describing a player, used in the squad list and player picker.
struct PlayerRow: View {
    let player: Player
    var status: SelectionStatus? = nil

    var body: some View {
        HStack(spacing: 12) {
            PlayerBadge(player: player)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if !player.positions.isEmpty {
                        Text(player.positionsText)
                    }
                    if !player.isAvailable {
                        Label("Unavailable", systemImage: "cross.case.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let status {
                StatusTag(status: status)
            }
        }
        .contentShape(Rectangle())
    }
}

struct StatusTag: View {
    let status: SelectionStatus

    var body: some View {
        switch status {
        case .starting(let role):
            tag(role.rawValue, color: role.group.color)
        case .bench:
            tag("SUB", color: .gray)
        case .notSelected:
            EmptyView()
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}
