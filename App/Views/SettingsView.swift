import SwiftUI
import AppKit

/// Settings (spec "Fonts and sizing"): the code font and size. Default
/// is the system monospace at 12 points. Stored in UserDefaults and
/// read by `CodeStyle.font`, so every column re-renders on change.
struct SettingsView: View {
    @AppStorage(CodeStyle.fontNameKey) private var fontName = ""
    @AppStorage(CodeStyle.fontSizeKey) private var fontSize = 12.0

    private var monospaceFonts: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted()
    }

    var body: some View {
        Form {
            Section(String(localized: "Code")) {
                Picker(String(localized: "Font"), selection: $fontName) {
                    Text(String(localized: "System monospace")).tag("")
                    ForEach(monospaceFonts, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Slider(value: $fontSize, in: 9...24, step: 1) { Text(String(localized: "Size")) }
                    Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Text("func sample(x: Int) -> Int { x * 2 }  // \(Int(fontSize)) pt")
                    .font(Font(CodeStyle.font))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
                Button(String(localized: "Reset to System Monospace 12 pt")) { fontName = ""; fontSize = 12 }
                    .disabled(fontName.isEmpty && fontSize == 12)
            }
            Section(String(localized: "Review")) {
                Toggle(String(localized: "Ask about blind mode on every new session"), isOn: Binding(
                    get: { !UserDefaults.standard.bool(forKey: SessionController.blindPromptShownKey) },
                    set: { UserDefaults.standard.set(!$0, forKey: SessionController.blindPromptShownKey) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.bottom, 8)
    }
}
