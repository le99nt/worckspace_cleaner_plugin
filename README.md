# 🧹 Workspace Clean-Up Assistant

[🇷🇺 Русский](#-русский) · [🇬🇧 English](#-english)

![Noctalia](https://img.shields.io/badge/Noctalia%20Shell-v5+-6C5CE7)
![Luau](https://img.shields.io/badge/engine-Luau-0060AC)
![Version](https://img.shields.io/badge/version-1.0.0-success)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 🇷🇺 Русский

Headless-плагин для **Noctalia Shell**, который следит за «забытыми» окнами терминалов и браузеров и мягко напоминает, что их можно закрыть. **Плагин никогда ничего не закрывает сам** — решение всегда остаётся за вами.

### 💡 Зачем это нужно

Открыли терминал для одной команды, а он висит уже три часа? Накопили десяток вкладок в браузере? Плагин заметит такие окна и вежливо напомнит:

> **Workspace Clean-Up Assistant**
> Окно [zsh — alacritty] простаивает уже 20 минут. Проверьте его!

### ✨ Возможности

- 🖥️ Отслеживает окна **alacritty**, **kitty**, **foot**, а также браузеров **Firefox**, **Chromium**, **Brave** (по классу приложения или заголовку)
- ⏱️ Напоминание после **20 минут** простоя без фокуса (настраивается)
- 🛡️ **Защита от спама**: по каждому окну — только одно уведомление, пока вы снова не сфокусируете его
- 🔄 Автоматическая очистка данных о закрытых окнах
- ⚙️ Гибкие настройки прямо из окна настроек Noctalia
- 🤫 Полностью фоновый режим — никакого UI, только тихие уведомления

### 📦 Установка

Требуется **Noctalia Shell v5+** и композитор **Niri**.

```bash
# Подключить источник плагинов
noctalia msg plugins source add obloble git https://github.com/le99nt/noctalia-plugins

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
| Порог простоя | 20 мин | 1–240 мин | Сколько окно может висеть без фокуса до напоминания |

Меняются в **Настройки → Плагины → Workspace Clean-Up Assistant** или через `noctalia msg settings-open-plugin obloble/workspace-cleaner`.

### 🛠 Как это работает

1. Сервис тикает раз в `poll_interval_sec` (`noctalia.setUpdateInterval`).
2. Каждый тик асинхронно выполняет `niri msg -j windows` (`noctalia.runAsync`) и парсит JSON (`noctalia.json.decode`).
3. Окно теряет фокус → его `id` и время записываются в таблицу отслеживания.
4. Окно получает фокус → счётчик сбрасывается, флаг уведомления очищается.
5. Простаивает дольше порога → `noctalia.notify()` и пометка «уведомлено».
6. Окно закрылось → запись удаляется из всех таблиц.

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

A headless plugin for **Noctalia Shell** that watches "forgotten" terminal and browser windows and gently reminds you that they can be closed. **The plugin never closes anything itself** — the decision is always yours.

### 💡 Why you need it

Opened a terminal for a single command and it has been hanging there for three hours? Accumulated a dozen browser tabs? The plugin notices such windows and politely reminds you:

> **Workspace Clean-Up Assistant**
> Window [zsh — alacritty] has been idle for 20 minutes. Check it!

### ✨ Features

- 🖥️ Tracks **alacritty**, **kitty**, **foot** terminals, as well as **Firefox**, **Chromium**, **Brave** browsers (by app class or window title)
- ⏱️ Reminder after **20 minutes** of unfocused idle time (configurable)
- 🛡️ **Anti-spam**: one notification per window until you focus it again
- 🔄 Automatic cleanup of closed windows from tracking tables
- ⚙️ Flexible settings right from the Noctalia settings window
- 🤫 Fully background mode — no UI, just quiet notifications

### 📦 Installation

Requires **Noctalia Shell v5+** and the **Niri** compositor.

```bash
# Add the plugin source
noctalia msg plugins source add obloble git https://github.com/le99nt/noctalia-plugins

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
| Idle timeout | 20 min | 1–240 min | How long a window may stay unfocused before a reminder |

Change them in **Settings → Plugins → Workspace Clean-Up Assistant** or via `noctalia msg settings-open-plugin obloble/workspace-cleaner`.

### 🛠 How it works

1. The service ticks every `poll_interval_sec` (`noctalia.setUpdateInterval`).
2. Each tick asynchronously runs `niri msg -j windows` (`noctalia.runAsync`) and parses the JSON (`noctalia.json.decode`).
3. A window loses focus → its `id` and timestamp are stored in the tracking table.
4. A window gains focus → the counter resets and the notified flag is cleared.
5. Idle longer than the threshold → `noctalia.notify()` and mark as "notified".
6. A window closes → its entries are removed from all tables.

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
