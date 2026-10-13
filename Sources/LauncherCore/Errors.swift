import Foundation

public enum MacGamerError: Error, LocalizedError, Equatable {
    case rosettaMissing
    case runtimeNotInstalled
    case runtimeHashMismatch(component: String)
    case runtimeDownloadFailed(String)
    case wineBinaryMissing
    case wineMacdrvMissing
    case bottleNotFound(String)
    case bottleBroken(String)
    case steamPathMissing
    case steamPathInvalid(String)
    case gptkNotCapable
    case gptkPayloadInvalid(String)
    case gptkNotImported
    case unsupportedBackend(GraphicsBackend)
    case missingExecutable(String)
    case processFailed(String)
    case dependencyFailed(String)
    case manifestMissing
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .rosettaMissing:
            return "Rosetta 2 не установлена. Установите: softwareupdate --install-rosetta --agree-to-license"
        case .runtimeNotInstalled:
            return "Рантайм не установлен. Выполните: macgamer runtime install"
        case .runtimeHashMismatch(let component):
            return "Хеш компонента \(component) не совпал с манифестом"
        case .runtimeDownloadFailed(let detail):
            return "Не удалось скачать рантайм: \(detail)"
        case .wineBinaryMissing:
            return "В установленном рантайме не найден wine64"
        case .wineMacdrvMissing:
            return "Wine не экспортирует macdrv_functions. Нужен winecx из tools/build-winecx.sh"
        case .bottleNotFound(let id):
            return "Бутылка не найдена: \(id)"
        case .bottleBroken(let id):
            return "Префикс бутылки повреждён: \(id)"
        case .steamPathMissing:
            return "Путь к Steam не указан. Выполните: macgamer steam use <path>"
        case .steamPathInvalid(let path):
            return "Неверный путь к Steam: \(path)"
        case .gptkNotCapable:
            return "Текущий Wine не помечен gptkCapable. Бэкенд d3dmetal недоступен"
        case .gptkPayloadInvalid(let detail):
            return "Некорректный GPTK payload: \(detail)"
        case .gptkNotImported:
            return "D3DMetal не импортирован. Укажите DMG через macgamer gptk import <dmg>"
        case .unsupportedBackend(let backend):
            return "Бэкенд недоступен: \(backend.rawValue)"
        case .missingExecutable(let path):
            return "Исполняемый файл не найден: \(path)"
        case .processFailed(let detail):
            return "Ошибка процесса: \(detail)"
        case .dependencyFailed(let detail):
            return "Не удалось установить зависимость: \(detail)"
        case .manifestMissing:
            return "Манифест runtime.json не найден"
        case .io(let detail):
            return detail
        }
    }
}
