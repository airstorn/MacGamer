import LauncherCore
import SwiftUI

struct ServiceStatusIcon: View {
    let health: ServiceHealth
    var busy: Bool = false

    var body: some View {
        Group {
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .accessibilityLabel(label)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var symbol: String {
        switch health {
        case .ok:
            return "checkmark.circle.fill"
        case .missing:
            return "xmark.circle.fill"
        case .optionalMissing:
            return "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch health {
        case .ok:
            return .green
        case .missing:
            return .red
        case .optionalMissing:
            return .orange
        }
    }

    private var label: String {
        switch health {
        case .ok:
            return "Готово"
        case .missing:
            return "Не настроено"
        case .optionalMissing:
            return "Необязательно"
        }
    }
}

struct ServiceStatusRow: View {
    let service: ServiceStatus
    var busy: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: service.symbol)
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .lineLimit(1)
                Text(service.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            ServiceStatusIcon(health: service.health, busy: busy)
        }
        .accessibilityElement(children: .combine)
    }
}
