import SwiftUI

/// Sheet shown after the opening price refresh: what moved since the last time the app was opened.
struct PriceChangesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let changes = store.priceChanges
        let up = changes.filter { $0.newPrice > $0.oldPrice }.count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tài sản thay đổi").font(.footnote).foregroundStyle(Theme.muted)
                        Text(Fmt.vnd(store.totalChange, sign: true))
                            .font(.money(28, weight: .bold))
                            .foregroundStyle(Theme.pl(store.totalChange))
                        Text("Tổng hiện tại \(Fmt.vnd(store.portfolio.totalAssets())) · \(up) mã tăng, \(changes.count - up) mã giảm")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .card()

                    VStack(spacing: 0) {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { i, c in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Dot(color: Theme.accent(c.type), size: 8)
                                        Text(c.symbol).font(.money(15, weight: .semibold))
                                    }
                                    Text("\(Fmt.vnd(c.oldPrice)) → \(Fmt.vnd(c.newPrice))")
                                        .font(.money(12)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(Fmt.percent(c.percent, decimals: 2))
                                        .font(.money(14, weight: .semibold)).foregroundStyle(Theme.pl(c.percent))
                                    Text(Fmt.vnd(c.valueDelta, compact: true, sign: true))
                                        .font(.money(12)).foregroundStyle(Theme.pl(c.valueDelta))
                                }
                            }
                            .padding(.vertical, 10)
                            if i < changes.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }
                    .card(padding: 14)

                    Text("So với giá đã lưu ở lần mở app trước. Dòng nhỏ bên phải là số tiền thay đổi theo số lượng bạn đang giữ.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    PrimaryButton(title: "Đã xem") { dismiss() }
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Biến động giá")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
