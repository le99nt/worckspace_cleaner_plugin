--!nonstrict
-- ============================================================================
-- Workspace Clean-Up Assistant (Noctalia Shell v5+, движок Luau) — v2.0.0
--
-- Headless фоновый сервис ([[service]] в plugin.toml):
--   * хост вызывает глобальную функцию update() как "service tick";
--     частота тика задается через noctalia.setUpdateInterval(мс);
--   * каждый тик запускает `niri msg -j windows` через noctalia.runAsync;
--   * находит окна из списка наблюдения, которые НЕ в фокусе дольше
--     порога простоя (по умолчанию 20 минут);
--   * отправляет МЯГКОЕ напоминание через noctalia.notify.
--
-- НОВОЕ В v2.0.0:
--   * настраиваемый список наблюдения (setting "watch_list": классы/заголовки
--     через запятую вместо жесткого списка в коде);
--   * повторяющиеся напоминания каждые repeat_interval_min минут (0 = выкл);
--   * тихие часы: уведомления не отправляются в диапазоне
--     quiet_start_hour .. quiet_end_hour (по отдельности -1 = выкл);
--   * опциональное автозакрытие окна после N напоминаний
--     (setting "auto_close_after_reminders", 0 = выкл) — окно закрывается
--     командой `niri msg action close-window --id <id>`;
--   * ежедневная сводка: при смене суток плагин присылает итог дня —
--     сколько напоминаний отправлено и сколько окон закрыто автоматически.
--
-- По умолчанию плагин НИКОГДА не закрывает окна сам (auto_close = 0):
-- решение всегда за пользователем. Автозакрытие работает только если
-- включено явно и только после N напоминаний подряд.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Конфигурация: значения из настроек плагина с безопасными fallback'ами.
-- noctalia.getConfig(key) возвращает значение [[setting]] из plugin.toml
-- либо nil, если пользователь ничего не менял и дефолт не применился.
-- ---------------------------------------------------------------------------
local POLL_INTERVAL_SEC = tonumber(noctalia.getConfig("poll_interval_sec")) or 60
local IDLE_TIMEOUT_SEC = (tonumber(noctalia.getConfig("idle_timeout_min")) or 20) * 60

--- Интервал повторных напоминаний (минут). 0 = напоминать один раз на окно.
local REPEAT_INTERVAL_SEC = (tonumber(noctalia.getConfig("repeat_interval_min")) or 0) * 60

--- Автозакрытие после N напоминаний. 0 = выключено (поведение v1).
local AUTO_CLOSE_AFTER = tonumber(noctalia.getConfig("auto_close_after_reminders")) or 0

--- Тихие часы. Границы диапазона включительно слева; -1 = граница не задана.
local QUIET_START = tonumber(noctalia.getConfig("quiet_start_hour")) or -1
local QUIET_END = tonumber(noctalia.getConfig("quiet_end_hour")) or -1

--- Команда получения списка окон композитора Niri в формате JSON.
local NIRI_WINDOWS_CMD = "niri msg -j windows"

-- ---------------------------------------------------------------------------
-- Список наблюдения: разбираем строку "alacritty, kitty, firefox, ..."
-- на массив шаблонов для поиска по вхождению (регистронезависимо).
-- ---------------------------------------------------------------------------
local TARGET_PATTERNS = {}
for pattern in string.gmatch(string.lower(noctalia.getConfig("watch_list") or "alacritty, kitty, foot, terminal, firefox, chromium, brave"), "[^,]+") do
	local p = pattern:gsub("^%s+", ""):gsub("%s+$", "")
	if p ~= "" then
		table.insert(TARGET_PATTERNS, p)
	end
end
-- Совсем пустой список смысла не имеет — страховочный минимум.
if #TARGET_PATTERNS == 0 then
	TARGET_PATTERNS = { "terminal" }
end

-- ---------------------------------------------------------------------------
-- Состояние плагина
--
-- idleSince[windowId]        = { since = <os.time()>, title = <string> }
-- notified[windowId]         = true — уведомление по окну уже отправлялось
-- reminderCount[windowId]    = число отправленных напоминаний по окну
-- lastNotifiedAt[windowId]   = os.time() последнего напоминания (для повторов)
-- autoClosing[windowId]      = true — по окну уже отправлена команда закрытия
--
-- Глобальные таблицы живут, пока жив runtime плагина (до reload).
-- ---------------------------------------------------------------------------
local idleSince = {}
local notified = {}
local reminderCount = {}
local lastNotifiedAt = {}
local autoClosing = {}

local inFlight = false

-- Ежедневная статистика: дата (ключ дня) + счётчики.
local stats = { day = os.date("%Y-%m-%d"), reminders = 0, autoClosed = 0 }

