import SwiftUI

/// Settings (web: app/account).
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("faceIDEnabled") private var faceID = true
    @State private var confirmReset = false
    @State private var resetMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Text(String((store.email ?? "?").split(separator: "@").first?.prefix(2) ?? "?").uppercased())
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(Theme.gold.opacity(0.18), in: Circle())
                        .foregroundStyle(Theme.gold)
                    VStack(alignment: .leading) {
                        Text("Tài khoản").fontWeight(.semibold)
                        Text(store.email ?? "").font(.money(12.5)).foregroundStyle(Theme.muted)
                    }
                }
            }

            Section("Cập nhật giá") {
                PriceUpdateSection()
                NavigationLink { PriceFromAIView() } label: {
                    Label("AI đọc giá từ ảnh / tra giá theo mã", systemImage: "camera.viewfinder")
                }
            }

            Section {
                NavigationLink { AISettingsView() } label: {
                    LabeledContent("Trợ lý AI", value: store.aiConfig.map { $0.provider.label } ?? "Chưa cấu hình")
                }
            }

            Section("Bảo mật") {
                Toggle("Khoá bằng Face ID", isOn: $faceID)
                NavigationLink("Đổi mật khẩu") { ChangePasswordView() }
            }

            Section("Giao diện") {
                Picker("Giao diện", selection: $appearance) {
                    Text("Tối").tag("dark")
                    Text("Sáng").tag("light")
                    Text("Theo máy").tag("system")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Xoá toàn bộ dữ liệu (làm lại từ đầu)", systemImage: "trash", role: .destructive) { confirmReset = true }
                if let resetMessage { Text(resetMessage).font(.footnote).foregroundStyle(Theme.muted) }
            } header: {
                Text("Dữ liệu")
            } footer: {
                Text("Xoá tài sản, giao dịch, sổ tiết kiệm của tài khoản này (dùng chung với web). Giá thị trường được giữ lại.")
            }

            Section("Ứng dụng") {
                LabeledContent("Phiên bản", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                LabeledContent("Hết hạn chữ ký", value: ProvisioningInfo.expiryText)
                Text("App cài bằng Apple ID miễn phí chạy được 7 ngày. Trước hạn, cắm iPhone vào máy tính và bấm Start trong Sideloadly để cài lại — dữ liệu vẫn giữ nguyên.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }

            Section {
                Button("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await store.signOut() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Cài đặt")
        .confirmationDialog("Xoá TOÀN BỘ tài sản, giao dịch, sổ tiết kiệm? Không thể hoàn tác.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Xoá hết", role: .destructive) {
                Task {
                    let n = store.portfolio.assets.count
                    let err = await store.perform { try await store.repo.resetAll(expectedAssets: n) }
                    resetMessage = err ?? "Đã xoá toàn bộ dữ liệu. Bắt đầu lại từ đầu."
                }
            }
        }
    }
}

/// "Giá Crypto / Giá Vàng / Tỷ giá USDT" buttons.
struct PriceUpdateSection: View {
    @Environment(AppStore.self) private var store
    @State private var running: Repository.PriceClass?
    @State private var message: String?
    @State private var updated: [(String, Double)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App tự cập nhật giá mỗi khi mở (tối đa 15 phút/lần). Bấm để lấy ngay: chứng khoán từ SSI, quỹ từ Fmarket, vàng từ PNJ (giá mua vào), coin từ Binance.")
                .font(.footnote).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(Repository.PriceClass.allCases, id: \.self) { button($0, $0.label) }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
            if !updated.isEmpty {
                VStack(spacing: 6) {
                    ForEach(updated.indices, id: \.self) { i in
                        HStack {
                            Text(updated[i].0).font(.money(14, weight: .semibold))
                            Spacer()
                            Text(Fmt.vnd(updated[i].1)).font(.money(14)).foregroundStyle(Theme.gold)
                        }
                    }
                }
                .padding(10)
                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Các nguồn giá Việt Nam là không chính thức; nếu một mã không có giá, sửa tay trong mã đó hoặc nhờ AI tra giá bên dưới.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
    }

    private func button(_ cls: Repository.PriceClass, _ label: String) -> some View {
        Button {
            Task { await run(cls) }
        } label: {
            HStack(spacing: 6) {
                if running == cls { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                Text(label)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(running != nil)
    }

    private func run(_ cls: Repository.PriceClass) async {
        running = cls
        message = nil
        updated = []
        defer { running = nil }
        do {
            let r = try await store.repo.updatePrices(cls, assets: store.portfolio.assets)
            message = r.message
            updated = r.updated
            await store.reload()
        } catch {
            message = "Lỗi: \(error.vietnamese)"
        }
    }
}

/// AI reads prices from a photo, or looks them up by symbol (web: components/price-from-image.tsx).
struct PriceFromAIView: View {
    @Environment(AppStore.self) private var store
    @State private var symbols = ""
    @State private var loading = false
    @State private var error: String?
    @State private var prices: [AIService.ReadPrice] = []
    @State private var include: Set<UUID> = []
    @State private var usdtRate: Double?
    @State private var done: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Chụp bảng giá để AI đọc, HOẶC gõ mã để AI tra giá hiện tại (vd \"VNM FPT VCBF-BCF\"). Tra giá theo mã chính xác nhất khi nhà cung cấp là Anthropic (có tìm web); đọc ảnh cần OpenAI/Anthropic.")
                    .font(.footnote).foregroundStyle(Theme.muted)

                if store.aiConfig == nil {
                    Disclaimer(AppError.aiNotConfigured.vietnamese)
                } else if prices.isEmpty {
                    ImagePickerButtons { img in Task { await run(text: nil, image: img) } }
                    HStack(spacing: 8) {
                        TextField("vd VNM FPT VCBF-BCF", text: $symbols)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled().fieldStyle()
                        Button("Tra giá") { Task { await run(text: symbols, image: nil) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(symbols.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                    }
                    if loading { HStack { ProgressView(); Text("Đang đọc…") } }
                } else {
                    VStack(spacing: 0) {
                        ForEach(prices) { p in
                            HStack {
                                Toggle(isOn: Binding(get: { include.contains(p.id) },
                                                     set: { if $0 { include.insert(p.id) } else { include.remove(p.id) } })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.symbol).font(.money(14, weight: .semibold))
                                        Text("\(p.assetClass.label) · \(Fmt.amount(p.price)) \(p.currency)")
                                            .font(.caption).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            Text("→ \(Fmt.vnd(p.vnd(usdtRate: usdtRate)))").font(.money(13)).foregroundStyle(Theme.gold)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Divider().overlay(Theme.border)
                        }
                    }
                    .card(padding: 14)
                    HStack(spacing: 10) {
                        SecondaryButton(title: "Huỷ") { prices = [] }
                        PrimaryButton(title: "Lưu \(include.count) giá", busy: loading, disabled: include.isEmpty) {
                            Task { await save() }
                        }
                    }
                }
                if let error { ErrorBox(text: error) }
                if let done { Text(done).font(.footnote).foregroundStyle(Theme.muted) }
            }
            .padding(16)
        }
        .screen()
        .navigationTitle("AI đọc / tra giá")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run(text: String?, image: UIImage?) async {
        guard let cfg = store.aiConfig else { return }
        loading = true
        error = nil
        done = nil
        defer { loading = false }
        do {
            let r = try await AIService.prices(cfg, text: text, image: image?.aiImage(), assets: store.portfolio.assets)
            if r.prices.isEmpty { error = "Không đọc được giá nào." }
            prices = r.prices
            usdtRate = r.usdtRate
            include = Set(r.prices.map(\.id))
        } catch {
            self.error = error.vietnamese
        }
    }

    private func save() async {
        let entries = prices.filter { include.contains($0.id) }.map { ($0.symbol, $0.vnd(usdtRate: usdtRate)) }.filter { $0.1 > 0 }
        loading = true
        defer { loading = false }
        if let err = await store.perform({ try await store.repo.saveReadPrices(entries.map { (symbol: $0.0, priceVnd: $0.1) }) }) {
            error = err
        } else {
            done = "Đã cập nhật giá cho \(entries.count) mã."
            prices = []
        }
    }
}

/// Provider / model / API key — stored in Supabase user_settings, shared with the web.
struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var provider = AIProvider.anthropic
    @State private var model = ""
    @State private var apiKey = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker("Nhà cung cấp", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                }
                TextField("Model (để trống = \(provider.defaultModel))", text: $model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(store.settings?.aiApiKey?.isEmpty == false ? "API key (để trống = giữ key cũ)" : "API key", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } footer: {
                Text("Cấu hình lưu trong tài khoản Supabase của bạn (chung với web, chỉ bạn đọc được). Ảnh cần OpenAI hoặc Anthropic; DeepSeek chỉ đọc chữ.")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if busy { ProgressView() }; Text("Lưu cấu hình AI") }
                }
                .disabled(busy)
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Trợ lý AI")
        .onAppear {
            provider = store.settings?.aiProvider ?? .anthropic
            model = store.settings?.aiModel ?? ""
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        let err = await store.perform { try await store.repo.saveSettings(provider: provider, model: model, apiKey: apiKey) }
        message = err ?? "Đã lưu cấu hình AI."
        if err == nil { apiKey = "" }
    }
}

struct ChangePasswordView: View {
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                SecureField("Mật khẩu mới (tối thiểu 6 ký tự)", text: $password)
                SecureField("Nhập lại mật khẩu mới", text: $confirm)
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if busy { ProgressView() }; Text("Đổi mật khẩu") }
                }
                .disabled(busy || password.count < 6 || password != confirm)
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Đổi mật khẩu")
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await SupabaseClient.shared.updatePassword(password)
            message = "Đã đổi mật khẩu (áp dụng cho cả web)."
            password = ""
            confirm = ""
        } catch {
            message = "Lỗi: \(error.vietnamese)"
        }
    }
}
