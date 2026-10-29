# MacGamer

Личный лаунчер Windows-игр на Apple Silicon. Открывает указанный вами Windows Steam через Wine и подхватывает установленные игры из `steamapps`. Steam, игры и CrossOver утилита не скачивает и не требует.

## Требования

- Mac на Apple Silicon, macOS 14+
- [Xcode](https://developer.apple.com/xcode/) со Swift 6
- Git LFS — в репозитории бинарный Wine (~189 MB)
- Установщик Windows Steam: `SteamSetup.exe` ([сайт Steam](https://store.steampowered.com/about/))

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

## Первый запуск

Пока окружение не готово, открывается мастер. Шаг считается по диску: если среда уже стоит, мастер начнётся со Steam.

1. **Rosetta** — стандартный компонент macOS для x86_64.
2. **Среда запуска** — Wine уже в приложении; скачаются DXMT и DXVK.
3. **Steam** — «Выбрать SteamSetup.exe», войти в клиент и установить игру. Если указали установщик, один раз пройдите мастер Steam внутри Wine.

## Как пользоваться

В библиотеке:

- **Открыть Steam** — клиент Windows Steam.
- **Синхронизировать** — подтянуть установленные игры из `steamapps`.
- **Играть** — запуск выбранной игры.

Перед каждым открытием Steam ставится обёртка `steamwebhelper` (`--disable-gpu --single-process`), иначе окно часто остаётся чёрным.
