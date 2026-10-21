# MacGamer — спецификация

Версия документа: 1.1  
Платформа: macOS 14+ (Apple Silicon)  
Репозиторий: Swift Package (`Package.swift`, Swift 6)

## 1. Назначение

MacGamer — личный лаунчер Windows-игр на Apple Silicon. Он управляет Wine-префиксами («бутылками»), открывает указанный пользователем Windows Steam и синхронизирует установленные игры из `steamapps` без скачивания Steam или игр самой утилитой.

## 2. Цели и нецели

### Цели

- Запуск x86_64 Windows-игр через Wine под Rosetta.
- Один Steam-prefix с автоподхватом `appmanifest_*.acf`.
- Переключаемые графические бэкенды: DXMT, DXVK, WineD3D, опционально D3DMetal (GPTK).
- Понятная диагностика (doctor, логи, ошибки Rosetta/prefix/Steam/GPTK).
- Runtime без обязательного установленного `CrossOver.app` при запуске (winecx в `Application Support`).
- Приемлемый звук через CoreAudio (патч period frames / увеличенный HAL-буфер).

### Нецели

- Не скачивать и не распространять Steam, игры, D3DMetal.
- Не эмулировать Proton / Steam Play Linux.
- Не поддерживать Intel Mac как целевую платформу.
- Не гарантировать совместимость всех Windows-игр.
- Не гарантировать полную тишину underrun под тяжёлой нагрузкой Rosetta.

## 3. Пользовательские сценарии

1. **Первый запуск:** мастер в `MacGamer.app` (Rosetta → встроенный winecx → SteamSetup.exe) → войти в Steam → установить игру → библиотека / `run --app <id>`. CrossOver не требуется. CLI: `runtime install` без `--archive`.
2. **Смена графики:** `backend set` на бутылке; применяется к следующим запускам (Steam UI может идти отдельно от игрового бэкенда).
3. **Импорт GPTK:** пользователь указывает DMG/lib → `gptk import` → доступен `d3dmetal` при `gptkCapable`.
4. **Диагностика:** dry-run команд, `log summarize`, файлы в `logs/`.

## 4. Архитектура

```
macgamer (CLI) ──┐
MacGamerApp (UI)─┼── LauncherCore
                 │     ├── RuntimeStore / Doctor / SetupGuide
                 │     ├── BottleStore / ProcessLauncher / RosettaInstaller
                 │     ├── LaunchPlanner / BackendOverlay
                 │     ├── SteamLibrary / SteamVDF / SteamWebHelperFix
                 │     ├── GPTKImporter / Dependencies / Diagnostics
                 └── данные в ~/Library/Application Support/MacGamer/
```

### Продукты пакета

| Продукт | Тип | Роль |
| --- | --- | --- |
| `LauncherCore` | library | доменная логика |
| `macgamer` | executable | CLI |
| `MacGamerApp` | executable | SwiftUI-оболочка библиотеки; `tools/package-app.sh` упаковывает её в `MacGamer.app` |

Запуск процессов: `/usr/bin/arch -x86_64 <wine> …` с `WINEPREFIX`, `WINEDLLPATH` / overlays, `WINEDLLOVERRIDES`.

## 5. Данные на диске

Корень: `~/Library/Application Support/MacGamer/`

| Путь | Содержимое |
| --- | --- |
| `runtimes/<id>/` | Wine (winecx), overlays DXMT/DXVK, `runtime-info.json` |
| `bottles/<uuid>/bottle.json` | конфиг бутылки |
| `bottles/<uuid>/prefix/` | Wine prefix |
| `library.json` | каталог игр |
| `logs/<gameId>/` | логи запусков |
| `downloads/` | архивы runtime |
| `store/d3dmetal/` | импортированный GPTK (не в git) |

Манифест runtime: `manifest/runtime.json` и копия в `Sources/LauncherCore/Resources/runtime.json`.

### Текущий runtime (контракт)

- `id`: `winecx-26.2`
- Источник для пользователя: встроенный LGPL-архив `Sources/LauncherCore/BundledRuntime/winecx-26.2-osx64.tar.xz` (Git LFS)
- Обновление бандла мантейнером: `tools/package-winecx-from-crossover.sh` или `tools/build-winecx.sh`
- `gptkCapable`: `true` (требуется экспорт `macdrv_functions` в `winemac.so`)
- Компоненты: wine (бандл), DXMT `0.80` builtin, DXVK-macOS async repack
- Установка: `macgamer runtime install [--archive <winecx.tar.xz>] [--force]` — без флагов берёт бандл
- После установки патчится `winecoreaudio.so` (см. §10 / §16)

