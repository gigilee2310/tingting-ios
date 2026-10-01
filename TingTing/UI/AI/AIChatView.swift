import SwiftUI

/// "Hỏi AI về tài sản" (web: app/ai + components/ai-chat.tsx).
struct AIChatView: View {
    @Environment(AppStore.self) private var store

    struct Msg: Identifiable {
        let id = UUID()
        let fromUser: Bool
        let text: String
    }

    @State private var msgs: [Msg] = []
    @State private var input = ""
    @State private var loading = false

    private let suggestions = ["Tôi đang lời hay lỗ?", "Tỷ trọng crypto của tôi là bao nhiêu?", "Mã nào đang lãi nhiều nhất?"]

    var body: some View {
        let p = store.portfolio
        let total = p.totalAssets()
        let cost = p.totalCost()
        let pl = total - cost
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tóm tắt nhanh (do code tính)").font(.footnote).foregroundStyle(Theme.muted)
                        HStack { Text("Tổng tài sản"); Spacer(); Text(Fmt.vnd(total)).font(.money(14)) }
                        HStack {
                            Text("Lãi/lỗ so với vốn")
                            Spacer()
                            Text("\(Fmt.vnd(pl, sign: true)) (\(Fmt.percent(cost > 0 ? pl / cost : 0)))")
                                .font(.money(14)).foregroundStyle(Theme.pl(pl))
                        }
                    }
                    .card()

                    if store.aiConfig == nil {
                        Disclaimer("Chat AI cần cấu hình nhà cung cấp. Vào Cài đặt (ảnh đại diện ở trang Home) → Trợ lý AI để chọn Anthropic / OpenAI / DeepSeek và nhập API key.")
                    } else if msgs.isEmpty {
                        SectionTitle("Gợi ý câu hỏi")
                        ForEach(suggestions, id: \.self) { s in
                            Button { Task { await ask(s) } } label: {
                                Text(s).foregroundStyle(Color.primary).card(padding: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(msgs) { m in
                        HStack {
                            if m.fromUser { Spacer(minLength: 40) }
                            Text(m.text)
                                .textSelection(.enabled)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .foregroundStyle(m.fromUser ? Theme.onGold : Color.primary)
                                .background(m.fromUser ? Theme.gold : Theme.panel, in: RoundedRectangle(cornerRadius: 16))
                            if !m.fromUser { Spacer(minLength: 40) }
                        }
                        .id(m.id)
                    }
                    if loading { ProgressView().padding(10).card(padding: 6).frame(width: 60) }

                    Text("AI chỉ diễn giải các con số do hệ thống truy vấn & tính sẵn — không tự tính hay bịa số liệu.")
                        .font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
                }
                .padding(16)
            }
            .onChange(of: msgs.count) { _, _ in
                if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .screen()
        .navigationTitle("AI Assistant")
        .safeAreaInset(edge: .bottom) {
            if store.aiConfig != nil {
                HStack(spacing: 8) {
                    TextField("Hỏi về tài sản của bạn…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .fieldStyle()
                        .onSubmit { Task { await ask(input) } }
                    Button { Task { await ask(input) } } label: {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 44, height: 44)
                            .background(Theme.gold, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Theme.onGold)
                    }
                    .disabled(loading || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func ask(_ q: String) async {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !loading, let cfg = store.aiConfig else { return }
        input = ""
        msgs.append(Msg(fromUser: true, text: question))
        loading = true
        defer { loading = false }
        do {
            let answer = try await AIService.chat(cfg, question: question, portfolio: store.portfolio)
            msgs.append(Msg(fromUser: false, text: answer.isEmpty ? "(AI không trả lời)" : answer))
        } catch {
            msgs.append(Msg(fromUser: false, text: "⚠ \(error.vietnamese)"))
        }
    }
}
