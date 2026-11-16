import SwiftUI

/// Full-window sign-in gate. Nothing else in the app is reachable until it succeeds.
struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var message: String?
    @State private var shakes = 0
    @State private var failures = 0
    @State private var hasAppeared = false
    @FocusState private var focus: Field?
 
    private enum Field { case username, password }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isLockedOut(at: .now)
    }

    var body: some View {
        ZStack {
            AuthBackground()

            ScrollView {
                VStack(spacing: Spacing.xLarge) {
                    Spacer(minLength: Spacing.xxLarge)
                    header
                    form
                        .modifier(Shake(animatableData: CGFloat(shakes)))
                    Spacer(minLength: Spacing.large)
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, Spacing.xLarge)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.85)) {
                hasAppeared = true
            }
            focus = .username
        }
        #if os(iOS)
        .sensoryFeedback(.error, trigger: failures)
        #endif
    }

    private var header: some View {
        VStack(spacing: Spacing.medium) {
            NeuralOrbView(size: 150, tint: Color(red: 0.30, green: 0.80, blue: 0.98))
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.8)
                .opacity(hasAppeared ? 1 : 0)
            Text("Lumen")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.75, green: 0.85, blue: 1)], startPoint: .top, endPoint: .bottom))
            Text("Sign in to continue")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 12)
    }

    private var form: some View {
        VStack(spacing: Spacing.medium) {
            VStack(spacing: 0) {
                HStack(spacing: Spacing.medium) {
                    Image(systemName: "person")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                    TextField("Username", text: $username, prompt: Text("Username").foregroundStyle(.white.opacity(0.4)))
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        #endif
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                .padding(.horizontal, Spacing.large)
                .frame(height: 50)

                Divider().overlay(Color.white.opacity(0.12))

                HStack(spacing: Spacing.medium) {
                    Image(systemName: "lock")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                    Group {
                        if isPasswordVisible {
                            TextField("Password", text: $password, prompt: Text("Password").foregroundStyle(.white.opacity(0.4)))
                        } else {
                            SecureField("Password", text: $password, prompt: Text("Password").foregroundStyle(.white.opacity(0.4)))
                        }
                    }
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
                    #endif
                    .submitLabel(.go)
                    .onSubmit(submit)
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                }
                .padding(.horizontal, Spacing.large)
                .frame(height: 50)
            }
            .foregroundStyle(.white)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(message == nil ? Color.white.opacity(0.14) : Color.red.opacity(0.6), lineWidth: 1)
            }

            statusLine

            Button(action: submit) {
                Text("Sign In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [Color(red: 0.36, green: 0.30, blue: 0.95), Color(red: 0.13, green: 0.65, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
                            .opacity(canSubmit ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.36, green: 0.30, blue: 0.95).opacity(canSubmit ? 0.45 : 0), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 20)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let lockedUntil = auth.lockedUntil, lockedUntil > .now {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(lockedUntil.timeIntervalSince(context.date).rounded(.up)))
                Label(seconds > 0 ? "Too many attempts. Try again in \(seconds)s." : "You can try again now.", systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(seconds > 0 ? Color.orange : Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func isLockedOut(at date: Date) -> Bool {
        (auth.lockedUntil ?? .distantPast) > date
    }

    private func submit() {
        guard canSubmit else { return }
        switch auth.signIn(username: username, password: password) {
        case .success:
            message = nil
            password = ""
        case .invalidCredentials(let attemptsLeft):
            fail(attemptsLeft <= 2
                 ? "Incorrect username or password. \(attemptsLeft) attempt\(attemptsLeft == 1 ? "" : "s") left."
                 : "Incorrect username or password.")
        case .lockedOut:
            fail(nil)
        }
    }

    private func fail(_ text: String?) {
        password = ""
        focus = .password
        failures += 1
        withAnimation(.snappy) { message = text }
        if !reduceMotion {
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        }
    }
}

/// Horizontal shake for a rejected sign-in.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// The deep indigo backdrop from the app icon, with slowly drifting light.
struct AuthBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.12, blue: 0.52), Color(red: 0.08, green: 0.07, blue: 0.27), Color(red: 0.02, green: 0.06, blue: 0.16)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.45))
                        .frame(width: size.width * 0.9)
                        .blur(radius: 90)
                        .offset(x: size.width * 0.18 * cos(t * 0.15), y: -size.height * 0.22 + 30 * sin(t * 0.2))
                    Circle()
                        .fill(Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.32))
                        .frame(width: size.width * 0.8)
                        .blur(radius: 100)
                        .offset(x: size.width * 0.3 * sin(t * 0.12), y: size.height * 0.32 + 40 * cos(t * 0.17))
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .ignoresSafeArea()
    }
}

/// The modern "welcome" moment right after signing in. Continues on its own; tap to skip.
struct WelcomeSplashView: View {
    let account: LocalAccount
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleLetters = 0
    @State private var showsSubtitle = false
    @State private var orbScale: CGFloat = 0.6

    private var greeting: String { "Welcome, \(account.displayName)" }

    var body: some View {
        ZStack {
            AuthBackground()
            VStack(spacing: Spacing.xLarge) {
                NeuralOrbView(size: 190, tint: Color(red: 0.30, green: 0.80, blue: 0.98), isActive: true)
                    .scaleEffect(orbScale)
                HStack(spacing: 0) {
                    ForEach(Array(greeting.enumerated()), id: \.offset) { index, character in
                        Text(String(character))
                            .opacity(index < visibleLetters ? 1 : 0)
                            .offset(y: index < visibleLetters || reduceMotion ? 0 : 10)
                            .blur(radius: index < visibleLetters ? 0 : 4)
                    }
                }
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(greeting)
                Text("Your models are ready. Let's create something.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(showsSubtitle ? 1 : 0)
                    .offset(y: showsSubtitle || reduceMotion ? 0 : 8)
            }
            .padding(Spacing.xLarge)
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .task {
            if reduceMotion {
                visibleLetters = greeting.count
                orbScale = 1
                showsSubtitle = true
                try? await Task.sleep(for: .seconds(1.6))
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { orbScale = 1 }
                try? await Task.sleep(for: .milliseconds(250))
                for index in 1...greeting.count {
                    withAnimation(.easeOut(duration: 0.25)) { visibleLetters = index }
                    try? await Task.sleep(for: .milliseconds(45))
                }
                withAnimation(.easeOut(duration: 0.4)) { showsSubtitle = true }
                try? await Task.sleep(for: .seconds(1.4))
            }
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }
}
