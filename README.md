# MacGamer

Личный лаунчер Windows-игр на Apple Silicon. Открывает указанный вами Windows Steam через Wine и подхватывает установленные игры из `steamapps`. Steam, игры и CrossOver утилита не скачивает и не требует.

## Требования

- Mac на Apple Silicon, macOS 14+
- [Xcode](https://developer.apple.com/xcode/) со Swift 6
- Git LFS — в репозитории бинарный Wine (~189 MB)
- Установщик Windows Steam: `SteamSetup.exe` или уже лежащий `steam.exe` ([сайт Steam](https://store.steampowered.com/about/))

```bash
git lfs install
git clone <url-репозитория> MacGamer
cd MacGamer
git lfs pull
```

## Сборка

```bash
make app
```

Собирает release, рисует иконку, упаковывает `MacGamer.app`, подписывает ad-hoc и копирует в `~/Applications`.

```bash
make run
```

То же и сразу открывает приложение.

Значок не лежит в git: при каждой сборке его рисует `tools/make-app-icon.swift` (геймпад на тёмном квадрате) и кладёт в `.app` как `AppIcon.icns`.

Другие цели:

```bash
make test
make cli
swift run macgamer doctor
swift run MacGamerApp
```

`swift run MacGamerApp` — запуск GUI без установки в Applications.

## Первый запуск

Откройте MacGamer. Пока окружение не готово, показывается мастер. Шаг считается по диску: если runtime уже стоит, мастер начнётся со Steam.

1. **Rosetta** — стандартный компонент macOS для x86_64.
2. **Среда запуска** — Wine уже в приложении; скачаются DXMT и DXVK.
3. **Steam** — «Выбрать SteamSetup.exe», войти в клиент, установить игру.

В боковой панели статусы сервисов:

| Сервис | Зелёный | Красный / оранжевый |
| --- | --- | --- |
| Apple Silicon | чип Apple | другой Mac |
| Rosetta | установлена | нет |
| Среда запуска | Wine на месте | не установлена |
| Steam | путь указан | не указан |
| D3DMetal | GPTK импортирован | необязательно, ещё нет |

Дальше в библиотеке: **Открыть Steam**, **Синхронизировать**, **Играть**.

Если указали установщик, один раз пройдите мастер Steam внутри Wine. Перед каждым открытием Steam ставится обёртка `steamwebhelper` (`--disable-gpu --single-process`), иначе окно часто остаётся чёрным.

Запасной CLI:

```bash
swift run macgamer runtime install
swift run macgamer steam use /path/to/SteamSetup.exe
swift run macgamer steam open
swift run macgamer steam sync
swift run macgamer run --app 570
```

`runtime install` берёт встроенный `winecx-26.2`. Другой архив — `--archive`. Переустановка — `--force`.

Чтобы снова увидеть мастер установки среды, временно уберите runtime:

```bash
mv "$HOME/Library/Application Support/MacGamer/runtimes/winecx-26.2" \
   "$HOME/Library/Application Support/MacGamer/runtimes/winecx-26.2.bak"
```

## Настройки игры

В библиотеке выберите игру → **Дополнительно**.

| Параметр | Смысл |
| --- | --- |
| Бэкенд | чем рисовать DirectX. По умолчанию как у бутылки — Metal (DXMT) |
| HUD | не игровой интерфейс, а оверлей слоя: FPS и диагностика. Для DXMT — `DXMT_DEBUG=1`, для DXVK — `DXVK_HUD=1`. На Wine и D3DMetal не действует. Для обычной игры лучше выключен |
| Виртуальный стол | окно Wine фиксированного размера (`explorer /desktop=…`). На клиент Steam не влияет |

```bash
swift run macgamer game set --app 570 --backend dxvk --hud on --desktop 1920x1080
swift run macgamer run --app 570 --backend dxmt --no-hud --desktop off
swift run macgamer backend set --bottle <id> --backend dxvk
```

| Бэкенд | В интерфейсе | Назначение |
| --- | --- | --- |
| `dxmt` | Metal (DXMT) | DirectX 10/11 → Metal |
| `dxvk` | Vulkan (DXVK) | DirectX 9–11 через MoltenVK |
| `wined3d` | Wine | запасной путь Wine |
| `d3dmetal` | D3DMetal | DirectX 11/12 после импорта GPTK |

Некоторым играм нужен Visual C++ Redistributable:

```bash
swift run macgamer deps vcrun2022 --bottle <id> --installer /path/to/VC_redist.x64.exe
```

## Опционально: D3DMetal (GPTK)

Apple Game Porting Toolkit в репозиторий не входит. Скачайте DMG у Apple сами:

```bash
swift run macgamer gptk import /path/to/Game_Porting_Toolkit.dmg
swift run macgamer backend set --bottle <id> --backend d3dmetal
```

## Звук

Щелчки в звуке — патч `winecoreaudio` (нужно дерево после `tools/build-winecx.sh`):

```bash
tools/patch-winecoreaudio.sh
```

Откат: `winecoreaudio.so.bak-pre-period-patch` рядом с `.so`. Лучше выход 48 kHz, проводной, без Spatial Audio.

## Данные

`~/Library/Application Support/MacGamer/`

| Путь | Содержимое |
| --- | --- |
| `runtimes/` | Wine, DXMT, DXVK |
| `bottles/` | префиксы Wine |
| `library.json` | библиотека игр |
| `logs/` | логи запусков |
| `downloads/` | архивы runtime |
| `store/d3dmetal/` | импортированный GPTK |

```bash
swift run macgamer log summarize ~/Library/Application\ Support/MacGamer/logs/<gameId>/<file>.log
```

В GUI сводка — кнопка **Лог**.

## CLI

```text
macgamer doctor
macgamer runtime install [--archive <winecx.tar.xz>] [--force]
macgamer bottle create --name <name> [--role steam|generic]
macgamer bottle list
macgamer steam use <path-to-steam.exe|SteamSetup.exe>
macgamer steam open [--dry-run]
macgamer steam sync
macgamer game set --app <id> [--backend dxmt|dxvk|d3dmetal|wined3d|bottle] [--hud on|off] [--desktop 1920x1080|off]
macgamer run --exe <path> --bottle <id> [--backend …] [--hud|--no-hud] [--desktop 1920x1080|off] [--dry-run]
macgamer run --app <steamAppId> [--backend …|bottle] [--hud|--no-hud] [--desktop 1920x1080|off] [--dry-run]
macgamer backend set --bottle <id> --backend <name>
macgamer deps vcrun2022 --bottle <id> [--installer <path>] [--dry-run]
macgamer gptk import <dmg-or-lib-root>
macgamer log summarize <path>
```

## Для сборщиков runtime

Встроенный Wine: `Sources/LauncherCore/BundledRuntime/winecx-26.2-osx64.tar.xz` (Git LFS, LGPL). Обновить бандл: `tools/package-winecx-from-crossover.sh` или `tools/build-winecx.sh`. Пользователю эти скрипты не нужны. FOSS-сборка часто ломает логин Steam.

## Ограничения

- Смена Wine может сбросить сессию Steam.
- Совместимость Windows-игр на Apple Silicon не гарантируется.
- Редкие щелчки звука возможны под нагрузкой Rosetta даже с патчем.

Контракт — в [SPEC.md](SPEC.md).

## Лицензии

Wine (LGPL) поставляется бинарно; исходники — у [CodeWeavers](https://media.codeweavers.com/pub/crossover/source/). DXMT v0.80 (MIT), DXVK (zlib), MoltenVK (Apache-2.0). D3DMetal — по лицензии Apple из DMG у пользователя. Steam и игры в репозиторий не входят.
