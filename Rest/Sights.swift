import SwiftUI

/// Something out of the window to rest your eyes on, picked fresh for each
/// break: "Try and look at a church spire". Each has its own pictogram, in
/// the asset catalog under Sights. Most are traced from the pictogram set;
/// the spire, cloud, bird, crane and chimney are drawn to match it.
struct Sight: Equatable {
    let thing: String
    /// The pictogram's name under Sights in the asset catalog.
    let icon: String

    static let all: [Sight] = [
        Sight(thing: "a church spire", icon: "spire"),
        Sight(thing: "the top of a tree", icon: "tree"),
        Sight(thing: "a cloud", icon: "cloud"),
        Sight(thing: "a bird", icon: "bird"),
        Sight(thing: "a plane", icon: "plane"),
        Sight(thing: "a crane", icon: "crane"),
        Sight(thing: "the tallest building you can see", icon: "building"),
        Sight(thing: "a chimney", icon: "chimney"),
        Sight(thing: "the horizon", icon: "horizon"),
        Sight(thing: "the furthest hill you can see", icon: "hill"),
        Sight(thing: "a car going by", icon: "car"),
        Sight(thing: "a dog out for a walk", icon: "dog"),
        Sight(thing: "people across the street", icon: "people"),
    ]

    /// Any of them except the one from the last break.
    static func pick(after last: Sight?) -> Sight {
        all.filter { $0 != last }.randomElement() ?? all[0]
    }
}

struct SightIcon: View {
    let icon: String

    var body: some View {
        Image("Sights/\(icon)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }
}
