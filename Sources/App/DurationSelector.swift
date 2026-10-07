import SwiftUI

func durationLabel(_ choice: DurationChoice) -> String {
    switch choice {
    case .minutes(let value): "\(value)분"
    case .unlimited: "무제한"
    }
}

struct DurationSelector: View {
    @Binding var minutes: Int
    @Binding var unlimited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("방지 시간", selection: $unlimited) {
                Text("분 단위").tag(false)
                Text("무제한").tag(true)
            }
            .pickerStyle(.segmented)

            if !unlimited {
                HStack {
                    Text("잠자기 방지 시간")
                    TextField("", value: $minutes, format: .number)
                        .frame(width: 76)
                        .textFieldStyle(.roundedBorder)
                    Text("분")
                }
            }
        }
    }
}
