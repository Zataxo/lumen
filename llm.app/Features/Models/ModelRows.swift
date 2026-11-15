import SwiftUI

struct ModelRow: View {
    let model: ModelInfo
    var isDefault = false
    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.small - 2) {
                Text(model.displayName)
                    .font(.body.weight(.medium))
                if let tag = model.tag {
                    Text(tag)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                if isDefault {
                    CapsuleBadge(title: "Default", systemImage: "star.fill", tint: accent)
                }
            }
            if !metadata.isEmpty {
                Text(metadata.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            let badges = [ModelCapability.vision, .tools, .thinking, .embedding].filter(model.capabilities.contains)
            if !badges.isEmpty {
                HStack(spacing: Spacing.xSmall) {
                    ForEach(badges, id: \.self) { CapabilityBadge(capability: $0) }
                }
            }
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    private var metadata: [String] {
        [
            model.family,
            model.parameterSize,
            model.quantization,
            model.sizeBytes.map(Format.bytes),
            model.contextLength.map(Format.contextLength),
        ].compactMap { $0 }.filter { !$0.isEmpty }
    }

    static var placeholder: some View {
        ModelRow(model: ModelInfo(id: "placeholder-model:latest", family: "family", parameterSize: "8.0B", quantization: "Q4_K_M", sizeBytes: 4_000_000_000))
    }
}

struct LoadedModelRow: View {
    let model: LoadedModel

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: "memorychip")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.id)
                    .font(.body.weight(.medium))
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if let vram = model.sizeInVRAMBytes, let size = model.sizeBytes, size > 0 {
            let gpuShare = Int((Double(vram) / Double(size) * 100).rounded())
            parts.append("\(Format.bytes(size)) · \(gpuShare)% GPU")
        }
        if let context = model.contextLength { parts.append(Format.contextLength(context)) }
        if let expiresAt = model.expiresAt, expiresAt > .now {
            // keep_alive = -1 reports an expiry centuries away.
            parts.append(expiresAt.timeIntervalSinceNow > 86_400 * 365
                         ? "Stays loaded"
                         : "Unloads \(expiresAt.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
