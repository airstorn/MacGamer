# MacGamer

Личный лаунчер Windows-игр на Apple Silicon. Управляет Wine-бутылками, открывает указанный пользователем Windows Steam и подхватывает установленные игры из `steamapps`.

## Требования

- Apple Silicon
- macOS 14+
- Rosetta 2
- Xcode / Swift 6

## Сборка

```bash
swift build
swift test
swift run macgamer doctor
```

GUI:

```bash
swift run MacGamerApp
```

## Данные

`~/Library/Application Support/MacGamer/`

- `runtimes/` — Wine, DXMT, DXVK
- `bottles/` — префиксы
- `library.json` — библиотека игр
- `logs/` — логи запуска
- `store/d3dmetal/` — импортированный GPTK payload

## Команды

```bash
macgamer doctor
macgamer runtime install
macgamer bottle create --name Steam --role steam
macgamer steam use /path/to/steam.exe
macgamer steam open --dry-run
macgamer steam sync
macgamer run --app 570 --dry-run
macgamer backend set --bottle <id> --backend dxvk
macgamer deps vcrun2022 --bottle <id> --installer /path/to/VC_redist.x64.exe --dry-run
macgamer gptk import /path/to/Game_Porting_Toolkit.dmg
macgamer log summarize /path/to/file.log
```

Steam и игры утилита не скачивает. Укажите путь к `steam.exe` или `SteamSetup.exe`, войдите в клиент и установите игру сами — MacGamer периодически сканирует `appmanifest_*.acf` и обновляет библиотеку.

Перед каждым `steam open` MacGamer ставит обёртку `steamwebhelper` с `--disable-gpu --single-process`, иначе окно Steam на Wine часто остаётся чёрным. Для UI клиента используется WineD3D; бэкенд бутылки (DXMT/DXVK) применяется к играм.

## Графика

| Бэкенд | Назначение |
| --- | --- |
| `dxmt` | DirectX 10/11 → Metal |
| `dxvk` | DirectX 9–11 через MoltenVK |
| `wined3d` | запасной путь Wine |
| `d3dmetal` | DirectX 11/12 после импорта GPTK |

Рантайм `winecx` помечен `gptkCapable=true` (Wine с `macdrv_functions` для DXMT).

```bash
# из FOSS-исходников CodeWeavers (долго)
tools/build-winecx.sh
# или упаковать LGPL Wine из установленного CrossOver (быстрее, для локального bootstrap)
tools/package-winecx-from-crossover.sh ~/Applications/CrossOver.app
macgamer runtime install --archive ~/Library/Application\ Support/MacGamer/downloads/winecx-26.2-osx64.tar.xz
```

После установки CrossOver.app не нужен. Бэкенд по умолчанию — `dxmt`. `d3dmetal` — после `macgamer gptk import <dmg>`.

## Лицензии

Wine (LGPL), DXMT (MIT для v0.80), DXVK (zlib), MoltenVK (Apache). D3DMetal остаётся у пользователя по лицензии Apple из DMG. Steam в репозиторий не входит.
