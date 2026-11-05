--!nonstrict
-- ============================================================================
-- Workspace Clean-Up Assistant (Noctalia Shell v5+, движок Luau)
--
-- Headless фоновый сервис ([[service]] в plugin.toml):
--   * хост вызывает глобальную функцию update() как "service tick";
--     частота тика задается через noctalia.setUpdateInterval(мс);
--   * каждый тик запускает `niri msg -j windows` через noctalia.runAsync;
--   * находит окна терминалов/браузеров, которые НЕ в фокусе дольше
--     порога простоя (по умолчанию 20 минут);
--   * отправляет МЯГКОЕ напоминание через noctalia.notify;
--   * НИКОГДА не закрывает окна сам — решение всегда за пользователем.
--
-- Защита от спама: по каждому окну уведомление отправляется ОДИН раз,
-- пока окно снова не получит фокус (счётчик и флаг сбрасываются).
-- Глобальные таблицы ниже живут, пока жив runtime плагина (до reload).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Конфигурация: значения из настроек плагина с безопасными fallback'ами.
-- noctalia.getConfig(key) возвращает значение [[setting]] из plugin.toml
-- либо nil, если пользователь ничего не менял и дефолт не применился.
-- ---------------------------------------------------------------------------
local POLL_INTERVAL_SEC = tonumber(noctalia.getConfig("poll_interval_sec")) or 60
local IDLE_TIMEOUT_SEC = (tonumber(noctalia.getConfig("idle_timeout_min")) or 20) * 60

--- Команда получения списка окон композитора Niri в формате JSON.
-- Именно `niri msg -j windows` возвращает массив ОКОН (id, title, app_id,
-- is_focused). Команда `niri msg -j outputs` отдает только данные о
-- мониторах, поэтому для поиска окон она не подходит.
local NIRI_WINDOWS_CMD = "niri msg -j windows"

--- Целевые окна: класс (app_id) или заголовок терминалов и браузеров.
-- Сравнение регистронезависимое, по вхождению подстроки.
local TARGET_PATTERNS = {
	"alacritty",
	"kitty",
	"foot",
	"terminal",
	"firefox",
	"chromium",
	"brave",
}

-- ---------------------------------------------------------------------------
-- Состояние плагина (таблица отслеживания простоя)
--
-- idleSince[windowId] = { since = <os.time()>, title = <string> }
--   Окно попадает сюда, когда теряет фокус, и удаляется, когда получает его.
--
-- notified[windowId] = true — напоминание по этому окну уже отправлено.
-- ---------------------------------------------------------------------------
local idleSince = {}
local notified = {}

--- Флаг "запрос к niri уже выполняется": runAsync асинхронный, и новый тик
-- может начаться раньше, чем пришел ответ предыдущего. Не допускаем
-- параллельных запросов, чтобы не путать порядок ответов.
local inFlight = false

-- ---------------------------------------------------------------------------
-- Вспомогательные функции
-- ---------------------------------------------------------------------------

--- Убирает начальные и конечные пробелы у строки.
local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Проверяет, подходит ли окно под критерии наблюдения (терминал/браузер).
---@param appId string? Класс приложения (app_id из вывода Niri)
---@param title string? Заголовок окна
---@return boolean
local function isWatchedWindow(appId, title)
	-- Приводим оба поля к нижнему регистру для регистронезависимого поиска.
	local appIdLower = string.lower(appId or "")
	local titleLower = string.lower(title or "")

	for _, pattern in ipairs(TARGET_PATTERNS) do
		-- Ищем вхождение шаблона и в классе, и в заголовке.
		if string.find(appIdLower, pattern, 1, true) or string.find(titleLower, pattern, 1, true) then
			return true
		end
	end
	return false
end

--- Отправляет мягкое напоминание пользователю и помечает окно
-- как "уведомленное" (защита от спама).
---@param windowId number Идентификатор окна Niri
---@param title string Заголовок окна
local function sendIdleNotification(windowId, title)
	local since = idleSince[windowId]
	if not since then
		return
	end

	-- Фактическое время простоя в минутах (для информативности).
	local minutes = math.max(1, math.floor((os.time() - since.since) / 60))

	-- Встроенная система уведомлений Noctalia.
	noctalia.notify(
		"Workspace Clean-Up Assistant",
		string.format("Окно [%s] простаивает уже %d минут. Проверьте его!", title, minutes)
	)

	-- Помечаем окно: повторных сообщений по нему не будет, пока окно
	-- снова не получит фокус (см. обработку фокуса ниже).
	notified[windowId] = true
	noctalia.log(string.format("[CleanUp] Напоминание отправлено: окно %d «%s» (%d мин.)", windowId, title, minutes))