### Env при запуске (LaunchPlanner)

- `WINEPREFIX`, `WINELOADER`, `WINESERVER`, `WINEDEBUG=-all`
- `WINEDLLOVERRIDES`, `WINEDLLPATH` (overlay + пути Wine)
- `CX_ROOT` = корень runtime
- `DYLD_FALLBACK_LIBRARY_PATH` = `lib64`/`lib` runtime + `/usr/local/lib`
- `SSL_CERT_FILE` / `CURL_CA_BUNDLE` = системный CA bundle (если найден), для TLS Steam/Wine
- Для DXMT: `DXMT_CONFIG`, `ROSETTA_ADVERTISE_AVX=1`

## 6. Модель данных

### BottleConfig

- `id`, `name`, `role` (`steam` | `generic`)
- `windowsVersion` (по умолчанию `win10`)
- `backend` (`dxmt` | `dxvk` | `d3dmetal` | `wined3d`), по умолчанию `dxmt`
- `hud`, `steamExePath?`, `createdAt`
- Одна steam-бутылка на установку (повторный `create --role steam` возвращает существующую)

### GameEntry

- `id`, `name`, `bottleId`, `source` (`steam` | `manual`)
- `steamAppId?`, `installState` (`installing` | `ready` | `updating` | `missing`)
- Опционально: `exe`, `workdir`, `arguments`, `env`, `backend`, `hud`, `virtualDesktop` (`width` × `height`, 640–7680)
- `backend` игры перекрывает бэкенд бутылки; `null` / отсутствие поля — как у бутылки
- `hud` и `virtualDesktop` относятся только к запуску этой игры; клиент Steam (`steam open`) их не использует

### GraphicsBackend

| Значение | Назначение | Условия |
| --- | --- | --- |
| `dxmt` | D3D10/11 → Metal | winecx + `macdrv_functions`; native DLL в `system32` + `winemetal.so` |
| `dxvk` | D3D9–11 → Vulkan/MoltenVK | overlay DXVK |
| `wined3d` | запасной путь Wine | всегда |
| `d3dmetal` | D3D11/12 GPTK | `gptkCapable` и импорт GPTK |

При `backend == wined3d` у бутылки для Steam open (и для запуска игры без своего бэкенда) предпочитается `dxmt`. Явный `wined3d` у игры остаётся `wined3d`.

## 7. CLI-контракт

