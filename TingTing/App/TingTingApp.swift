import SwiftUI

@main
struct TingTingApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.gold)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, phase in store.scenePhaseChanged(phase) }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            switch store.phase {
            case .launching:
                SplashView()
            case .signedOut:
                LoginView()
            case .ready:
                MainTabView()
            }
            if store.phase == .ready && store.isLocked {
                LockView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isLocked)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Ting Ting").font(.largeTitle.bold()).foregroundStyle(Theme.gold)
                ProgressView()
            }
        }
    }
}

struct LockView: View {
    @Environment(AppStore.self) private var store
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill").font(.system(size: 54)).foregroundStyle(Theme.gold)
                Text("Ting Ting đang khoá").font(.title3.bold())
                if failed { Text("Chưa xác thực được. Thử lại nhé.").font(.footnote).foregroundStyle(Theme.muted) }
                PrimaryButton(title: "Mở khoá bằng Face ID") { Task { failed = !(await store.unlock()) } }
                    .frame(maxWidth: 280)
            }
            .padding()
        }
        .task { failed = !(await store.unlock()) }
    }
}

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ting Ting").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.gold)
                    Text("Quản lý tài sản cá nhân").foregroundStyle(Theme.muted)
                }
                .padding(.top, 60)

                if !store.isConfigured {
                    ErrorBox(text: AppError.notConfigured.vietnamese)
                }

                Field(label: "Email") {
                    TextField("email@vd.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldStyle()
                }
                Field(label: "Mật khẩu") {
                    SecureField("••••••", text: $password)
                        .textContentType(.password)
                        .fieldStyle()
                }
                if let error { ErrorBox(text: error) }
                PrimaryButton(title: "Đăng nhập", busy: busy, disabled: email.isEmpty || password.isEmpty) {
                    Task { await signIn() }
                }
                Text("Dùng cùng tài khoản với web Ting Ting. Dữ liệu được đồng bộ giữa app và web.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(20)
        }
        .screen()
    }

    private func signIn() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await store.signIn(email: email, password: password)
        } catch {
            self.error = error.vietnamese
        }
    }
}
