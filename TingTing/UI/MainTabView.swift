import SwiftUI

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = Tabs.home
    @State private var showAdd = false
    @State private var addRoute: AddRoute?

    enum Tabs: Hashable { case home, assets, add, future, ai }

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { new in
            // The middle "+" tab opens the add sheet instead of switching tabs (web FAB).
            if new == .add { showAdd = true } else { tab = new }
        })) {
            Tab("Home", systemImage: "house", value: Tabs.home) {
                NavigationStack { HomeView() }
            }
            Tab("Tài sản", systemImage: "wallet.bifold", value: Tabs.assets) {
                NavigationStack { AssetsHubView() }
            }
            Tab("Thêm", systemImage: "plus.circle.fill", value: Tabs.add) {
                Color.clear
            }
            Tab("Tương lai", systemImage: "chart.line.uptrend.xyaxis", value: Tabs.future) {
                NavigationStack { FutureView() }
            }
            Tab("AI", systemImage: "sparkles", value: Tabs.ai) {
                NavigationStack { AIChatView() }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddSheet { route in
                showAdd = false
                addRoute = route
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(get: { store.showPriceChanges && !store.isLocked },
                                    set: { store.showPriceChanges = $0 })) {
            PriceChangesView().presentationDetents([.medium, .large])
        }
        .sheet(item: $addRoute) { route in
            NavigationStack {
                switch route {
                case .manual: CreateAssetView()
                case .aiText: AIEntryView(startWithImage: false)
                case .aiImage: AIEntryView(startWithImage: true)
                }
            }
        }
    }
}

enum AddRoute: String, Identifiable {
    case aiImage, aiText, manual
    var id: String { rawValue }
}

/// Bottom sheet with the three ways to add (same as the web FAB sheet).
struct AddSheet: View {
    var onPick: (AddRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thêm giao dịch").font(.headline).padding(.bottom, 4)
            option(.aiImage, icon: "camera", title: "Chụp / Upload ảnh", desc: "AI đọc ảnh lệnh → điền sẵn form")
            option(.aiText, icon: "text.bubble", title: "Hỏi AI", desc: "Gõ tự nhiên, vd \"mua 200 VCB giá 93.200\"")
            option(.manual, icon: "pencil", title: "Nhập thủ công", desc: "Chọn loại (CK/coin/quỹ/vàng/sổ) → điền form")
            Spacer()
        }
        .padding(20)
        .background(Theme.background)
    }

    private func option(_ route: AddRoute, icon: String, title: String, desc: String) -> some View {
        Button { onPick(route) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 42, height: 42)
                    .background(Theme.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold).foregroundStyle(Color.primary)
                    Text(desc).font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }
}
