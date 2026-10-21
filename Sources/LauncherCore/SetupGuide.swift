import Foundation

public enum SetupStep: String, Equatable, Sendable {
    case unsupportedChip
    case rosetta
    case runtime
    case steam
    case ready
}

public struct SetupStatus: Equatable, Sendable {
    public var step: SetupStep
    public var title: String
    public var detail: String

    public init(step: SetupStep, title: String, detail: String) {
        self.step = step
        self.title = title
        self.detail = detail
    }
}

public enum ServiceHealth: String, Equatable, Sendable {
    case ok
    case missing
    case optionalMissing
}

public struct ServiceStatus: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String
    public var symbol: String
    public var health: ServiceHealth

    public init(id: String, name: String, detail: String, symbol: String, health: ServiceHealth) {
        self.id = id
        self.name = name
        self.detail = detail
        self.symbol = symbol
        self.health = health
    }
}

public enum SetupGuide {
    public static func status(doctor: DoctorReport, steamConfigured: Bool) -> SetupStatus {
        if doctor.chip != "arm64" {
            return SetupStatus(
                step: .unsupportedChip,
                title: "Нужен Mac на Apple Silicon",
                detail: "MacGamer запускает Windows-игры через Rosetta и работает только на компьютерах с чипом Apple."
            )
        }
        if !doctor.rosettaInstalled {
            return SetupStatus(
                step: .rosetta,
                title: "Установите Rosetta",
                detail: "Rosetta нужна, чтобы Windows-игры запускались на Apple Silicon. Это стандартный компонент macOS."
            )
        }
        if !doctor.runtimeInstalled {
            return SetupStatus(
                step: .runtime,
                title: "Установите среду запуска",
                detail: "Wine уже входит в MacGamer. Останется скачать графические компоненты — это займёт несколько минут."
            )
        }
        if !steamConfigured {
            return SetupStatus(
                step: .steam,
                title: "Укажите Windows Steam",
                detail: "Скачайте установщик Steam для Windows с сайта Steam и выберите SteamSetup.exe. Затем войдите в аккаунт и установите игру — она появится в библиотеке."
            )
        }
        return SetupStatus(
            step: .ready,
            title: "Готово к играм",
            detail: "Steam подключён. Откройте клиент, установите игру и нажмите «Играть»."
        )
    }

    public static func status(doctor: DoctorReport, bottles: [BottleConfig]) -> SetupStatus {
        status(doctor: doctor, steamConfigured: isSteamConfigured(bottles))
    }

    public static func services(doctor: DoctorReport, bottles: [BottleConfig]) -> [ServiceStatus] {
        services(doctor: doctor, steamConfigured: isSteamConfigured(bottles))
    }

    public static func services(doctor: DoctorReport, steamConfigured: Bool) -> [ServiceStatus] {
        let siliconOK = doctor.chip == "arm64"
        let runtimeDetail: String
        if doctor.runtimeInstalled {
            runtimeDetail = doctor.runtimeId ?? "установлена"
        } else {
            runtimeDetail = "не установлена"
        }
        let d3dDetail: String
        let d3dHealth: ServiceHealth
        if doctor.gptkImported {
            d3dDetail = "импортирован"
            d3dHealth = .ok
        } else if doctor.gptkCapable {
            d3dDetail = "не импортирован, нужен для DirectX 12"
            d3dHealth = .optionalMissing
        } else {
            d3dDetail = "недоступен в текущей среде"
            d3dHealth = .optionalMissing
        }
        return [
            ServiceStatus(
                id: "silicon",
                name: "Apple Silicon",
                detail: siliconOK ? doctor.chip : "нужен чип Apple",
                symbol: "cpu",
                health: siliconOK ? .ok : .missing
            ),
            ServiceStatus(
                id: "rosetta",
                name: "Rosetta",
                detail: doctor.rosettaInstalled ? "установлена" : "не установлена",
                symbol: "translate",
                health: doctor.rosettaInstalled ? .ok : .missing
            ),
            ServiceStatus(
                id: "runtime",
                name: "Среда запуска",
                detail: runtimeDetail,
                symbol: "cube.box.fill",
                health: doctor.runtimeInstalled ? .ok : .missing
            ),
            ServiceStatus(
                id: "steam",
                name: "Steam",
                detail: steamConfigured ? "подключён" : "не указан",
                symbol: "gamecontroller.fill",
                health: steamConfigured ? .ok : .missing
            ),
            ServiceStatus(
                id: "d3dmetal",
                name: "D3DMetal",
                detail: d3dDetail,
                symbol: "square.stack.3d.up.fill",
                health: d3dHealth
            )
        ]
    }

    public static func isSteamConfigured(_ bottles: [BottleConfig]) -> Bool {
        bottles.contains { bottle in
            bottle.role == .steam && !(bottle.steamExePath ?? "").isEmpty
        }
    }
}
