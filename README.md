# 🧹 Workspace Clean-Up Assistant

[🇷🇺 Русский](#-русский) · [🇬🇧 English](#-english)

![Noctalia](https://img.shields.io/badge/Noctalia%20Shell-v5+-6C5CE7)
![Luau](https://img.shields.io/badge/engine-Luau-0060AC)
![Version](https://img.shields.io/badge/version-2.0.0-success)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 🇷🇺 Русский

Headless-плагин для **Noctalia Shell**, который следит за «забытыми» окнами и мягко напоминает, что их можно закрыть. **По умолчанию плагин ничего не закрывает сам** — решение всегда остаётся за вами. Но если хотите, v2.0.0 умеет **автоматически закрывать** окно после N напоминаний (опция выключена по умолчанию).

### 💡 Зачем это нужно

Открыли терминал для одной команды, а он висит уже три часа? Накопили десяток вкладок в браузере? Плагин заметит такие окна и вежливо напомнит:

> **Workspace Clean-Up Assistant**
> Окно [zsh — alacritty] простаивает уже 20 минут. Проверьте его!

А в конце дня пришлёт сводку:

> **Workspace Clean-Up Assistant**
> Итоги за 2026-11-06: 5 напоминаний, 2 окон закрыто автоматически.

### ✨ Возможности

- 🖥️ **Настраиваемый список наблюдения** — отслеживайте любые приложения по классу или заголовку окна (по умолчанию: `alacritty`, `kitty`, `foot`, `firefox`, `chromium`, `brave`)
- ⏱️ Напоминание после **20 минут** простоя без фокуса (настраивается)
- 🔁 **Повторяющиеся напоминания** каждые N минут, пока вы не вернётесь к окну (0 = только одно напоминание)
- 🌙 **Тихие часы** — ночью напоминания (и автозакрытие) не беспокоят; диапазон может пересекать полночь
- 🧨 **Опциональное автозакрытие** — окно закрывается через `niri msg action close-window` только после N напоминаний (0 = выключено, безопасный режим по умолчанию)
- 📊 **Ежедневная сводка** — итоги дня: сколько напоминаний отправлено и сколько окон закрыто автоматически
- 🛡️ **Защита от спама**: повторное напоминание — только по истечении интервала повторов
- 🔄 Автоматическая очистка данных о закрытых окнах
- 🤫 Полностью фоновый режим — никакого UI, только тихие уведомления

### 📦 Установка

Требуется **Noctalia Shell v5+** и композитор **Niri**.

```bash
# Подключить источник плагинов
noctalia msg plugins source add workspace-cleaner git https://github.com/le99nt/worckspace_cleaner_plugin

# Включить плагин
noctalia msg plugins enable obloble/workspace-cleaner
```

Для локальной разработки:

```bash
noctalia msg plugins source add local path /путь/к/репозиторию
noctalia msg plugins enable obloble/workspace-cleaner
```

### ⚙️ Настройки

| Параметр | По умолчанию | Диапазон | Описание |
|---|---|---|---|
| Интервал опроса | 60 сек | 10–600 сек | Как часто запрашивать список окон у Niri |
| Порог простоя | 20 мин | 1–240 мин | Сколько окно может висеть без фокуса до первого напоминания |
| Повтор напоминаний | 0 (выкл) | 0–240 мин | Повторять напоминание каждые N минут, пока окно не в фокусе |
| Автозакрытие после N напоминаний | 0 (выкл) | 0–10 | Закрыть окно через `niri msg action close-window` после N напоминаний |
| Список наблюдения | терминалы + браузеры | строка | Классы/фрагменты заголовков через запятую, например `alacritty, kitty, firefox` |
| Тихие часы — начало | -1 (выкл) | -1–23 | Час начала тихого периода |
| Тихие часы — конец | -1 (выкл) | -1–23 | Час конца тихого периода (диапазон может пересекать полночь, например 23 → 7) |

Меняются в **Настройки → Плагины → Workspace Clean-Up Assistant** или через `noctalia msg settings-open-plugin obloble/workspace-cleaner`.

**Пример «жёсткого» режима:** повторы каждые 10 минут, автозакрытие после 3 напоминаний, тихие часы с 23:00 до 7:00 — окно получит 3 уведомления за полчаса, после чего закроется само (кроме ночи).

### 🛠 Как это работает

1. Сервис тикает раз в `poll_interval_sec` (`noctalia.setUpdateInterval`).
2. Каждый тик асинхронно выполняет `niri msg -j windows` (`noctalia.runAsync`) и парсит JSON (`noctalia.json.decode`).
3. Окно из списка наблюдения теряет фокус → его `id` и время записываются в таблицу отслеживания.
4. Окно получает фокус → счётчики простоя и напоминаний полностью сбрасываются.
5. Простаивает дольше порога → `noctalia.notify()` (если не тихие часы).
6. Включены повторы → напоминание повторяется каждые `repeat_interval_min`, пока окно не получит фокус.
7. Счётчик напоминаний достиг `auto_close_after_reminders` (и > 0) → окно закрывается через `niri msg action close-window --id <id>`.
8. Наступили новые сутки → сводка за предыдущий день, счётчики обнуляются.
9. Окно закрылось → запись удаляется из всех таблиц отслеживания.

### 📁 Структура

```
workspace-cleaner/
├── plugin.toml        # Манифест: метаданные, [[service]], [[setting]]
├── init.luau          # Логика мониторинга (entry [[service]])
└── translations/en.json
```

### 🧪 Проверка перед установкой

```bash
noctalia plugins lint workspace-cleaner   # 0 errors, 0 warnings
```

---

## 🇬🇧 English

A headless plugin for **Noctalia Shell** that watches "forgotten" windows and gently reminds you that they can be closed. **By default the plugin never closes anything itself** — the decision is always yours. But if you want, v2.0.0 can **auto-close** a window after N reminders (disabled by default).

### 💡 Why you need it

Opened a terminal for a single command and it has been hanging there for three hours? Accumulated a dozen browser tabs? The plugin notices such windows and politely reminds you:

> **Workspace Clean-Up Assistant**
> Window [zsh — alacritty] has been idle for 20 minutes. Check it!

At the end of the day it sends a summary:

> **Workspace Clean-Up Assistant**
> Summary for 2026-11-06: 5 reminders, 2 windows auto-closed.

### ✨ Features

- 🖥️ **Configurable watch list** — track any apps by class or window title (default: `alacritty`, `kitty`, `foot`, `firefox`, `chromium`, `brave`)
- ⏱️ Reminder after **20 minutes** of unfocused idle time (configurable)
- 🔁 **Repeating reminders** every N minutes until you focus the window again (0 = single reminder)
- 🌙 **Quiet hours** — no reminders (and no auto-close) at night; the range may cross midnight
- 🧨 **Optional auto-close** — the window is closed via `niri msg action close-window` only after N reminders (0 = off, safe by default)
- 📊 **Daily summary** — end-of-day totals: reminders sent and windows auto-closed
- 🛡️ **Anti-spam**: a follow-up reminder only after the repeat interval elapses
- 🔄 Automatic cleanup of closed windows from tracking tables
- 🤫 Fully background mode — no UI, just quiet notifications

### 📦 Installation

Requires **Noctalia Shell v5+** and the **Niri** compositor.

```bash
# Add the plugin source
noctalia msg plugins source add workspace-cleaner git https://github.com/le99nt/worckspace_cleaner_plugin

# Enable the plugin
noctalia msg plugins enable obloble/workspace-cleaner
```

For local development:

```bash
noctalia msg plugins source add local path /path/to/repo
noctalia msg plugins enable obloble/workspace-cleaner
```

### ⚙️ Settings

| Option | Default | Range | Description |
|---|---|---|---|
| Poll interval | 60 s | 10–600 s | How often to query Niri for the window list |
| Idle timeout | 20 min | 1–240 min | How long a window may stay unfocused before the first reminder |
| Repeat reminders | 0 (off) | 0–240 min | Repeat the reminder every N minutes while the window stays unfocused |
| Auto-close after N reminders | 0 (off) | 0–10 | Close the window via `niri msg action close-window` after N reminders |
| Watch list | terminals + browsers | string | Comma-separated app classes / title fragments, e.g. `alacritty, kitty, firefox` |
| Quiet hours — start | -1 (off) | -1–23 | Hour when quiet hours begin |
| Quiet hours — end | -1 (off) | -1–23 | Hour when quiet hours end (the range may cross midnight, e.g. 23 → 7) |

Change them in **Settings → Plugins → Workspace Clean-Up Assistant** or via `noctalia msg settings-open-plugin obloble/workspace-cleaner`.

**Example "strict" mode:** repeats every 10 minutes, auto-close after 3 reminders, quiet hours 23:00–7:00 — a window gets 3 notifications over half an hour and then closes itself (except at night).

### 🛠 How it works

1. The service ticks every `poll_interval_sec` (`noctalia.setUpdateInterval`).
2. Each tick asynchronously runs `niri msg -j windows` (`noctalia.runAsync`) and parses the JSON (`noctalia.json.decode`).
3. A watched window loses focus → its `id` and timestamp are stored in the tracking table.
4. A window gains focus → idle counters and reminder counts are fully reset.
5. Idle longer than the threshold → `noctalia.notify()` (unless quiet hours are active).
6. Repeats enabled → the reminder repeats every `repeat_interval_min` until the window gains focus.
7. The reminder counter reaches `auto_close_after_reminders` (and > 0) → the window is closed via `niri msg action close-window --id <id>`.
8. A new day begins → a summary for the previous day is sent and counters reset.
9. A window closes → its entries are removed from all tracking tables.

### 📁 Structure

```
workspace-cleaner/
├── plugin.toml        # Manifest: metadata, [[service]], [[setting]]
├── init.luau          # Monitoring logic ([[service]] entry)
└── translations/en.json
```

### 🧪 Pre-install check

```bash
noctalia plugins lint workspace-cleaner   # 0 errors, 0 warnings
```

---

## 📄 Лицензия / License

MIT © [obloble](https://github.com/le99nt)
