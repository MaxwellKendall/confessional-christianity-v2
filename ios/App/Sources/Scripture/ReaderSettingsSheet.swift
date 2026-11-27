import SwiftUI
import DomainKit

/// The reader's "READING" sheet (TKL-838 `sheetSettings`, TKL-972): text size in five
/// steps, a live preview line, verse numbers, confession marks and Dark. Every change
/// writes through the binding at once; the reader saves it to `ReaderSettings`.
struct ReaderSettingsSheet: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("READING")
                .font(.ccDisplay(15, semibold: true))
                .tracking(1.2)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            row(border: true) {
                Text("Text size")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Array(ReaderSettings.textSizeRange), id: \.self) { step in
                        sizeButton(step)
                    }
                }
            }

            preview
                .padding(.top, 16)
                .padding(.bottom, 4)

            row(border: true) {
                Toggle("Verse numbers in chapters", isOn: $settings.showVerseNumbers)
            }
            row(border: true) {
                Toggle("Show what the confessions cite", isOn: $settings.showConfessionMarks)
            }
            row(border: false) {
                Toggle("Dark", isOn: $settings.dark)
            }
        }
        .font(.ccUI(15))
        .tint(.ccChapel)
        .foregroundStyle(.ccInk)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationBackground(.ccSurface)
        .presentationDetents([.height(436)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ChapelRadius.sheet)
    }

    private func row<Content: View>(border: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack { content() }
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) {
                if border { Rectangle().fill(.ccLine).frame(height: 1) }
            }
    }

    private func sizeButton(_ step: Int) -> some View {
        let on = settings.textSize == step
        return Button { settings.textSize = step } label: {
            Text("A")
                .font(.ccBody(readerSettingsSizeButtonFont(step)))
                .frame(width: 40, height: 40)
                .foregroundStyle(on ? .ccOnChapel : .ccInk)
                .background(on ? Color.ccChapel : .clear, in: RoundedRectangle(cornerRadius: ChapelRadius.well))
                .overlay {
                    RoundedRectangle(cornerRadius: ChapelRadius.well)
                        .strokeBorder(on ? Color.ccChapel : .ccLine)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -2)
        .accessibilityLabel("Text size \(step + 1) of \(ReaderSettings.textSizeRange.count)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("reader-text-size-\(step)")
    }

    private var preview: some View {
        let size = readerChapterFontSize(textSize: settings.textSize)
        var line = AttributedString()
        if settings.showVerseNumbers {
            var number = AttributedString("1")
            number.font = .system(size: size * 0.55)
            number.baselineOffset = size * 0.3
            number.foregroundColor = .ccInk3
            line += number + AttributedString("\u{2009}")
        }
        line += AttributedString("The LORD is my shepherd; I shall not want.")
        return Text(line)
            .font(.ccBody(size))
            .lineSpacing(size * (1.5 - 1.254))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ccPaper, in: RoundedRectangle(cornerRadius: ChapelRadius.card))
            .accessibilityLabel("Preview: The LORD is my shepherd; I shall not want.")
    }
}
