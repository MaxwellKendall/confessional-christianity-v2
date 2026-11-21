// The Lord's Day tab (pillar two, TKL-825). The week's card feed (TKL-862),
// the camera (TKL-860) and the archive (TKL-865) are separate tickets; until
// they land this is the tab's empty state from TKL-885's prototype, saying what
// the pillar does.
import SwiftUI

struct LordsDayTabView: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pillar two")
                        .labelCaps(size: 10.5, tracking: 0.16)
                        .padding(.top, 16)
                    Text("The Lord's Day")
                        .font(.ccDisplay(25, semibold: true))
                        .foregroundStyle(.ccInk)
                        .padding(.top, 4)
                        .padding(.bottom, 16)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Keep Sunday's sermon")
                            .font(.ccDisplay(19, semibold: true))
                            .foregroundStyle(.ccInk)
                            .padding(.bottom, 8)
                        Text("Take notes on Sunday's sermon and photograph them after church. The app turns them into a card for each day of the week: a key point, a verse, a quote, and a prayer for the Sunday ahead.")
                            .font(.ccBody(15.5))
                            .lineSpacing(3)
                            .foregroundStyle(.ccInk2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Photographing your notes arrives in the next update.")
                            .font(.system(size: 13))
                            .foregroundStyle(.ccInk3)
                            .padding(.top, 14)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ccFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ccHairline, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                .frame(maxWidth: 704)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ccCard)
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations(path: $path)
        }
        .tint(.ccInk)
    }
}
