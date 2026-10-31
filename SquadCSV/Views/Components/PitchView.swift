import SwiftUI

/// A football pitch with the lineup's players drawn on it.
/// Tap a marker to choose a player; drag it to fine-tune its position.
struct PitchView: View {
    @Binding var lineup: Lineup
    let playersByID: [UUID: Player]
    var isEditable = true
    var onTapSlot: (Int) -> Void = { _ in }

    /// Width / height of the drawn pitch.
    static let aspectRatio: CGFloat = 0.7

    @State private var draggingSlotID: UUID?
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let tokenSize = min(size.width * 0.12, 54)

            ZStack {
                PitchBackground()

                ForEach(Array(lineup.slots.enumerated()), id: \.element.id) { index, slot in
                    let isDragging = draggingSlotID == slot.id
                    let player = slot.playerID.flatMap { playersByID[$0] }

                    PlayerToken(
                        role: slot.role,
                        player: player,
                        isCaptain: player != nil && player?.id == lineup.captainID,
                        size: tokenSize
                    )
                    .scaleEffect(isDragging ? 1.15 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.4 : 0.2), radius: isDragging ? 6 : 2, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditable { onTapSlot(index) }
                    }
                    .gesture(dragGesture(index: index, slot: slot, size: size), including: isEditable ? .all : .none)
                    .position(
                        x: slot.x * size.width + (isDragging ? dragTranslation.width : 0),
                        y: slot.y * size.height + (isDragging ? dragTranslation.height : 0)
                    )
                    .zIndex(isDragging ? 1 : 0)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(slot.role.name): \(player?.name ?? "empty")")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .coordinateSpace(name: "pitch")
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.spring(duration: 0.3), value: lineup.slots)
    }

    private func dragGesture(index: Int, slot: LineupSlot, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("pitch"))
            .onChanged { value in
                draggingSlotID = slot.id
                dragTranslation = value.translation
            }
            .onEnded { value in
                let x = (slot.x * size.width + value.translation.width) / size.width
                let y = (slot.y * size.height + value.translation.height) / size.height
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if lineup.slots.indices.contains(index) {
                        lineup.slots[index].x = min(max(x, 0.06), 0.94)
                        lineup.slots[index].y = min(max(y, 0.05), 0.95)
                    }
                    draggingSlotID = nil
                    dragTranslation = .zero
                }
            }
    }
}

/// A player's marker on the pitch: a shirt-coloured disc with a name label.
struct PlayerToken: View {
    let role: Position
    let player: Player?
    var isCaptain = false
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if let player {
                    Circle().fill(role.group.color.gradient)
                    Circle().strokeBorder(.white, lineWidth: 2)
                    Text(player.number.map(String.init) ?? player.initials)
                        .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white)
                } else {
                    Circle().fill(.black.opacity(0.25))
                    Circle().strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.35, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if isCaptain {
                    Text("C")
                        .font(.system(size: size * 0.24, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: size * 0.38, height: size * 0.38)
                        .background(.yellow, in: Circle())
                        .offset(x: size * 0.1, y: -size * 0.1)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let player, !player.isAvailable {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(.white, .red)
                        .offset(x: size * 0.1, y: size * 0.05)
                }
            }

            Text(player?.shortName ?? role.rawValue)
                .font(.system(size: max(9, size * 0.24), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(player == nil ? 0.3 : 0.6), in: Capsule())
                .fixedSize()
        }
    }
}

struct PitchBackground: View {
    private let stripeCount = 12

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<stripeCount, id: \.self) { index in
                    Rectangle().fill(
                        index.isMultiple(of: 2)
                            ? Color(red: 0.18, green: 0.56, blue: 0.25)
                            : Color(red: 0.15, green: 0.5, blue: 0.22)
                    )
                }
            }
            PitchMarkings()
                .stroke(.white.opacity(0.8), lineWidth: 2)
            PitchSpots()
                .fill(.white.opacity(0.8))
        }
    }
}

/// Proportions follow a standard 105 × 68 m pitch.
private struct PitchGeometry {
    let field: CGRect

    init(in rect: CGRect) {
        let inset = rect.width * 0.04
        field = rect.insetBy(dx: inset, dy: inset)
    }

    var centreCircleRadius: CGFloat { field.width * 9.15 / 68 }
    var penaltyBoxSize: CGSize { CGSize(width: field.width * 40.3 / 68, height: field.height * 16.5 / 105) }
    var goalBoxSize: CGSize { CGSize(width: field.width * 18.3 / 68, height: field.height * 5.5 / 105) }
    var penaltySpotDistance: CGFloat { field.height * 11 / 105 }
}

struct PitchMarkings: Shape {
    func path(in rect: CGRect) -> Path {
        let geometry = PitchGeometry(in: rect)
        let field = geometry.field
        var path = Path()

        // Touchlines, halfway line and centre circle.
        path.addRect(field)
        path.move(to: CGPoint(x: field.minX, y: field.midY))
        path.addLine(to: CGPoint(x: field.maxX, y: field.midY))
        let radius = geometry.centreCircleRadius
        path.addEllipse(in: CGRect(x: field.midX - radius, y: field.midY - radius, width: radius * 2, height: radius * 2))

        // Boxes at both ends.
        let box = geometry.penaltyBoxSize
        let goal = geometry.goalBoxSize
        path.addRect(CGRect(x: field.midX - box.width / 2, y: field.minY, width: box.width, height: box.height))
        path.addRect(CGRect(x: field.midX - box.width / 2, y: field.maxY - box.height, width: box.width, height: box.height))
        path.addRect(CGRect(x: field.midX - goal.width / 2, y: field.minY, width: goal.width, height: goal.height))
        path.addRect(CGRect(x: field.midX - goal.width / 2, y: field.maxY - goal.height, width: goal.width, height: goal.height))

        // Penalty arcs: the part of a circle around each spot that lies outside the box.
        addArc(to: &path, spotY: field.minY + geometry.penaltySpotDistance, boxEdgeY: field.minY + box.height, centreX: field.midX, radius: radius)
        addArc(to: &path, spotY: field.maxY - geometry.penaltySpotDistance, boxEdgeY: field.maxY - box.height, centreX: field.midX, radius: radius)

        return path
    }

    private func addArc(to path: inout Path, spotY: CGFloat, boxEdgeY: CGFloat, centreX: CGFloat, radius: CGFloat) {
        let offset = boxEdgeY - spotY
        guard abs(offset) < radius else { return }
        let halfWidth = (radius * radius - offset * offset).squareRoot()
        let direction: CGFloat = offset >= 0 ? 1 : -1
        let steps = 24
        for step in 0...steps {
            let x = centreX - halfWidth + 2 * halfWidth * CGFloat(step) / CGFloat(steps)
            let dx = x - centreX
            let y = spotY + direction * (radius * radius - dx * dx).squareRoot()
            let point = CGPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
    }
}

struct PitchSpots: Shape {
    func path(in rect: CGRect) -> Path {
        let geometry = PitchGeometry(in: rect)
        let field = geometry.field
        let r = max(2, rect.width * 0.008)
        var path = Path()
        for y in [field.midY, field.minY + geometry.penaltySpotDistance, field.maxY - geometry.penaltySpotDistance] {
            path.addEllipse(in: CGRect(x: field.midX - r, y: y - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

#Preview {
    let store = SquadStore.preview()
    return PitchView(lineup: .constant(store.lineups[0]), playersByID: store.playersByID)
        .padding()
}
