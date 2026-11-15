import SwiftUI

/// Small capsule label: "Not encrypted", "Default", capability badges.
struct CapsuleBadge: View {
    var title: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(title)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
        .fixedSize()
    }
}

struct NotEncryptedBadge: View {
    var body: some View {
        CapsuleBadge(title: "Not encrypted", systemImage: "lock.open", tint: .orange)
            .help("This server uses plain http://. Traffic, including API keys, isn't encrypted.")
            .accessibilityLabel("Not encrypted connection")
    }
}

struct CapabilityBadge: View {
    var capability: ModelCapability

    var body: some View {
        CapsuleBadge(title: capability.label, systemImage: capability.symbolName, tint: tint)
    }

    private var tint: Color {
        switch capability {
        case .vision: .blue
        case .tools: .purple
        case .thinking: .pink
        case .embedding: .teal
        case .completion: .secondary
        }
    }
}

struct StatusDot: View {
    var status: ServerStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                if case .checking = status {
                    Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
                }
            }
            .help(status.description)
            .accessibilityLabel(status.description)
    }

    private var color: Color {
        switch status {
        case .online: .green
        case .slow: .yellow
        case .offline: .red
        case .unknown, .checking: .secondary.opacity(0.35)
        }
    }
}
