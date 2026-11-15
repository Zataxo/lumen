import SwiftUI

/// Temperature / Top P / context length rows. `nil` values mean "inherit": the model's own
/// default in Settings, or the app default inside a chat (`inheritLabel`).
struct ParameterControls: View {
    @Binding var parameters: GenerationParameters
    var inheritLabel = "Model Default"

    static let contextLengths = [2048, 4096, 8192, 16384, 32768, 65536, 131072]

    var body: some View {
        ParameterSlider(title: "Temperature", value: $parameters.temperature, range: 0...2, step: 0.05, fallback: 0.8, inheritLabel: inheritLabel)
        ParameterSlider(title: "Top P", value: $parameters.topP, range: 0...1, step: 0.01, fallback: 0.9, inheritLabel: inheritLabel)
        Picker("Context Length", selection: $parameters.contextLength) {
            Text(inheritLabel).tag(Int?.none)
            ForEach(Self.contextLengths, id: \.self) { length in
                Text(Format.contextLength(length).replacingOccurrences(of: " ctx", with: " tokens")).tag(Optional(length))
            }
        }
    }
}

struct ParameterSlider: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let fallback: Double
    var inheritLabel = "Model Default"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Toggle(isOn: Binding(
                get: { value != nil },
                set: { value = $0 ? fallback : nil }
            )) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? inheritLabel)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if value != nil {
                Slider(value: Binding(get: { value ?? fallback }, set: { value = $0 }), in: range, step: step)
                    .accessibilityLabel(title)
            }
        }
        .animation(.snappy, value: value == nil)
    }
}
