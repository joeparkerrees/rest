import SwiftUI

/// Something out of the window to rest your eyes on, picked fresh for each
/// break: "Try and look at a church spire". Each has its own pictogram, in
/// the asset catalog under Sights. Most are traced from the pictogram set;
/// the spire, cloud, bird, crane and chimney are drawn to match it.
struct Sight: Equatable {
    let thing: String
    /// The pictogram's name under Sights in the asset catalog.
    let icon: String
    /// How far the drawing's lowest point sits above the bottom of its
    /// 196-unit square, so it can stand on the horizon. Nil for things that
    /// belong in the sky, which float above it instead.
    let foot: CGFloat?

    static let all: [Sight] = [
        Sight(thing: "a church spire", icon: "spire", foot: 14),
        Sight(thing: "the top of a tree", icon: "tree", foot: 14),
        Sight(thing: "a cloud", icon: "cloud", foot: nil),
        Sight(thing: "a bird", icon: "bird", foot: nil),
        Sight(thing: "a plane", icon: "plane", foot: nil),
        Sight(thing: "a crane", icon: "crane", foot: 9),
        Sight(thing: "the tallest building you can see", icon: "building", foot: 16),
        Sight(thing: "a chimney", icon: "chimney", foot: 18),
        Sight(thing: "the horizon", icon: "horizon", foot: 14),
        Sight(thing: "the furthest hill you can see", icon: "hill", foot: 14),
        Sight(thing: "a car going by", icon: "car", foot: 16),
        Sight(thing: "a dog out for a walk", icon: "dog", foot: nil),
        Sight(thing: "people across the street", icon: "people", foot: 15),
    ]

    /// Any of them except the one from the last break.
    static func pick(after last: Sight?) -> Sight {
        all.filter { $0 != last }.randomElement() ?? all[0]
    }
}

struct SightIcon: View {
    let icon: String
    var size: CGFloat = 44

    var body: some View {
        Image("Sights/\(icon)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A sight in the landscape, in ink: standing on the horizon
/// with its foot on the line, or up in the sky if it flies. Place it with
/// its frame's bottom edge on the horizon.
struct SightFigure: View {
    let sight: Sight
    var size: CGFloat

    var body: some View {
        SightIcon(icon: sight.icon, size: size)
            .foregroundStyle(Theme.ink)
            // One unit past the foot, so the figure overlaps the land with no seam.
            .offset(y: sight.foot.map { ($0 + 1) / 196 * size } ?? -size * 0.6)
    }
}