-- ---------------------------------------------------------------------------
-- Вспомогательные функции
-- ---------------------------------------------------------------------------

--- Убирает начальные и конечные пробелы у строки.
local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Проверяет, попадает ли текущий час в диапазон тихих часов.
--- Диапазон может пересекать полночь (например, 23 .. 7).
---@return boolean
local function isQuietHour()
	if QUIET_START < 0 or QUIET_END < 0 or QUIET_START == QUIET_END then
		return false
	end
	local hour = os.date("*t").hour
	if QUIET_START < QUIET_END then
		return hour >= QUIET_START and hour < QUIET_END
	end
	return hour >= QUIET_START or hour < QUIET_END
end

--- Проверяет, подходит ли окно под критерии наблюдения (список watch_list).
---@param appId string? Класс приложения (app_id из вывода Niri)
---@param title string? Заголовок окна
---@return boolean
local function isWatchedWindow(appId, title)
	local appIdLower = string.lower(appId or "")
	local titleLower = string.lower(title or "")

	for _, pattern in ipairs(TARGET_PATTERNS) do
		if string.find(appIdLower, pattern, 1, true) or string.find(titleLower, pattern, 1, true) then
			return true
		end
	end
	return false
end

--- Отправляет команду Niri на закрытие окна (используется ТОЛЬКО при
--- включенном auto_close_after_reminders > 0 и после N напоминаний).
---@param windowId number Идентификатор окна Niri
---@param title string Заголовок окна
local function closeWindow(windowId, title)
	if autoClosing[windowId] then
		return
	end
	autoClosing[windowId] = true
	stats.autoClosed = stats.autoClosed + 1

	noctalia.log(string.format("[CleanUp] Автозакрытие: окно %d «%s» после %d напоминаний",
		windowId, title, reminderCount[windowId] or 0))
	noctalia.notify(
		"Workspace Clean-Up Assistant",
		string.format("Окно [%s] закрыто автоматически после %d напоминаний.", title, reminderCount[windowId] or 0)
	)

	local started = noctalia.runAsync(
		string.format("niri msg action close-window --id %d", windowId),
		function(result)
			if result.exitCode ~= 0 then
				noctalia.log("[CleanUp] close-window завершился с ошибкой: " .. tostring(result.stderr))
			end
		end,
		5000
	)
	if not started then
		noctalia.log("[CleanUp] Не удалось запустить close-window для окна " .. windowId)
	end
end

--- Регистрирует и отправляет напоминание по окну (первое или повторное).
--- При достижении порога auto_close_after_reminders инициирует закрытие.
---@param windowId number Идентификатор окна Niri
---@param title string Заголовок окна
local function sendReminder(windowId, title)
	local since = idleSince[windowId]
	if not since then
		return
	end

	local minutes = math.max(1, math.floor((os.time() - since.since) / 60))
	reminderCount[windowId] = (reminderCount[windowId] or 0) + 1
	lastNotifiedAt[windowId] = os.time()
	stats.reminders = stats.reminders + 1

	noctalia.notify(
		"Workspace Clean-Up Assistant",
		string.format("Окно [%s] простаивает уже %d минут. Проверьте его!", title, minutes)
	)
	noctalia.log(string.format("[CleanUp] Напоминание №%d: окно %d «%s» (%d мин.)",
		reminderCount[windowId], windowId, title, minutes))

	if AUTO_CLOSE_AFTER > 0 and reminderCount[windowId] >= AUTO_CLOSE_AFTER then
		closeWindow(windowId, title)
	end
end

--- Смена суток: отправляет сводку за прошедший день и обнуляет счётчики.
--- Вызывается в начале каждого тика — момент смены даты ловится автоматически.
local function maybeDailySummary()
	local today = os.date("%Y-%m-%d")
	if stats.day == today then
		return
	end

	if stats.reminders > 0 or stats.autoClosed > 0 then
		noctalia.notify(
			"Workspace Clean-Up Assistant",
			string.format("Итоги за %s: %d напоминаний, %d окон закрыто автоматически.",
				stats.day, stats.reminders, stats.autoClosed)
		)
		noctalia.log(string.format("[CleanUp] Сводка за %s: напоминаний %d, автозакрытий %d",
			stats.day, stats.reminders, stats.autoClosed))
	end

	stats.day = today
	stats.reminders = 0
	stats.autoClosed = 0
end

--- Убирает из таблиц отслеживания окна, которых больше нет у Niri.
---@param aliveIds table Множество ID существующих окон ({ [id] = true })
local function pruneDeadWindows(aliveIds)
	for windowId in pairs(idleSince) do
		if not aliveIds[windowId] then
			idleSince[windowId] = nil
			notified[windowId] = nil
			reminderCount[windowId] = nil
			lastNotifiedAt[windowId] = nil
			autoClosing[windowId] = nil
			noctalia.log(string.format("[CleanUp] Окно %d закрыто — убрано из отслеживания", windowId))
		end
	end