```
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

Правила:

- Steam/игры не скачиваются утилитой.
- `steam use` принимает `steam.exe` или `SteamSetup.exe` (после установки резолвится в prefix `…/Steam/steam.exe`).
- Перед `steam open` / `run --app` применяется `SteamWebHelperFix` (`--disable-gpu --single-process`).
- `run --app` не ждёт завершения процесса Steam; `run --exe` может ждать.
- `game set` пишет бэкенд, HUD и виртуальный стол в `library.json`; флаги `run --backend/--hud/--no-hud/--desktop` действуют только на этот запуск.
- Включённый стол добавляет `explorer /desktop=mg-<appid>,WxH` перед программой. `steam open` стол не использует.
- Ошибки — через `MacGamerError` с человекочитаемым текстом (`Diagnostics.explain`).

## 8. Графический пайплайн (DXMT)

1. `LaunchPlanner` выбирает бэкенд и overlay.
2. Для `dxmt`: копирует `d3d11/dxgi/d3d10core/winemetal.dll` в `prefix/drive_c/windows/system32`, `winemetal.so` в unix-lib Wine.
3. Env: `WINEDLLOVERRIDES=d3d11=n,b;…`, `WINEDLLPATH` (overlay + `lib/wine/…`), `DXMT_CONFIG`, `CX_ROOT` = корень runtime, `ROSETTA_ADVERTISE_AVX=1`, `DYLD_FALLBACK_LIBRARY_PATH` на `lib`/`lib64` runtime.
4. Критерий успеха для DX11-игры: в `Player.log` (или аналоге) есть инициализация D3D11 без `InitializeEngineGraphics failed` / `Failed to create metal view`.

## 9. Steam-библиотека

- Источник истины: `steamapps/appmanifest_*.acf` (+ `libraryfolders.vdf` при необходимости).
- Парсинг: `SteamVDF`.
- Состояния установки выводятся из флагов манифеста.
- GUI (`MacGamerApp`) отображает и обновляет `library.json`, пока Steam открыт / по sync.

## 10. Инструменты

| Скрипт | Назначение |
| --- | --- |
| `tools/package-winecx-from-crossover.sh` | мантейнер: упаковка LGPL Wine из CrossOver → обновление бандла `BundledRuntime` |
| `tools/build-winecx.sh` | FOSS CrossOver sources → tar.xz с `macdrv_functions` (эксперимент; см. §15) |
| `tools/patch-winecoreaudio.sh` | пересборка/установка патченного `winecoreaudio.so` в runtime |
| `tools/patches/winecoreaudio-period-frames.patch` | MR11681 + увеличенный HAL-буфер (≥1024 frames, ring ×6) |
| `tools/steamwebhelper-shim/` | CEF-shim для чёрного экрана Steam |
| `tools/package-app.sh` | сборка `MacGamer.app` и установка в `~/Applications` |
| `make app` / `make run` | обёртка: собрать `.app` / собрать и открыть |
| `tools/make-app-icon.swift` | значок приложения для `.app` |

## 11. Требования к окружению

- Apple Silicon, Rosetta 2
- macOS 14+
- Xcode / Swift 6 toolchain
- Git LFS для `Sources/LauncherCore/BundledRuntime/winecx-26.2-osx64.tar.xz`
- CrossOver у пользователя не требуется
- Для FOSS-сборки Wine (мантейнер): Intel Homebrew (`/usr/local`), зависимости из шапки `build-winecx.sh`
- Для патча звука: дерево сборки `~/winecx-build-<ver>/` (после хотя бы одной configure/make wine) либо повторный `build-winecx.sh`

## 12. Тестирование

- `swift test` — unit/fixture тесты `LauncherCoreTests` (манифест, бандл Wine, SetupGuide, VDF, planner env, GPTK import fixture, dry-run deps).
- Ручной smoke: мастер GUI, `doctor`, `runtime install`, `steam open` (логин Success), `run --app` на известной DX11-игре (например Megabonk / appid `3405340`), проверка щелчков звука.

## 13. Лицензии и границы распространения

| Компонент | Лицензия / условие |
| --- | --- |
| Код MacGamer | по лицензии репозитория |
| Wine / winecx | LGPL |
| DXMT v0.80 | MIT |
| DXVK | zlib |
| MoltenVK | Apache-2.0 |
| D3DMetal / GPTK | только пользовательский импорт по условиям Apple |
| Steam / игры | не входят в репозиторий |

## 14. Критерии приёмки (MVP)

1. `swift build` и `swift test` проходят.
2. `doctor` сообщает chip, Rosetta, установленный runtime, `gptkCapable` / `gptkImported`.
3. Runtime winecx ставится из встроенного архива (`runtime install` без `--archive`) и содержит `macdrv_functions`.
4. Steam открывается из указанного пути; CEF не остаётся чёрным экраном из‑за GPU (shim); логин доходит до `SetLoginState: Success`.
5. Установленная игра появляется после `steam sync` / в GUI.
6. `run --app` запускает игру с выбранным бэкендом; для `dxmt` на winecx Direct3D инициализируется на Apple GPU.
7. Установка и запуск не требуют `CrossOver.app`.
8. В runtime установлен патченный `winecoreaudio.so` (или задокументирован откат к `.bak-pre-period-patch`).

## 15. Известные ограничения

- **FOSS winecx (например 26.3 из `build-winecx.sh`)** на практике ломает Steam: `Crypto API failed certificate check`, застревание логина / CM. Пользовательский бандл — `winecx-26.2`.
- Сборка winecx из исходников долгая и хрупкая (Intel Homebrew Tier 3, Rosetta) и нужна только мантейнеру.
- Обновление бандла из CrossOver — опция мантейнера; версия wine ≤ версии установленного CrossOver.
- Смена Wine/runtime может сбросить сессию Steam (повторный логин).
- Не все игры совместимы с DXMT/DXVK/D3DMetal на Apple Silicon.
- Редкие щелчки звука возможны под нагрузкой Rosetta даже с патчем period/buffer.

## 16. Звук (winecoreaudio)

Проблема: рассинхрон period frames игры (часто 480) и HAL macOS (часто 512) → underrun в `ca_render_cb` → щелчки. Upstream: Wine MR11681 (Aug 2026).

Контракт патча MacGamer:

1. Выставить `kAudioDevicePropertyBufferFrameSize` по запросу клиента, clamp к range устройства.
2. Предпочитать HAL ≥ **1024** frames (если устройство позволяет), иначе ≥ 512.
3. Ring-buffer не меньше **6 × period_frames**.
4. `GetDevicePeriod` возвращает фактический period устройства, не хардкод 10 ms.

Установка: `tools/patch-winecoreaudio.sh [path-to-runtime]`  
Откат: `winecoreaudio.so.bak-pre-period-patch` рядом с `.so`.

Рекомендации окружения: выход **48 kHz**, проводной (не Bluetooth), без Spatial Audio.
