import SwiftUI

struct ProviderIndicator: View {
    let provider: AgentProvider
    let showLabel: Bool

    init(_ provider: AgentProvider, showLabel: Bool = false) {
        self.provider = provider
        self.showLabel = showLabel
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: provider.iconName)
                .font(.system(size: showLabel ? 10 : 12))
                .foregroundColor(.white)

            if showLabel {
                Text(provider.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, showLabel ? 6 : 4)
        .padding(.vertical, showLabel ? 4 : 4)
        .background(
            Circle()
                .fill(provider.tintColor.opacity(0.8))
        )
    }
}

#Preview {
    VStack(spacing: 10) {
        ForEach(AgentProvider.allCases, id: \.self) { provider in
            HStack {
                ProviderIndicator(provider)
                ProviderIndicator(provider, showLabel: true)
            }
        }
    }
    .padding()
    .background(.black)
}