end

--- Обрабатывает асинхронный ответ `niri msg -j windows`.
---@param result table CommandResult: { exitCode, stdout, stderr, ... }
local function handleNiriResult(result)
	inFlight = false

	if result.exitCode ~= 0 then
		noctalia.log("[CleanUp] niri msg завершился с ошибкой: " .. tostring(result.stderr))
		return
	end

	local windows, err = noctalia.json.decode(result.stdout)
	if err ~= nil then
		noctalia.log("[CleanUp] Ошибка парсинга JSON: " .. tostring(err))
		return
	end
	if type(windows) ~= "table" then
		noctalia.log("[CleanUp] Неожиданная структура JSON: ожидался массив окон")
		return
	end

	local aliveIds = {}
	local now = os.time()

	for _, win in ipairs(windows) do
		if type(win.id) == "number" then
			aliveIds[win.id] = true

			local isFocused = win.is_focused == true

			if isFocused then
				-- Окно в фокусе: полный сброс счётчиков простоя и напоминаний.
				idleSince[win.id] = nil
				notified[win.id] = nil
				reminderCount[win.id] = nil
				lastNotifiedAt[win.id] = nil
			elseif isWatchedWindow(win.app_id, win.title) then
				local title = win.title
				if type(title) ~= "string" or trim(title) == "" then
					title = win.app_id or "без названия"
				end

				if idleSince[win.id] == nil then
					-- Первый раз увидели неактивным — фиксируем время.
					idleSince[win.id] = { since = now, title = title }
					noctalia.log(string.format("[CleanUp] Начат отсчёт простоя: окно %d «%s»", win.id, title))
				elseif isQuietHour() then
					-- Тихие часы: не беспокоим (и не закрываем) окна.
				elseif not notified[win.id] and (now - idleSince[win.id].since) >= IDLE_TIMEOUT_SEC then
					-- Первое напоминание: порог простоя превышен.
					sendReminder(win.id, title)
					notified[win.id] = true
				elseif notified[win.id] and REPEAT_INTERVAL_SEC > 0
					and (now - (lastNotifiedAt[win.id] or 0)) >= REPEAT_INTERVAL_SEC then
					-- Повторное напоминание (если включены повторы).
					sendReminder(win.id, title)
					notified[win.id] = true
				end
				-- Иначе молчим (защита от спама).
			end
		end
	end

	pruneDeadWindows(aliveIds)
end

-- ---------------------------------------------------------------------------
-- Точка входа сервиса: тик, вызываемый хостом с интервалом
-- POLL_INTERVAL_SEC (задается ниже через setUpdateInterval).
-- ---------------------------------------------------------------------------
function update()
	-- Проверяем смену суток и, при необходимости, шлём сводку за вчера.
	maybeDailySummary()

	-- Не наслаиваем запросы: предыдущий ещё выполняется.
	if inFlight then
		return
	end

	inFlight = true
	local started = noctalia.runAsync(NIRI_WINDOWS_CMD, handleNiriResult, 10000)
	if not started then
		inFlight = false
		noctalia.log("[CleanUp] Не удалось запустить процесс: " .. NIRI_WINDOWS_CMD)
	end
end

-- ---------------------------------------------------------------------------
-- Завершение работы плагина (reload/disable/uninstall/shutdown).
-- ---------------------------------------------------------------------------
function onExit(signal, reason)
	noctalia.log("[CleanUp] Плагин остановлен (reason=" .. tostring(reason) .. ")")
end

-- ---------------------------------------------------------------------------
-- Инициализация: задаем частоту тика сервиса (мс) и логируем старт.
-- ---------------------------------------------------------------------------
noctalia.setUpdateInterval(POLL_INTERVAL_SEC * 1000)
noctalia.log(string.format(
	"[CleanUp] Workspace Clean-Up Assistant v2.0.0 запущен (интервал %d сек, порог %d мин, повторы %s, автозакрытие %s, тихие часы %s)",
	POLL_INTERVAL_SEC,
	math.floor(IDLE_TIMEOUT_SEC / 60),
	REPEAT_INTERVAL_SEC > 0 and (math.floor(REPEAT_INTERVAL_SEC / 60) .. " мин") or "выкл",
	AUTO_CLOSE_AFTER > 0 and ("после " .. AUTO_CLOSE_AFTER) or "выкл",
	(QUIET_START >= 0 and QUIET_END >= 0) and (QUIET_START .. "-" .. QUIET_END) or "выкл"
))
