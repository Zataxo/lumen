import SwiftUI

/// Circular avatar: the user's photo, or their initials on a colored gradient.
struct AvatarView: View {
    var name: String
    var imageData: Data?
    var color: PaletteColor
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let imageData, let image = Image(imageData: imageData) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(color.color.gradient)
                    .overlay {
                        Text(Initials.from(name))
                            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
}

extension AvatarView {
    init(profile: UserProfile, size: CGFloat = 28) {
        self.init(name: profile.name, imageData: profile.avatarData, color: profile.avatarColor, size: size)
    }
}
