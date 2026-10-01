import PhotosUI
import SwiftUI

// MARK: - Card

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var background: Color = Theme.panel

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16, background: Color = Theme.panel) -> some View {
        modifier(CardModifier(padding: padding, background: background))
    }

    /// Standard screen background.
    func screen() -> some View {
        scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Text helpers

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.muted)
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 12
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// Key–value ledger rows inside a card.
struct LedgerRows: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack {
                    Text(row.0).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(row.1).font(.money(14)).multilineTextAlignment(.trailing)
                }
                .font(.system(size: 14))
                .padding(.vertical, 11)
                if i < rows.count - 1 { Divider().overlay(Theme.border) }
            }
        }
        .card(padding: 14)
    }
}

struct Disclaimer: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.25), lineWidth: 1))
    }
}

struct ErrorBox: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(Theme.negative)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.negative.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Inputs

/// Numeric input that shows thousands separators while typing (web NumInput).
struct NumberField: View {
    let placeholder: String
    @Binding var text: String
    var allowsDecimal = true

    init(_ placeholder: String, text: Binding<String>, allowsDecimal: Bool = true) {
        self.placeholder = placeholder
        _text = text
        self.allowsDecimal = allowsDecimal
    }

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { Self.grouped(text) },
            set: { text = Self.raw($0, allowsDecimal: allowsDecimal) }
        ))
        .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
        .font(.money(16))
        .fieldStyle()
    }

    static func raw(_ s: String, allowsDecimal: Bool) -> String {
        var out = ""
        var seenDot = false
        for ch in s {
            if ch.isNumber { out.append(ch) }
            // Vietnamese keyboards may produce "," as the decimal separator: treat a lone trailing one as "."
            else if allowsDecimal && ch == "." && !seenDot { out.append("."); seenDot = true }
        }
        return out
    }

    static func grouped(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = String(parts[0])
        var grouped = ""
        for (i, ch) in intPart.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        grouped = String(grouped.reversed())
        if parts.count > 1 { grouped += "." + parts[1] }
        return grouped
    }
}

extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }
}

struct Field<Content: View>: View {
    let label: String
    var warn = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionTitle(label)
                if warn {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel("AI chưa chắc trường này")
                }
            }
            content
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var busy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Theme.onGold) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Theme.onGold)
            .background(Theme.gold, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(busy || disabled)
        .opacity(busy || disabled ? 0.55 : 1)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(role == .destructive ? Theme.negative : Color.primary)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        }
    }
}

// MARK: - Image picking (camera or library) → JPEG base64 for AI

struct ImagePickerButtons: View {
    var onImage: (UIImage) -> Void
    @State private var item: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        HStack(spacing: 10) {
            Button { showCamera = true } label: {
                Label("Chụp ảnh", systemImage: "camera")
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            PhotosPicker(selection: $item, matching: .images) {
                Label("Chọn ảnh", systemImage: "photo")
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
        }
        .buttonStyle(.bordered)
        .tint(Theme.gold)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    onImage(img)
                }
                item = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in onImage(img) }.ignoresSafeArea()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension UIImage {
    /// Downscaled JPEG for AI vision calls (keeps requests small).
    func aiImage(maxSide: CGFloat = 1600) -> AIImage? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return AIImage(base64: data.base64EncodedString(), mediaType: "image/jpeg")
    }
}
