import SwiftUI
import DomainKit

enum OnboardingPage: Int, CaseIterable {
    case title, teachingScripture, catechism, sabbathScripture, sermon, firstAction
}

struct OnboardingView: View {
    let existingNames: [String]
    var onBegin: (String) -> Bool
    var onSermon: () -> Void
    var onSignIn: () -> Void

    @State private var page = OnboardingPage.title
    @State private var name = ""
    @State private var showsSaveError = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(OnboardingPage.allCases, id: \.self) { step in
                    Button { go(to: step) } label: {
                        Capsule()
                            .fill(step == page ? Color.ccGilt : .ccLine)
                            .frame(width: 14, height: 3)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Page \(step.rawValue + 1) of \(OnboardingPage.allCases.count)")
                    .accessibilityAddTraits(step == page ? .isSelected : [])
                }
                Spacer()
                if page != .firstAction {
                    Button("Skip") { go(to: .firstAction) }
                        .font(.ccBody(12.5))
                        .foregroundStyle(.ccInk2)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            TabView(selection: $page) {
                ForEach(OnboardingPage.allCases, id: \.self) { step in
                    screen(step)
                        .padding(.horizontal, 28)
                        .padding(.top, 10)
                        .padding(.bottom, 22)
                        .tag(step)
                        .accessibilityHidden(page != step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ccPaper.ignoresSafeArea())
        .foregroundStyle(.ccInk)
        .onChange(of: page) { _, next in
            if next != .firstAction { focused = false }
        }
        .alert("Couldn’t add your child", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your child’s name is still here. Please try again.")
        }
        #if DEBUG
        .onAppear {
            if let value = UserDefaults.standard.string(forKey: "OnboardingPage"),
               let number = Int(value), let step = OnboardingPage(rawValue: number - 1) {
                page = step
            }
        }
        #endif
    }

    @ViewBuilder
    private func screen(_ step: OnboardingPage) -> some View {
        switch step {
        case .title:
            VStack {
                Spacer()
                VStack(spacing: 20) {
                    Text("CONFESSIONAL CHRISTIANITY")
                        .font(.ccDisplay(15)).tracking(3.9)
                        .accessibilityAddTraits(.isHeader)
                    Rectangle().fill(.ccLine).frame(width: 28, height: 1)
                    Text("A rhythm for the Lord’s Day, and the week between.")
                        .font(.ccBody(17)).foregroundStyle(.ccInk2)
                        .lineSpacing(5)
                        .frame(maxWidth: 235)
                }
                .multilineTextAlignment(.center)
                Spacer()
                primary("Begin") { go(to: .teachingScripture) }
            }
        case .teachingScripture:
            scripture(
                "“And these words that I command you today shall be on your heart. You shall teach them diligently to your children, and shall talk of them when you sit in your house, and when you walk by the way, and when you lie down, and when you rise.”",
                reference: "Deuteronomy 6:6–7"
            )
        case .catechism:
            OnboardingCatechismDemo()
        case .sabbathScripture:
            scripture(
                "“If you turn back your foot from the Sabbath, from doing your pleasure on my holy day, and call the Sabbath a delight and the holy day of the LORD honorable … then you shall take delight in the LORD.”",
                reference: "Isaiah 58:13–14"
            )
        case .sermon:
            OnboardingSermonDemo()
        case .firstAction:
            GeometryReader { geometry in
                ScrollView {
                    firstAction.frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func scripture(_ quote: String, reference: String) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    Text(quote)
                        .font(.ccBody(23)).lineSpacing(7)
                    VStack(spacing: 6) {
                        Text(reference.uppercased())
                            .font(.ccDisplay(11, semibold: true)).tracking(1.76)
                            .foregroundStyle(.ccGilt)
                        Text("ESV")
                            .font(.ccDisplay(9)).tracking(2.7)
                            .foregroundStyle(.ccInk3)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var firstAction: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Who will you teach first?")
                    .font(.ccDisplay(22, semibold: true))
                    .accessibilityAddTraits(.isHeader)
                Text("A first name is all it takes. You can begin without an account.")
                    .font(.ccBody(16.5)).foregroundStyle(.ccInk2)
            }
            VStack(spacing: 12) {
                TextField("First name", text: $name)
                    .font(.ccBody(16))
                    .accessibilityLabel("Child’s first name")
                    .textContentType(.givenName)
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(begin)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(.ccSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(focused ? Color.ccGilt : .ccLine)
                    }
                if let error = nameCheck.message {
                    Text(error)
                        .font(.ccBody(13.5)).foregroundStyle(.ccDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                primary("Begin", action: begin)
                    .disabled(!canBegin)
            }
            VStack(alignment: .leading, spacing: 10) {
                actionLink("No children at home yet? Start with Sunday’s sermon", action: onSermon)
                actionLink("Used the app on another iPhone? Sign in", action: onSignIn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameCheck: ChildName.Check { ChildName.validate(name, existing: existingNames) }

    private var canBegin: Bool {
        if case .valid = nameCheck { return true }
        return false
    }

    private func begin() {
        guard case .valid(let trimmedName) = nameCheck else { return }
        focused = false
        showsSaveError = !onBegin(trimmedName)
    }

    private func go(to step: OnboardingPage) {
        withAnimation(reduceMotion ? nil : .easeInOut) { page = step }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ccBody(15).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.ccOnChapel)
                .background(.ccChapel, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func actionLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).underline().font(.ccBody(13.5)).foregroundStyle(.ccInk2)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 32, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