end

--- Убирает из таблиц отслеживания окна, которых больше нет у Niri.
---@param aliveIds table Множество ID существующих окон ({ [id] = true })
local function pruneDeadWindows(aliveIds)
	for windowId in pairs(idleSince) do
		if not aliveIds[windowId] then
			idleSince[windowId] = nil
			notified[windowId] = nil
			noctalia.log(string.format("[CleanUp] Окно %d закрыто — убрано из отслеживания", windowId))
		end
	end
end

--- Обрабатывает асинхронный ответ `niri msg -j windows`.
---@param result table CommandResult: { exitCode, stdout, stderr, ... }
local function handleNiriResult(result)
	inFlight = false

	if result.exitCode ~= 0 then
		-- Niri мог перезапуститься или команда отсутствует: логируем и ждём
		-- следующего тика. Такой сбой не должен останавливать сервис.
		noctalia.log("[CleanUp] niri msg завершился с ошибкой: " .. tostring(result.stderr))
		return
	end

	-- Декодирование JSON: noctalia.json.decode возвращает (value, err).
	local windows, err = noctalia.json.decode(result.stdout)
	if err ~= nil then
		noctalia.log("[CleanUp] Ошибка парсинга JSON: " .. tostring(err))
		return
	end
	if type(windows) ~= "table" then
		noctalia.log("[CleanUp] Неожиданная структура JSON: ожидался массив окон")
		return
	end

	-- Множество живых ID для последующей чистки таблицы.
	local aliveIds = {}
	local now = os.time()

	for _, win in ipairs(windows) do
		-- Пропускаем некорректные записи без числового ID.
		if type(win.id) == "number" then
			aliveIds[win.id] = true

			local isFocused = win.is_focused == true

			if isFocused then
				-- ---------------------------------------------------
				-- Окно в фокусе: сбрасываем счётчик простоя и флаг
				-- уведомления (пользователь "вернулся" к окну).
				-- ---------------------------------------------------
				idleSince[win.id] = nil
				notified[win.id] = nil
			elseif isWatchedWindow(win.app_id, win.title) then
				-- ---------------------------------------------------
				-- Подходящее окно НЕ в фокусе: ведём учёт простоя.
				-- ---------------------------------------------------
				local title = win.title
				if type(title) ~= "string" or trim(title) == "" then
					title = win.app_id or "без названия"
				end

				if idleSince[win.id] == nil then
					-- Первый раз увидели неактивным — фиксируем время.
					idleSince[win.id] = { since = now, title = title }
					noctalia.log(string.format("[CleanUp] Начат отсчёт простоя: окно %d «%s»", win.id, title))
				elseif not notified[win.id] and (now - idleSince[win.id].since) >= IDLE_TIMEOUT_SEC then
					-- Простаивает дольше порога; уведомление ещё не отправлялось.
					sendIdleNotification(win.id, title)
				end
				-- Если notified[win.id] == true — молчим (защита от спама).
			end
		end
	end

	-- Удаляем записи о закрытых окнах.
	pruneDeadWindows(aliveIds)
end

-- ---------------------------------------------------------------------------
-- Точка входа сервиса: тик, вызываемый хостом с интервалом
-- POLL_INTERVAL_SEC (задается ниже через setUpdateInterval).
-- ---------------------------------------------------------------------------
function update()
	-- Не наслаиваем запросы: предыдущий ещё выполняется.
	if inFlight then
		return
	end

	inFlight = true
	-- Асинхронный запуск с таймаутом 10 секунд; ответ придёт в callback.
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
-- Первый тик хост выполнит через заданный интервал.
-- ---------------------------------------------------------------------------
noctalia.setUpdateInterval(POLL_INTERVAL_SEC * 1000)
noctalia.log(
	string.format(
		"[CleanUp] Workspace Clean-Up Assistant запущен (интервал %d сек, порог %d мин)",
		POLL_INTERVAL_SEC,
		math.floor(IDLE_TIMEOUT_SEC / 60)
	)
)
