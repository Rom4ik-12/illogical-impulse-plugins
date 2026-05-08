# Quickshell User Modules — Установщик

Добавляет систему пользовательских модулей в конфиг quickshell на базе illogical-impulse:

- Новая страница **Настройки → Модули** (включить/выключить, установить/экспортировать, удалить).
- Синглтон `services/UserModules.qml`, сканирующий
  `~/.config/illogical-impulse/user_modules/<id>/`.
- Поля манифеста модуля: `entry` (QML), `barWidgets` (вставка в бар),
  `patches` (правки существующих файлов шелла при включении).
- `MODULES.md` — полная спецификация формата.
- Несколько примеров модулей в `defaults/user_modules/`.

## Установка

```sh
./install.sh
```

Установщик **автоматически определяет**, где лежит шелл. Проверяет по порядку:

1. `$QS_DIR` (если задан)
2. `~/.config/quickshell/ii/` (стандартная раскладка illogical-impulse)
3. `~/.config/quickshell/` (плоская раскладка — файлы в корне)

Папка модулей по умолчанию `~/.config/illogical-impulse/user_modules`. Можно
переопределить явно:

```sh
QS_DIR=/путь/до/quickshell SHELL_CFG_DIR=/путь/до/illogical-impulse ./install.sh
```

Требуется: `python3`, `jq`, `bash`. После установки перезапусти quickshell.

Установка идемпотентна — повторный запуск не задублирует патчи.

## Удаление

```sh
./uninstall.sh
```

Откатывает все текстовые патчи, удаляет новые файлы. Установленные модули
и оригиналы патчей сохраняются (пути выводятся в конце).

## Что меняется

Новые файлы (копируются):

- `services/UserModules.qml`
- `modules/userModules/UserModulesHost.qml`
- `modules/userModules/UserModulesBarSlot.qml`
- `modules/settings/ModulesConfig.qml`
- `scripts/user_modules/patch.sh`
- `MODULES.md`
- `defaults/user_modules/*` (примеры модулей)

Существующие файлы (правятся текстово, обратимо):

- `shell.qml` — импорт `UserModulesHost`
- `settings.qml` — добавляет страницу Модули
- `modules/common/Config.qml` — добавляет `userModules.enabled`
- `modules/common/Directories.qml` — добавляет `userModulesDir`
- `modules/ii/bar/BarContent.qml` — добавляет `UserModulesBarSlot` (пропускается,
  если апстримный якорь отсутствует, например в сильно изменённом форке)
- `translations/ru_RU.json` — русские строки для нового UI (другие языки
  откатываются на английский; PR приветствуются)

## Авто-обновление с GitHub

В шелле есть кнопка **Обновить лоадер** (Настройки → Модули), которая тянет
свежий тарбол установщика и перезапускает `install.sh`. По умолчанию указывает на:

```
https://github.com/Rom4ik-12/illogical-impulse-plugins/releases/latest/download/illogical-impulse-plugins.tar.gz
```

Чтобы сменить источник, отредактируй `userModules.loaderUpdateUrl` в
`~/.config/illogical-impulse/config.json`. Принимаются три формата URL:

- прямой `.tar.gz` / `.zip`
- URL гит-репо на GitHub (будет shallow-клон)
- всё остальное считается tar.gz

### Публикация своего форка

Этот каталог сразу готов как репозиторий GitHub:

1. Запушь его на GitHub.
2. Поставь тег релиза: `git tag v1.0.0 && git push --tags`.
3. Встроенный `.github/workflows/release.yml` запустит `make dist`, прицепит
   тарбол к релизу, и URL вида `releases/latest/download/...` сразу станет
   доступен.

Локально:

```sh
make check    # синтаксис bash/python
make dist     # собрать dist/illogical-impulse-plugins.tar.gz
```

## Как делиться модулями

Модуль — папка с `module.json` и entry-QML. Заархивируй как `<id>.qsmod`
(или поделись папкой). Получатель кладёт её в `user_modules/` или жмёт
**Установить** в Настройки → Модули.

Полный формат — в `payload/MODULES.md`.
