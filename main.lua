-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Frank

local ApiClient = require("api_client")
local ButtonDialog = require("ui/widget/buttondialog")
local ComputerConfig = require("computer_config")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local Prompts = require("prompts")
local Providers = require("providers")
local ReaderContext = require("reader_context")
local socket_ok, socket = pcall(require, "socket")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("i18n")

local MRI = WidgetContainer:extend{
    name = "mri",
    is_doc_only = true,
}

local LOG_MAX_BYTES = 65536
local LOG_KEEP_BYTES = 49152
local DIRECTORY_PREFETCH_VERSION = 3
local DIRECTORY_KINDS = { "people", "places", "concepts" }
local RESPONSE_CACHE_VERSION = 1
local RESPONSE_CACHE_MAX_ENTRIES = 80
local RESPONSE_CACHE_PROGRESS_DELTA = 5
local MRI_VERSION = "0.1.0-dev"
local MRI_GITHUB_URL = "https://github.com/frankshiii/MRI"

local function nowSeconds()
    if socket_ok and socket and socket.gettime then
        return socket.gettime()
    end
    return os.time()
end

local function recapNeedsChunkFallback(err)
    local message = tostring(err or "")
    local lower = message:lower()
    return lower:find("http 413", 1, true) ~= nil
        or lower:find("context_length", 1, true) ~= nil
        or lower:find("context length", 1, true) ~= nil
        or lower:find("context window", 1, true) ~= nil
        or lower:find("maximum context", 1, true) ~= nil
        or lower:find("prompt is too long", 1, true) ~= nil
        or lower:find("input is too long", 1, true) ~= nil
        or lower:find("input length", 1, true) ~= nil
        or lower:find("input token", 1, true) ~= nil
        or lower:find("too many tokens", 1, true) ~= nil
        or lower:find("payload too large", 1, true) ~= nil
        or lower:find("request entity too large", 1, true) ~= nil
        or message:find("上下文", 1, true) ~= nil
        or message:find("输入过长", 1, true) ~= nil
        or message:find("请求过大", 1, true) ~= nil
        or message:find("长度限制", 1, true) ~= nil
end

-- Keep MRI directly under the Tools tab and ahead of lower-priority tools.
local reader_menu_order = require("ui/elements/reader_menu_order")
local mri_menu_registered = false
for unused_index, item_id in ipairs(reader_menu_order.tools) do
    if item_id == "mri" then
        mri_menu_registered = true
        break
    end
end
if not mri_menu_registered then
    table.insert(reader_menu_order.tools, 1, "mri")
end

local function clean(text)
    if type(text) ~= "string" then
        return ""
    end
    return util.cleanupSelectedText(text)
end

local function responseCacheKey(kind, identity)
    local normalized = clean(identity):lower():gsub("%s+", " ")
    local hash = 5381
    for index = 1, #normalized do
        hash = (hash * 33 + normalized:byte(index)) % 4294967296
    end
    return tostring(kind or "answer") .. ":" .. string.format("%08x", hash)
end

local function copy_messages(messages)
    local result = {}
    for unused_index, message in ipairs(messages or {}) do
        table.insert(result, { role = message.role, content = message.content })
    end
    return result
end

local function fileExists(path)
    local file = io.open(path, "r")
    if not file then
        return false
    end
    file:close()
    return true
end

local function openMRISettings(settings_dir)
    local path = settings_dir .. "/mri.lua"
    local existed = fileExists(path)
    local settings = LuaSettings:open(path)
    if existed or not fileExists(settings_dir .. "/aireader.lua") then
        return settings, false
    end

    local legacy = LuaSettings:open(settings_dir .. "/aireader.lua")
    local keys = {
        "provider",
        "response_length",
        "mri_quick_view",
        "directory_prefetch",
        "directory_book_only",
        "allow_spoilers",
        "auto_recap",
        "auto_recap_show",
    }
    for unused_index, provider_id in ipairs(Providers.order) do
        for unused_field_index, field in ipairs({ "api_key", "model", "endpoint" }) do
            table.insert(keys, "provider_" .. provider_id .. "_" .. field)
        end
    end
    for unused_index, key in ipairs(keys) do
        local value = legacy:readSetting(key)
        if value ~= nil then
            settings:saveSetting(key, value)
        end
    end
    settings:flush()
    return settings, true
end

local function readBookSetting(doc_settings, key, legacy_key, default)
    if not doc_settings then
        return default
    end
    local value = doc_settings:readSetting(key)
    if value == nil and legacy_key then
        value = doc_settings:readSetting(legacy_key)
        if value ~= nil then
            doc_settings:saveSetting(key, value)
        end
    end
    if value == nil then
        return default
    end
    return value
end

local function plainAIOutput(text)
    if type(text) ~= "string" then
        return text
    end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("```[%w_%-]*", "")
    text = text:gsub("!%[([^%]]-)%]%([^%)]-%)", "%1")
    text = text:gsub("%[([^%]]-)%]%([^%)]-%)", "%1")
    text = text:gsub("%*%*", ""):gsub("__", ""):gsub("~~", "")
    text = text:gsub("`([^`\n]-)`", "%1")
    text = text:gsub("%*([^%*\n]-)%*", "%1")
    text = text:gsub("_([^_\n]-)_", "%1")
    text = "\n" .. text
    text = text:gsub("\n[ \t]*#+[ \t]*", "\n")
    text = text:gsub("\n[ \t][ \t]+[%-%*%+][ \t]+", "\n• ")
    text = text:gsub("\n[ \t]*[%-%*%+][ \t]+", "\n- ")
    text = text:gsub("\n[ \t]*•[ \t]*", "\n• ")
    text = text:gsub("\n[ \t]*>[ \t]?", "\n")
    text = text:gsub("\n[ \t]+\n", "\n\n")
    text = text:gsub("\n\n\n+", "\n\n")
    text = text:sub(2)
    text = text:gsub("^根据原文[，,:：%s]*", "", 1)
    text = text:gsub("^从原文来看[，,:：%s]*", "", 1)
    text = text:gsub("^根据这段[^，,。%.!\n]*[，,:：]%s*", "", 1)
    text = text:gsub("^从这段[^，,。%.!\n]*[，,:：]%s*", "", 1)
    text = text:gsub("^根据你提供的[^，,。%.!\n]*[，,:：]%s*", "", 1)
    text = text:gsub("^根据提供的[^，,。%.!\n]*[，,:：]%s*", "", 1)
    text = text:gsub("^Based on the passage[,%s:%-]*", "", 1)
    text = text:gsub("^Based on the excerpt[,%s:%-]*", "", 1)
    text = text:gsub("^From the passage[,%s:%-]*", "", 1)
    text = text:gsub("^From the excerpt[,%s:%-]*", "", 1)
    text = text:gsub("^The supplied text shows that%s+", "", 1)
    return text:gsub("^[ \t\n]+", ""):gsub("[ \t\n]+$", "")
end

local function plainDirectoryOutput(text)
    text = plainAIOutput(text)
    if type(text) ~= "string" then
        return text
    end

    -- Directory entries use blank lines instead of model-dependent numbering.
    -- This also cleans older cached lists and providers that ignore the prompt.
    text = text:gsub("　", " ")
    text = "\n" .. text
    local numbered_markers = {
        "\n[ \t]*%d+[ \t]*%.[ \t]*",
        "\n[ \t]*%d+[ \t]*%)[ \t]*",
        "\n[ \t]*%(%d+%)[ \t]*",
        "\n[ \t]*%d+[ \t]*、[ \t]*",
        "\n[ \t]*%d+[ \t]*．[ \t]*",
        "\n[ \t]*%d+[ \t]*）[ \t]*",
        "\n[ \t]*（%d+）[ \t]*",
    }
    for unused_index, marker in ipairs(numbered_markers) do
        text = text:gsub(marker, "\n\n- ")
    end
    for unused_index, numeral in ipairs({
        "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二",
    }) do
        for unused_separator_index, separator in ipairs({ "、", "．", "）" }) do
            text = text:gsub("\n[ \t]*" .. numeral .. separator .. "[ \t]*", "\n\n- ")
        end
    end
    text = text:gsub("\n[ \t]*%-[ \t]*", "\n- ")
    text = text:gsub("\n[ \t]*•[ \t]*", "\n• ")
    text = text:gsub("\n\n\n+", "\n\n")
    return text:gsub("^[ \t\n]+", ""):gsub("[ \t\n]+$", "")
end

function MRI:init()
    self.settings, self._legacy_settings_migrated = openMRISettings(DataStorage:getSettingsDir())
    self.computer_config = ComputerConfig:new(
        DataStorage:getDataDir() .. "/plugins/mri.koplugin/config.json"
    )
    self.computer_config:load()
    self.api = ApiClient:new()
    self.context = ReaderContext:new(self.ui)
    self.log_path = DataStorage:getSettingsDir() .. "/mri.log"
    self.session_messages = nil
    self.session_title = nil
    self.last_chapter_start = nil
    self.last_chapter_title = nil
    self._reader_ready = false
    self.last_auto_recap = readBookSetting(
        self.ui.doc_settings,
        "mri_last_auto_recap",
        "aireader_last_auto_recap",
        nil
    )
    self.entity_directories = readBookSetting(
        self.ui.doc_settings,
        "mri_entity_directories",
        "aireader_entity_directories",
        {}
    )
    if type(self.entity_directories) ~= "table" then
        self.entity_directories = {}
    end
    self.chapter_memories = readBookSetting(
        self.ui.doc_settings,
        "mri_chapter_memories",
        "aireader_chapter_memories",
        {}
    )
    if type(self.chapter_memories) ~= "table" then
        self.chapter_memories = {}
    end
    if #self.chapter_memories == 0 and self.last_auto_recap and self.last_auto_recap.text then
        table.insert(self.chapter_memories, self.last_auto_recap)
    end
    self.response_cache = readBookSetting(
        self.ui.doc_settings,
        "mri_response_cache",
        "aireader_response_cache",
        {}
    )
    if type(self.response_cache) ~= "table" then
        self.response_cache = {}
    end

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if self.ui.highlight then
        self:addToHighlightDialog()
    end
    self:logEvent(_("信息"), _("MRI 已载入"), self:computerConfigStatus())
    if self._legacy_settings_migrated then
        self:logEvent(_("完成"), _("MRI 设置迁移"), _("已保留旧版设置"))
    end
end

function MRI:onDispatcherRegisterActions()
    Dispatcher:registerAction("mri_open", {
        category = "none",
        event = "MRIOpen",
        title = "MRI",
        reader = true,
    })
    Dispatcher:registerAction("mri_recap", {
        category = "none",
        event = "MRIRecap",
        title = _("MRI: recap"),
        reader = true,
    })
end

function MRI:isEpub()
    local filename = self.ui.document and self.ui.document.file or ""
    return type(filename) == "string" and filename:lower():match("%.epub$") ~= nil
end

function MRI:ensureEpub()
    if self:isEpub() then
        return true
    end
    self:showInfo(_("目前只支持 EPUB。"), 3)
    return false
end

function MRI:showInfo(text, timeout)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

local function safeLogText(text)
    text = tostring(text or "")
    text = text:gsub("[\r\n]+", " ")
    text = text:gsub("[Bb]earer%s+%S+", "Bearer [已隐藏]")
    text = text:gsub("sk%-%S+", "[已隐藏]")
    text = text:gsub("AIza[%w_%-]+", "[已隐藏]")
    if #text > 500 then
        text = util.fixUtf8(text:sub(1, 500), "") .. "…"
    end
    return text
end

function MRI:logEvent(level, action, detail)
    if type(self.log_path) ~= "string" then
        return
    end
    local parts = {
        os.date("%Y-%m-%d %H:%M:%S"),
        safeLogText(level),
        safeLogText(action),
    }
    if detail and tostring(detail) ~= "" then
        table.insert(parts, safeLogText(detail))
    end
    local file = io.open(self.log_path, "a")
    if not file then
        return
    end
    file:write(table.concat(parts, " | "), "\n")
    file:close()

    local reader = io.open(self.log_path, "r")
    if not reader then
        return
    end
    local size = reader:seek("end") or 0
    if size <= LOG_MAX_BYTES then
        reader:close()
        return
    end
    reader:seek("set", math.max(0, size - LOG_KEEP_BYTES))
    local tail = reader:read("*a") or ""
    reader:close()
    tail = util.fixUtf8(tail, "")
    local first_newline = tail:find("\n", 1, true)
    if first_newline then
        tail = tail:sub(first_newline + 1)
    end
    local writer = io.open(self.log_path, "w")
    if writer then
        writer:write(tail)
        writer:close()
    end
end

function MRI:showLog()
    local text = ""
    local file = io.open(self.log_path, "r")
    if file then
        text = file:read("*a") or ""
        file:close()
    end
    if text == "" then
        text = _("还没有运行日志。")
    end
    local viewer
    viewer = TextViewer:new{
        title = _("运行日志"),
        text = text,
        text_type = "book_info",
        add_default_buttons = false,
        buttons_table = {
            {
                {
                    text = _("清空"),
                    callback = function()
                        local clear_file = io.open(self.log_path, "w")
                        if clear_file then
                            clear_file:close()
                        end
                        viewer:onClose()
                        self:showInfo(_("运行日志已清空。"), 2)
                    end,
                },
                {
                    text = _("关闭"),
                    callback = function()
                        viewer:onClose()
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function MRI:saveSetting(key, value)
    self.settings:saveSetting(key, value)
    self.settings:flush()
end

function MRI:spoilersEnabled()
    return self.settings:readSetting("allow_spoilers", false) == true
end

function MRI:responseLength()
    local value = self.settings:readSetting("response_length", "medium")
    if value ~= "short" and value ~= "medium" and value ~= "long" then
        return "medium"
    end
    return value
end

function MRI:responseLengthName()
    local value = self:responseLength()
    if value == "short" then
        return _("短")
    elseif value == "long" then
        return _("长")
    end
    return _("中")
end

function MRI:responseMaxTokens(base)
    if self:responseLength() == "short" then
        return math.max(200, math.floor(base * 0.6))
    elseif self:responseLength() == "long" then
        return math.min(2600, math.floor(base * 1.6))
    end
    return base
end

function MRI:mriQuickViewEnabled()
    return self.settings:nilOrTrue("mri_quick_view")
end

function MRI:directoryPrefetchEnabled()
    return self.settings:nilOrTrue("directory_prefetch")
end

function MRI:directoryBookOnly()
    return self.settings:readSetting("directory_book_only", false) == true
end

function MRI:directoryKnowledgeMode()
    return self:directoryBookOnly() and "book-only" or "hybrid"
end

function MRI:directoryPrefetchTokens()
    if self:responseLength() == "short" then
        return 1800
    elseif self:responseLength() == "long" then
        return 3800
    end
    return 2800
end

function MRI:responseCacheProfile()
    local provider = self:currentProvider()
    local ok_state, state = pcall(function()
        return self.context:readingState()
    end)
    if not ok_state or type(state) ~= "table" then
        state = {}
    end
    return {
        progress_percent = tonumber(state.overall_percent) or 0,
        page = tonumber(state.page) or 1,
        page_count = math.max(1, tonumber(state.page_count) or 1),
        spoilers = self:spoilersEnabled(),
        provider_id = provider and provider.id or "",
        model = provider and provider.model or "",
        endpoint = provider and provider.endpoint or "",
        response_length = self:responseLength(),
        language = _:isChinese() and "zh" or "en",
    }
end

function MRI:cacheEntryFresh(entry, profile)
    if type(entry) ~= "table" or type(entry.text) ~= "string" or entry.text == ""
        or entry.version ~= RESPONSE_CACHE_VERSION then
        return false
    end
    profile = profile or self:responseCacheProfile()
    if entry.spoilers ~= profile.spoilers
        or entry.provider_id ~= profile.provider_id
        or entry.model ~= profile.model
        or entry.endpoint ~= profile.endpoint
        or entry.response_length ~= profile.response_length
        or entry.language ~= profile.language then
        return false
    end
    local cached_progress = tonumber(entry.progress_percent)
    if cached_progress ~= nil then
        return math.abs(profile.progress_percent - cached_progress) <= RESPONSE_CACHE_PROGRESS_DELTA
    end
    local page_delta = math.abs(profile.page - (tonumber(entry.page) or 0))
    return page_delta <= math.max(1, math.floor(profile.page_count *
        RESPONSE_CACHE_PROGRESS_DELTA / 100))
end

function MRI:getCachedAnswer(kind, identity, action)
    local entry = self.response_cache[responseCacheKey(kind, identity)]
    local profile = self:responseCacheProfile()
    if not self:cacheEntryFresh(entry, profile) then
        return nil
    end
    self:logEvent(_("命中缓存"), action or tostring(kind),
        string.format("progress=%.1f%% · cached=%.1f%%",
            profile.progress_percent, tonumber(entry.progress_percent) or 0))
    return entry
end

function MRI:saveCachedAnswer(kind, identity, answer, metadata)
    if type(answer) ~= "string" or answer == "" or not self.ui.doc_settings then
        return
    end
    local profile = self:responseCacheProfile()
    local entry = {
        text = plainAIOutput(answer),
        version = RESPONSE_CACHE_VERSION,
        progress_percent = profile.progress_percent,
        page = profile.page,
        spoilers = profile.spoilers,
        provider_id = profile.provider_id,
        model = profile.model,
        endpoint = profile.endpoint,
        response_length = profile.response_length,
        language = profile.language,
        created_at = os.time(),
    }
    for key, value in pairs(metadata or {}) do
        entry[key] = value
    end
    self.response_cache[responseCacheKey(kind, identity)] = entry

    local count = 0
    for unused_key, unused_entry in pairs(self.response_cache) do
        count = count + 1
    end
    while count > RESPONSE_CACHE_MAX_ENTRIES do
        local oldest_key
        local oldest_time
        for key, cached in pairs(self.response_cache) do
            local created_at = type(cached) == "table" and tonumber(cached.created_at) or 0
            if oldest_time == nil or created_at < oldest_time then
                oldest_key = key
                oldest_time = created_at
            end
        end
        if not oldest_key then
            break
        end
        self.response_cache[oldest_key] = nil
        count = count - 1
    end
    self.ui.doc_settings:saveSetting("mri_response_cache", self.response_cache)
end

function MRI:directoryCacheFresh(entry, state, allow_spoilers)
    if type(entry) ~= "table" or type(entry.text) ~= "string" or entry.text == "" then
        return false
    end
    if entry.spoilers ~= allow_spoilers then
        return false
    end
    if entry.prefetch_version and entry.prefetch_version ~= DIRECTORY_PREFETCH_VERSION then
        return false
    end
    local profile = self:responseCacheProfile()
    if (entry.provider_id ~= nil and entry.provider_id ~= profile.provider_id)
        or (entry.model ~= nil and entry.model ~= profile.model)
        or (entry.endpoint ~= nil and entry.endpoint ~= profile.endpoint)
        or (entry.response_length ~= nil and entry.response_length ~= profile.response_length)
        or (entry.language ~= nil and entry.language ~= profile.language)
        or (entry.knowledge_mode == nil and self:directoryBookOnly())
        or (entry.knowledge_mode ~= nil
            and entry.knowledge_mode ~= self:directoryKnowledgeMode()) then
        return false
    end
    if entry.progress_percent and state.overall_percent then
        return math.abs(state.overall_percent - entry.progress_percent)
            <= RESPONSE_CACHE_PROGRESS_DELTA
    end
    local threshold = math.max(1, math.floor((state.page_count or 1) *
        RESPONSE_CACHE_PROGRESS_DELTA / 100))
    return math.abs((state.page or 1) - (entry.page or 0)) <= threshold
end

function MRI:directoriesNeedPrefetch()
    local ok_state, state = pcall(function()
        return self.context:readingState()
    end)
    if not ok_state or type(state) ~= "table" then
        return false
    end
    local allow_spoilers = self:spoilersEnabled()
    for unused_index, kind in ipairs(DIRECTORY_KINDS) do
        if not self:directoryCacheFresh(self.entity_directories[kind], state, allow_spoilers) then
            return true
        end
    end
    return false
end

local function taggedSection(text, tag)
    if type(text) ~= "string" then
        return nil
    end
    local value = text:match("<" .. tag .. ">%s*([%s%S]-)%s*</" .. tag .. ">")
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

function MRI:runDirectoryPrefetch()
    local provider = self:currentProvider()
    local valid, validation_error = self.api:validate(provider)
    if not valid then
        self:logEvent(_("失败"), _("后台预生成资料表"), validation_error)
        return
    end
    local allow_spoilers = self:spoilersEnabled()
    local sampled_text, sample_error
    if allow_spoilers then
        sampled_text, sample_error = self.context:sampleWholeBook(5000, 6, true)
    else
        sampled_text, sample_error = self.context:sampleReadToCurrent(5000, 6, nil, nil, true)
    end
    if not sampled_text then
        self:logEvent(_("失败"), _("后台预生成资料表"), sample_error)
        return
    end
    local memory = self:chapterMemoryContext(18000)
    if memory then
        sampled_text = "<chapter_memory>\n" .. memory .. "\n</chapter_memory>\n\n" .. sampled_text
    end
    local prompt = Prompts.directory_bundle(
        sampled_text,
        allow_spoilers,
        not self:directoryBookOnly()
    )
    local answer, err = self:requestAI(provider, {
        { role = "system", content = self:systemPrompt() },
        { role = "user", content = prompt },
    }, {
        max_tokens = self:directoryPrefetchTokens(),
        invisible = true,
        log_action = _("后台预生成资料表"),
    })
    if not answer then
        return
    end
    if not self._reader_ready then
        return
    end
    local state = self.context:readingState()
    local cache_profile = self:responseCacheProfile()
    local saved = 0
    for unused_index, kind in ipairs(DIRECTORY_KINDS) do
        local section = taggedSection(answer, kind)
        if section then
            self.entity_directories[kind] = {
                text = plainDirectoryOutput(section),
                page = state.page or self.context:currentPage(),
                progress_percent = state.overall_percent,
                spoilers = allow_spoilers,
                created_at = os.time(),
                prefetched = true,
                prefetch_version = DIRECTORY_PREFETCH_VERSION,
                provider_id = cache_profile.provider_id,
                model = cache_profile.model,
                endpoint = cache_profile.endpoint,
                response_length = cache_profile.response_length,
                language = cache_profile.language,
                knowledge_mode = self:directoryKnowledgeMode(),
            }
            saved = saved + 1
        end
    end
    if saved == 0 then
        self:logEvent(_("失败"), _("后台预生成资料表"), _("无法识别返回内容"))
        return
    end
    if self.ui.doc_settings then
        self.ui.doc_settings:saveSetting("mri_entity_directories", self.entity_directories)
    end
    if saved < #DIRECTORY_KINDS then
        self:logEvent(_("失败"), _("后台预生成资料表"),
            string.format(_("只保存了 %d/3 张资料表"), saved))
    else
        self:logEvent(_("完成"), _("后台预生成资料表"),
            string.format(_("已更新至 %.1f%%"), state.overall_percent or 0))
    end
end

function MRI:scheduleDirectoryPrefetch()
    if not self._reader_ready or not self:directoryPrefetchEnabled()
        or self._prefetch_busy or self._prefetch_job or self._auto_busy then
        return
    end
    if not NetworkMgr:isConnected() or not self:directoriesNeedPrefetch() then
        return
    end
    if self._prefetch_last_attempt and os.time() - self._prefetch_last_attempt < 300 then
        return
    end
    self._prefetch_job = function()
        self._prefetch_job = nil
        if not self._reader_ready or not self:directoryPrefetchEnabled()
            or self._prefetch_busy or self._auto_busy or not NetworkMgr:isConnected()
            or not self:directoriesNeedPrefetch() then
            return
        end
        self._prefetch_last_attempt = os.time()
        self._prefetch_busy = true
        Trapper:wrap(function()
            self:runDirectoryPrefetch()
        end)
        self._prefetch_busy = false
    end
    UIManager:scheduleIn(3, self._prefetch_job)
end

function MRI:systemPrompt()
    return Prompts.system(self:spoilersEnabled(), self:responseLength())
end

function MRI:currentProvider()
    local id = self.settings:readSetting("provider", "openai")
    return Providers:get(id, self.settings, self.computer_config:load())
end

function MRI:requestAI(provider, messages, options)
    options = options or {}
    local enriched = copy_messages(messages)
    if enriched[1] and enriched[1].role == "system" then
        enriched[1].content = self:systemPrompt()
    else
        table.insert(enriched, 1, { role = "system", content = self:systemPrompt() })
    end
    local ok_state, reading_state = pcall(function()
        return self.context:readingState()
    end)
    if not ok_state or type(reading_state) ~= "table" then
        local ok_props, props = pcall(function()
            return self.context:bookProps()
        end)
        local ok_page, page = pcall(function()
            return self.context:currentPage()
        end)
        page = ok_page and math.max(1, tonumber(page) or 1) or 1
        reading_state = {
            title = ok_props and type(props) == "table" and props.title or "Unknown title",
            authors = ok_props and type(props) == "table" and props.authors or "Unknown author",
            page = page,
            page_count = page,
            overall_percent = 0,
            chapter_title = "",
            chapter_page = 1,
            chapter_pages = 1,
            chapter_percent = 0,
        }
    end
    local state_message = {
        role = "system",
        content = Prompts.reading_state(reading_state, self:spoilersEnabled()),
    }
    local insert_at = enriched[1] and enriched[1].role == "system" and 2 or 1
    table.insert(enriched, insert_at, state_message)
    local action = options.log_action or options.progress_text or _("AI 请求")
    local provider_detail = provider and (Providers:name(provider.id) .. " · " .. tostring(provider.model or "")) or ""
    self:logEvent(_("开始"), action, provider_detail)
    local started_at = nowSeconds()
    local answer, err = self.api:request(provider, enriched, options)
    local metrics = {
        elapsed = nowSeconds() - started_at,
        output_bytes = type(answer) == "string" and #answer or 0,
    }
    if not answer then
        self:logEvent(_("失败"), action,
            string.format("%.2fs · %s", metrics.elapsed, tostring(err or _("未知错误"))))
        return nil, err, metrics
    end
    self:logEvent(_("完成"), action,
        string.format("%.2fs · output=%dB", metrics.elapsed, metrics.output_bytes))
    return plainAIOutput(answer), nil, metrics
end

function MRI:saveChapterMemory(memory)
    if type(memory) ~= "table" or type(memory.text) ~= "string" then
        return
    end
    for index = #self.chapter_memories, 1, -1 do
        local existing = self.chapter_memories[index]
        if type(existing) ~= "table" or
            (existing.end_page and memory.end_page and existing.end_page == memory.end_page) or
            (existing.title == memory.title and existing.start_page == memory.start_page) then
            table.remove(self.chapter_memories, index)
        end
    end
    table.insert(self.chapter_memories, memory)
    while #self.chapter_memories > 200 do
        table.remove(self.chapter_memories, 1)
    end
    if self.ui.doc_settings then
        self.ui.doc_settings:saveSetting("mri_chapter_memories", self.chapter_memories)
    end
end

function MRI:chapterMemoryContext(max_bytes)
    local current_page = self.context:currentPage()
    local parts = {}
    for unused_index, memory in ipairs(self.chapter_memories) do
        if type(memory) == "table" and type(memory.text) == "string" and
            (not memory.end_page or memory.end_page <= current_page) then
            table.insert(parts, "【" .. (memory.title or _("章节")) .. "】\n" .. memory.text)
        end
    end
    if #parts == 0 then
        return nil
    end
    local text = table.concat(parts, "\n\n")
    max_bytes = max_bytes or 24000
    if #text <= max_bytes then
        return text
    end
    return table.concat(self.context:chunks(text, math.floor(max_bytes / 3), 3), "\n\n")
end

function MRI:computerConfigStatus()
    self.computer_config:load()
    if self.computer_config.status == "loaded" then
        return _("电脑配置 · 已读取")
    elseif self.computer_config.status == "error" then
        return _("电脑配置 · 格式错误")
    end
    return _("电脑配置 · 未创建")
end

function MRI:showComputerConfigStatus()
    self.computer_config:load()
    local detail
    if self.computer_config.status == "loaded" then
        detail = _("配置已读取。修改后无需在 Kindle 重复输入 Key。")
    elseif self.computer_config.status == "error" then
        detail = self.computer_config.error or _("JSON 格式错误")
    else
        detail = _("请在电脑上编辑 mri.koplugin/config.json。")
    end
    self:showInfo(detail .. "\n\n" .. _("文件：") .. "koreader/plugins/mri.koplugin/config.json", nil)
end

function MRI:testConnection()
    local provider = self:currentProvider()
    local valid, validation_error = self.api:validate(provider)
    if not valid then
        self:logEvent(_("失败"), _("测试连接"), validation_error)
        self:showInfo(validation_error, 4)
        return
    end
    self:withNetwork(function()
        Trapper:wrap(function()
            self:logEvent(_("开始"), _("测试连接"), Providers:name(provider.id) .. " · " .. provider.model)
            local answer, err = self.api:request(provider, {
                { role = "system", content = "Reply with OK only." },
                { role = "user", content = "Connection test." },
            }, {
                max_tokens = 8,
                progress_text = _("正在测试连接…轻触可取消"),
            })
            if not answer then
                if err ~= _("已取消") then
                    self:logEvent(_("失败"), _("测试连接"), err)
                    self:showInfo(err, 4)
                end
                return
            end
            self:logEvent(_("完成"), _("测试连接"))
            self:showInfo(_("连接正常。"), 3)
        end)
    end)
end

function MRI:addToHighlightDialog()
    self.ui.highlight:addToHighlightDialog("11_ai_reader", function(highlight)
        return {
            text = "MRI",
            callback = function()
                local selected = highlight.selected_text or {}
                local selection = {
                    text = selected.text,
                    pos0 = selected.pos0,
                    pos1 = selected.pos1,
                }
                highlight:onClose()
                UIManager:nextTick(function()
                    self:startMRI(selection)
                end)
            end,
        }
    end)
end

function MRI:showQuestionDialog(context, follow_up)
    local dialog
    local buttons = {}
    if _:isChinese() then
        table.insert(buttons, {
            {
                text = _("← 上一字"),
                callback = function()
                    if dialog and dialog._input_widget then
                        dialog._input_widget:leftChar()
                    end
                end,
            },
            {
                text = _("选定 / 空格"),
                callback = function()
                    if dialog and dialog._input_widget then
                        dialog._input_widget:addChars(" ")
                    end
                end,
            },
            {
                text = _("下一字 →"),
                callback = function()
                    if dialog and dialog._input_widget then
                        dialog._input_widget:rightChar()
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("取消"),
            id = "close",
            callback = function()
                UIManager:close(dialog)
            end,
        },
        {
            text = _("提问"),
            is_enter_default = true,
            callback = function()
                local question = clean(dialog:getInputText())
                if question == "" then
                    return
                end
                UIManager:close(dialog)
                if follow_up then
                    self:sendFollowUp(question)
                else
                    self:startQuestion(context, question)
                end
            end,
        },
    })
    dialog = InputDialog:new{
        title = follow_up and _("继续问") or (_("询问 · ") .. context.name),
        input = "",
        input_hint = _("输入问题"),
        deny_keyboard_hiding = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function MRI:withNetwork(callback)
    NetworkMgr:runWhenConnected(callback)
end

function MRI:startQuestion(context, question)
    if not self:ensureEpub() then
        return
    end
    local prompt = Prompts.question(question, context.text)
    local cache_identity = tostring(context.cache_scope or context.name or "book") .. "\n" .. question
    local cached = self:getCachedAnswer("question", cache_identity, _("问这本书"))
    if cached then
        local answer_title = _("回答") .. " · " .. context.name
        self:setSession(prompt, cached.text, answer_title)
        self:showAnswer(answer_title, cached.text)
        return
    end
    self:withNetwork(function()
        Trapper:wrap(function()
            local answer, err = self:requestAI(self:currentProvider(), {
                { role = "system", content = self:systemPrompt() },
                { role = "user", content = prompt },
            }, {
                max_tokens = self:responseMaxTokens(1200),
                progress_text = _("AI 正在阅读…轻触可取消"),
            })
            if not answer then
                if err ~= _("已取消") then
                    self:showInfo(err, 4)
                end
                return
            end
            local answer_title = _("回答") .. " · " .. context.name
            self:saveCachedAnswer("question", cache_identity, answer)
            self:setSession(prompt, answer, answer_title)
            self:showAnswer(answer_title, answer)
        end)
    end)
end

function MRI:setSession(first_prompt, first_answer, title)
    self.session_messages = {
        { role = "system", content = self:systemPrompt() },
        { role = "user", content = first_prompt },
        { role = "assistant", content = first_answer },
    }
    self.session_title = title
end

function MRI:trimSession()
    if not self.session_messages or #self.session_messages <= 7 then
        return
    end
    local old = self.session_messages
    local trimmed = { old[1], old[2], old[3] }
    local start_index = math.max(4, #old - 3)
    for index = start_index, #old do
        table.insert(trimmed, old[index])
    end
    self.session_messages = trimmed
end

function MRI:sendFollowUp(question)
    if not self.session_messages then
        self:showInfo(_("当前没有可继续的对话。"), 3)
        return
    end
    local prompt
    if _:isChinese() then
        prompt = "后续问题：" .. question .. "\n继续遵守阅读边界，使用适合窄屏的清楚结构。"
    else
        prompt = "Follow-up question: " .. question .. "\nKeep the reading boundary and use a clear narrow-screen structure."
    end
    self:withNetwork(function()
        Trapper:wrap(function()
            local messages = copy_messages(self.session_messages)
            table.insert(messages, { role = "user", content = prompt })
            local answer, err = self:requestAI(self:currentProvider(), messages, {
                max_tokens = self:responseMaxTokens(1200),
                progress_text = _("AI 正在回答…轻触可取消"),
            })
            if not answer then
                if err ~= _("已取消") then
                    self:showInfo(err, 4)
                end
                return
            end
            table.insert(self.session_messages, { role = "user", content = prompt })
            table.insert(self.session_messages, { role = "assistant", content = answer })
            self:trimSession()
            self:showAnswer(self.session_title or _("回答"), answer)
        end)
    end)
end

function MRI:showAnswer(title, answer)
    answer = plainAIOutput(answer)
    local viewer
    viewer = TextViewer:new{
        title = title,
        text = answer,
        text_type = "book_info",
        add_default_buttons = false,
        buttons_table = {
            {
                {
                    text = _("继续问"),
                    callback = function()
                        UIManager:close(viewer)
                        self.answer_viewer = nil
                        UIManager:nextTick(function()
                            self:showQuestionDialog({ name = title }, true)
                        end)
                    end,
                },
                {
                    text = _("关闭"),
                    callback = function()
                        viewer:onClose()
                    end,
                },
            },
        },
        close_callback = function()
            self.answer_viewer = nil
            self:clearSession(false)
        end,
    }
    self.answer_viewer = viewer
    UIManager:show(viewer)
    self:scheduleDirectoryPrefetch()
end

function MRI:clearSession(show_notice)
    self.session_messages = nil
    self.session_title = nil
    if show_notice then
        self:showInfo(_("临时对话已清空。"), 2)
    end
end

function MRI:startMRI(selected)
    if not self:ensureEpub() then
        return
    end
    local selection, selection_error
    if type(selected) == "table" then
        selection, selection_error = self.context:selection(selected)
    else
        local text = clean(selected)
        selection = text ~= "" and { name = _("选中文字"), text = text } or nil
    end
    if not selection then
        self:showInfo(selection_error or _("没有有效选中文字"), 3)
        return
    end
    local selected_text = selection.text
    if #selected_text > 12000 then
        selected_text = util.fixUtf8(selected_text:sub(1, 12000), "")
    end
    local cache_identity = selected_text .. "\nquick=" .. tostring(self:mriQuickViewEnabled())
    local cached = self:getCachedAnswer("mri", cache_identity, "MRI")
    if cached then
        local cached_prompt = Prompts.mri(
            selected_text,
            selected_text,
            self:mriQuickViewEnabled()
        )
        self:setSession(cached_prompt, cached.text, "MRI")
        self:showAnswer("MRI", cached.text)
        return
    end
    local valid, validation_error = self.api:validate(self:currentProvider())
    if not valid then
        self:showInfo(validation_error, 4)
        return
    end

    self:withNetwork(function()
        Trapper:wrap(function()
            local mentions
            if #selected_text <= 240 and not selected_text:find("\n", 1, true) then
                local search_error
                mentions, search_error = self.context:findMentions(
                    selected_text,
                    self.context:currentXPointer(),
                    self:spoilersEnabled()
                )
                if not mentions and search_error == _("已取消") then
                    return
                end
            end
            if not mentions and #selected_text <= 240 then
                local chapter = self.context:currentChapter()
                mentions = chapter and chapter.text or nil
            end
            mentions = mentions or selected_text
            local memory = self:chapterMemoryContext(24000)
            if memory then
                local label = _:isChinese() and "已读章节记忆" or "Memory from completed chapters"
                mentions = mentions .. "\n\n<chapter_memory>\n" .. label .. "\n" .. memory .. "\n</chapter_memory>"
            end
            local prompt = Prompts.mri(selected_text, mentions, self:mriQuickViewEnabled())
            local answer, err = self:requestAI(self:currentProvider(), {
                { role = "system", content = self:systemPrompt() },
                { role = "user", content = prompt },
            }, {
                max_tokens = self:responseMaxTokens(1300),
                progress_text = _("MRI 正在整理条目…轻触可取消"),
            })
            if not answer then
                if err ~= _("已取消") then
                    self:showInfo(err, 4)
                end
                return
            end
            self:saveCachedAnswer("mri", cache_identity, answer)
            self:setSession(prompt, answer, "MRI")
            self:showAnswer("MRI", answer)
        end)
    end)
end

function MRI:generateRecap(range, invisible)
    local provider = self:currentProvider()
    local chunks = self.context:chunks(range.text, 42000, 6)
    local prompt = Prompts.recap(range.name, range.text)
    local answer, err = self:requestAI(provider, {
        { role = "system", content = self:systemPrompt() },
        { role = "user", content = prompt },
    }, {
        max_tokens = self:responseMaxTokens(1200),
        invisible = invisible,
        progress_text = _("AI 正在回顾…轻触可取消"),
        log_action = _("回顾 · 整段"),
    })
    if answer or err == _("已取消") or #chunks == 1 or not recapNeedsChunkFallback(err) then
        return answer, err, prompt
    end

    self:logEvent(_("重试"), _("回顾 · 分段"), _("整段超过服务上下文限制"))

    local summaries = {}
    for index, chunk in ipairs(chunks) do
        local chunk_prompt = Prompts.chunk_recap(chunk)
        local summary, err = self:requestAI(provider, {
            { role = "system", content = self:systemPrompt() },
            { role = "user", content = chunk_prompt },
        }, {
            max_tokens = 500,
            invisible = invisible,
            progress_text = _("AI 正在回顾…轻触可取消") .. " " .. tostring(index) .. "/" .. tostring(#chunks),
            log_action = _("回顾 · 分段") .. " " .. tostring(index) .. "/" .. tostring(#chunks),
        })
        if not summary then
            return nil, err
        end
        local label = _:isChinese() and "片段 " or "Segment "
        table.insert(summaries, label .. tostring(index) .. ": " .. summary)
    end

    local final_prompt = Prompts.synthesise_recap(range.name, table.concat(summaries, "\n"))
    local answer, err = self:requestAI(provider, {
        { role = "system", content = self:systemPrompt() },
        { role = "user", content = final_prompt },
    }, {
        max_tokens = self:responseMaxTokens(1200),
        invisible = invisible,
        progress_text = _("AI 正在合并回顾…轻触可取消"),
        log_action = _("回顾 · 合并"),
    })
    return answer, err, final_prompt
end

function MRI:runRecapBenchmark()
    if not self:ensureEpub() then
        return
    end
    if self._recap_benchmark_busy then
        self:showInfo(_("回顾测速正在运行。"), 3)
        return
    end
    local provider = self:currentProvider()
    local valid, validation_error = self.api:validate(provider)
    if not valid then
        self:showInfo(validation_error, 4)
        return
    end

    self._recap_benchmark_busy = true
    self:withNetwork(function()
        Trapper:wrap(function()
            local sampled_text, sample_error = self.context:sampleReadToCurrent(36000, 6)
            if not sampled_text then
                self:logEvent(_("失败"), _("回顾测速"), sample_error)
                if sample_error ~= _("已取消") then
                    self:showInfo(sample_error, 4)
                end
                return
            end
            local memory = self:chapterMemoryContext(30000)
            local source_text = memory and ("<chapter_memory>\n" .. memory ..
                "\n</chapter_memory>\n\n" .. sampled_text) or sampled_text
            local chunks = self.context:chunks(source_text, 42000, 6)
            if #chunks < 2 then
                self:logEvent(_("跳过"), _("回顾测速"),
                    string.format("source=%dB · chunks=1", #source_text))
                self:showInfo(_("当前内容只有一段，无需比较。"), 4)
                return
            end

            local split_bytes = 0
            for unused_index, chunk in ipairs(chunks) do
                split_bytes = split_bytes + #chunk
            end
            local token_divisor = _:isChinese() and 3 or 4
            local test_id = os.date("%Y%m%d-%H%M%S")
            local provider_name = Providers:name(provider.id) .. " · " .. tostring(provider.model or "")
            self:logEvent(_("开始"), _("回顾测速"), string.format(
                "id=%s · %s · source=%dB (~%d tokens) · split=%dB/%d chunks (~%d tokens) · order=whole>split",
                test_id, provider_name, #source_text, math.ceil(#source_text / token_divisor),
                split_bytes, #chunks, math.ceil(split_bytes / token_divisor)))

            local whole_prompt = Prompts.recap(_("开头到这里"), source_text)
            local whole_answer, whole_error, whole_metrics = self:requestAI(provider, {
                { role = "system", content = self:systemPrompt() },
                { role = "user", content = whole_prompt },
            }, {
                max_tokens = self:responseMaxTokens(1200),
                progress_text = _("正在测试整段回顾…轻触可取消"),
                log_action = _("回顾测速 · 整段"),
            })
            whole_metrics = whole_metrics or { elapsed = 0, output_bytes = 0 }
            self:logEvent(whole_answer and _("完成") or _("失败"), _("回顾测速"), string.format(
                "id=%s · mode=whole · calls=1 · input=%dB · elapsed=%.2fs · output=%dB%s",
                test_id, #source_text, whole_metrics.elapsed or 0, whole_metrics.output_bytes or 0,
                whole_error and (" · " .. tostring(whole_error)) or ""))
            if whole_error == _("已取消") then
                self:showInfo(_("已取消"), 2)
                return
            end

            local summaries = {}
            local split_total = 0
            local split_error
            for index, chunk in ipairs(chunks) do
                local chunk_prompt = Prompts.chunk_recap(chunk)
                local summary, err, metrics = self:requestAI(provider, {
                    { role = "system", content = self:systemPrompt() },
                    { role = "user", content = chunk_prompt },
                }, {
                    max_tokens = 500,
                    progress_text = _("正在测试分段回顾…轻触可取消") .. " " ..
                        tostring(index) .. "/" .. tostring(#chunks),
                    log_action = _("回顾测速 · 分段") .. " " ..
                        tostring(index) .. "/" .. tostring(#chunks),
                })
                metrics = metrics or { elapsed = 0, output_bytes = 0 }
                split_total = split_total + (metrics.elapsed or 0)
                self:logEvent(summary and _("完成") or _("失败"), _("回顾测速"), string.format(
                    "id=%s · mode=split · part=%d/%d · input=%dB · elapsed=%.2fs · output=%dB%s",
                    test_id, index, #chunks, #chunk, metrics.elapsed or 0,
                    metrics.output_bytes or 0, err and (" · " .. tostring(err)) or ""))
                if not summary then
                    split_error = err
                    break
                end
                local label = _:isChinese() and "片段 " or "Segment "
                table.insert(summaries, label .. tostring(index) .. ": " .. summary)
            end

            local split_answer
            if not split_error then
                local merge_prompt = Prompts.synthesise_recap(_("开头到这里"), table.concat(summaries, "\n"))
                local merge_metrics
                split_answer, split_error, merge_metrics = self:requestAI(provider, {
                    { role = "system", content = self:systemPrompt() },
                    { role = "user", content = merge_prompt },
                }, {
                    max_tokens = self:responseMaxTokens(1200),
                    progress_text = _("正在测试合并回顾…轻触可取消"),
                    log_action = _("回顾测速 · 合并"),
                })
                merge_metrics = merge_metrics or { elapsed = 0, output_bytes = 0 }
                split_total = split_total + (merge_metrics.elapsed or 0)
                self:logEvent(split_answer and _("完成") or _("失败"), _("回顾测速"), string.format(
                    "id=%s · mode=merge · input=%dB · elapsed=%.2fs · output=%dB%s",
                    test_id, #merge_prompt, merge_metrics.elapsed or 0,
                    merge_metrics.output_bytes or 0,
                    split_error and (" · " .. tostring(split_error)) or ""))
            end

            local complete = whole_answer and split_answer
            local faster = "incomplete"
            if complete then
                faster = (whole_metrics.elapsed or 0) <= split_total and "whole" or "split"
            end
            self:logEvent(complete and _("完成") or _("失败"), _("回顾测速"), string.format(
                "id=%s · RESULT · whole=%.2fs/1 call/%dB input · split=%.2fs/%d calls/%dB input · faster=%s",
                test_id, whole_metrics.elapsed or 0, #source_text, split_total, #chunks + 1,
                split_bytes, faster))
            if complete then
                self:showInfo(string.format(
                    _("测速完成。整段 %.1f 秒；分段 %.1f 秒。详情已写入运行日志。"),
                    whole_metrics.elapsed or 0, split_total), 6)
            else
                self:showInfo(_("测速未完整完成，错误和耗时已写入运行日志。"), 6)
            end
        end)
        self._recap_benchmark_busy = false
    end)
end

function MRI:manualRecap(scope)
    if not self:ensureEpub() then
        return
    end
    local current_page = self.context:currentPage()
    local cache_anchor = scope == "current" and "read-to-current"
        or (scope .. ":" .. tostring(self.context:chapterStartPage(current_page)))
    local cached = self:getCachedAnswer("recap", cache_anchor, _("回顾阅读"))
    if cached then
        local cached_title = cached.title or _("回顾阅读")
        self:setSession(_("已缓存的回顾"), cached.text, cached_title)
        self:showAnswer(cached_title, cached.text)
        return
    end
    local valid, validation_error = self.api:validate(self:currentProvider())
    if not valid then
        self:showInfo(validation_error, 4)
        return
    end

    self:withNetwork(function()
        Trapper:wrap(function()
            local range, range_error
            if scope == "chapter" then
                range, range_error = self.context:currentChapter()
            elseif scope == "previous" then
                range, range_error = self.context:previousTwoChapters()
            else
                local sampled_text
                sampled_text, range_error = self.context:sampleReadToCurrent(36000, 6)
                if sampled_text then
                    local memory = self:chapterMemoryContext(30000)
                    range = {
                        name = _("开头到这里"),
                        text = memory and ("<chapter_memory>\n" .. memory ..
                            "\n</chapter_memory>\n\n" .. sampled_text) or sampled_text,
                    }
                end
            end
            if not range then
                if range_error ~= _("已取消") then
                    self:showInfo(range_error, 4)
                end
                return
            end
            local answer, err, prompt = self:generateRecap(range, false)
            if not answer then
                if err ~= _("已取消") then
                    self:showInfo(err, 4)
                end
                return
            end
            local answer_title = _("回顾 · ") .. range.name
            self:saveCachedAnswer("recap", cache_anchor, answer, { title = answer_title })
            self:setSession(prompt, answer, answer_title)
            self:showAnswer(answer_title, answer)
        end)
    end)
end

function MRI:showLastAutoRecap()
    if not self.last_auto_recap or not self.last_auto_recap.text then
        self:showInfo(_("还没有自动回顾。"), 3)
        return
    end
    local viewer
    viewer = TextViewer:new{
        title = _("上次自动回顾 · ") .. (self.last_auto_recap.title or _("章节")),
        text = plainAIOutput(self.last_auto_recap.text),
        text_type = "book_info",
        add_default_buttons = false,
        buttons_table = {
            {
                {
                    text = _("关闭"),
                    callback = function()
                        viewer:onClose()
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function MRI:directoryName(kind)
    if kind == "people" then
        return _("人物表")
    elseif kind == "places" then
        return _("地点表")
    end
    return _("概念表")
end

function MRI:showEntityDirectory(kind)
    local entry = self.entity_directories[kind]
    local ok_state, state = pcall(function()
        return self.context:readingState()
    end)
    if not ok_state or type(state) ~= "table"
        or not self:directoryCacheFresh(entry, state, self:spoilersEnabled()) then
        self:generateEntityDirectory(kind)
        return
    end
    self:logEvent(_("命中缓存"), self:directoryName(kind),
        string.format("progress=%.1f%% · cached=%.1f%%",
            tonumber(state.overall_percent) or 0,
            tonumber(entry.progress_percent) or 0))

    local display_text = plainDirectoryOutput(entry.text)
    local title = self:directoryName(kind)
    if entry.page then
        title = title .. " · " .. _("更新于第 ") .. tostring(entry.page) .. _(" 页")
    end
    local context_prompt
    local loaded_answer
    if _:isChinese() then
        context_prompt = "以下是依据已读原文生成的“" .. self:directoryName(kind) .. "”。后续只根据这份内容回答：\n" .. display_text
        loaded_answer = "已载入这份“" .. self:directoryName(kind) .. "”。"
    else
        context_prompt = "The following list was generated from the text read so far. Answer follow-up questions using only this list:\n" .. display_text
        loaded_answer = "This list is ready for follow-up questions."
    end
    self:setSession(context_prompt, loaded_answer, self:directoryName(kind))

    local viewer
    viewer = TextViewer:new{
        title = title,
        text = display_text,
        text_type = "book_info",
        add_default_buttons = false,
        buttons_table = {
            {
                {
                    text = _("继续问"),
                    callback = function()
                        UIManager:close(viewer)
                        UIManager:nextTick(function()
                            self:showQuestionDialog({ name = self:directoryName(kind) }, true)
                        end)
                    end,
                },
                {
                    text = _("更新"),
                    callback = function()
                        UIManager:close(viewer)
                        self:clearSession(false)
                        UIManager:nextTick(function()
                            self:generateEntityDirectory(kind)
                        end)
                    end,
                },
            },
            {
                {
                    text = _("关闭"),
                    callback = function()
                        viewer:onClose()
                    end,
                },
            },
        },
        close_callback = function()
            self:clearSession(false)
        end,
    }
    UIManager:show(viewer)
end

function MRI:generateEntityDirectory(kind)
    if not self:ensureEpub() then
        return
    end
    local provider = self:currentProvider()
    local valid, validation_error = self.api:validate(provider)
    if not valid then
        self:showInfo(validation_error, 4)
        return
    end

    local directory_name = self:directoryName(kind)
    self:withNetwork(function()
        Trapper:wrap(function()
            local allow_spoilers = self:spoilersEnabled()
            local use_book_knowledge = not self:directoryBookOnly()

            local function collectSamples(max_bytes, max_samples, memory_bytes)
                local sampled_text, sample_error
                if allow_spoilers then
                    sampled_text, sample_error = self.context:sampleWholeBook(max_bytes, max_samples)
                else
                    sampled_text, sample_error = self.context:sampleReadToCurrent(max_bytes, max_samples)
                end
                if not sampled_text then
                    return nil, sample_error
                end
                local samples = {}
                local memory = self:chapterMemoryContext(memory_bytes)
                if memory then
                    table.insert(samples, "[chapter memory]\n" .. memory)
                end
                table.insert(samples, sampled_text)
                return table.concat(samples, "\n\n")
            end

            local sample_text, sample_error
            if use_book_knowledge then
                sample_text, sample_error = collectSamples(6000, 3, 12000)
            else
                sample_text, sample_error = collectSamples(12000, 6, 24000)
            end
            if not sample_text then
                if sample_error ~= _("已取消") then
                    self:showInfo(sample_error, 4)
                end
                return
            end

            local final_prompt = Prompts.directory(
                kind,
                sample_text,
                allow_spoilers,
                use_book_knowledge,
                false
            )
            local answer, err = self:requestAI(provider, {
                { role = "system", content = self:systemPrompt() },
                { role = "user", content = final_prompt },
            }, {
                max_tokens = self:responseMaxTokens(1600),
                progress_text = _("正在整理") .. directory_name .. "…",
                log_action = directory_name .. " · " ..
                    (use_book_knowledge and _("自动混合") or _("只依据本书")),
            })
            if not answer then
                if err ~= _("已取消") then
                    self:showInfo(err, 4)
                end
                return
            end

            if use_book_knowledge
                and answer:lower():find("<need_more_context>", 1, true) then
                self:logEvent(_("重试"), directory_name, _("模型需要更多书内样本"))
                sample_text, sample_error = collectSamples(12000, 6, 24000)
                if not sample_text then
                    if sample_error ~= _("已取消") then
                        self:showInfo(sample_error, 4)
                    end
                    return
                end
                final_prompt = Prompts.directory(kind, sample_text, allow_spoilers, true, true)
                answer, err = self:requestAI(provider, {
                    { role = "system", content = self:systemPrompt() },
                    { role = "user", content = final_prompt },
                }, {
                    max_tokens = self:responseMaxTokens(1600),
                    progress_text = _("正在补充书内样本…轻触可取消"),
                    log_action = directory_name .. " · " .. _("扩大样本"),
                })
                if not answer then
                    if err ~= _("已取消") then
                        self:showInfo(err, 4)
                    end
                    return
                end
            end

            local state = self.context:readingState()
            local cache_profile = self:responseCacheProfile()
            self.entity_directories[kind] = {
                text = plainDirectoryOutput(answer),
                page = state.page or self.context:currentPage(),
                progress_percent = state.overall_percent,
                spoilers = allow_spoilers,
                created_at = os.time(),
                provider_id = cache_profile.provider_id,
                model = cache_profile.model,
                endpoint = cache_profile.endpoint,
                response_length = cache_profile.response_length,
                language = cache_profile.language,
                knowledge_mode = self:directoryKnowledgeMode(),
            }
            if self.ui.doc_settings then
                self.ui.doc_settings:saveSetting("mri_entity_directories", self.entity_directories)
            end
            self:showEntityDirectory(kind)
        end)
    end)
end

function MRI:askBook()
    if not self:ensureEpub() then
        return
    end
    Trapper:wrap(function()
        local allow_spoilers = self:spoilersEnabled()
        local text, err
        if allow_spoilers then
            text, err = self.context:sampleWholeBook(14000, 7)
        else
            text, err = self.context:sampleReadToCurrent(16000, 7)
        end
        if not text then
            if err ~= _("已取消") then
                self:showInfo(err, 4)
            end
            return
        end
        local memory = self:chapterMemoryContext(24000)
        if memory then
            text = "<chapter_memory>\n" .. memory .. "\n</chapter_memory>\n\n" .. text
        end
        local state = self.context:readingState()
        local name
        if allow_spoilers then
            name = _("全书 · 含剧透")
        else
            name = string.format(_("已读内容 · %.1f%%"), state.overall_percent or 0)
        end
        self:showQuestionDialog({
            name = name,
            text = text,
            cache_scope = allow_spoilers and "whole-book" or "read-to-current",
        }, false)
    end)
end

function MRI:generateBookIntro()
    if not self:ensureEpub() then
        return
    end
    local allow_spoilers = self:spoilersEnabled()
    local cache_identity = allow_spoilers and "whole-book" or "read-to-current"
    local cached = self:getCachedAnswer("book-intro", cache_identity, _("全书简介"))
    if cached then
        local cached_prompt = Prompts.book_intro("", allow_spoilers)
        self:setSession(cached_prompt, cached.text, _("全书简介"))
        self:showAnswer(_("全书简介"), cached.text)
        return
    end
    local provider = self:currentProvider()
    local valid, validation_error = self.api:validate(provider)
    if not valid then
        self:showInfo(validation_error, 4)
        return
    end

    self:withNetwork(function()
        Trapper:wrap(function()
            local context, context_error
            if allow_spoilers then
                context, context_error = self.context:sampleWholeBook(14000, 7)
            else
                context, context_error = self.context:sampleReadToCurrent(12000, 6)
            end
            if not context then
                if context_error ~= _("已取消") then
                    self:showInfo(context_error, 4)
                end
                return
            end
            local prompt = Prompts.book_intro(context, allow_spoilers)
            local answer, err = self:requestAI(provider, {
                { role = "system", content = self:systemPrompt() },
                { role = "user", content = prompt },
            }, {
                max_tokens = self:responseMaxTokens(1700),
                progress_text = _("AI 正在生成全书简介…轻触可取消"),
            })
            if not answer then
                if err ~= _("已取消") then
                    self:showInfo(err, 4)
                end
                return
            end
            self:saveCachedAnswer("book-intro", cache_identity, answer)
            self:setSession(prompt, answer, _("全书简介"))
            self:showAnswer(_("全书简介"), answer)
        end)
    end)
end

function MRI:showRecapDialog()
    if not self:ensureEpub() then
        return
    end
    local dialog
    dialog = ButtonDialog:new{
        title = _("回顾阅读"),
        buttons = {
            {
                {
                    text = _("当前章到这里"),
                    callback = function()
                        UIManager:close(dialog)
                        self:manualRecap("chapter")
                    end,
                },
            },
            {
                {
                    text = _("前两章"),
                    callback = function()
                        UIManager:close(dialog)
                        self:manualRecap("previous")
                    end,
                },
                {
                    text = _("开头到这里"),
                    callback = function()
                        UIManager:close(dialog)
                        self:manualRecap("current")
                    end,
                },
            },
            {
                {
                    text = _("全书简介"),
                    callback = function()
                        UIManager:close(dialog)
                        self:generateBookIntro()
                    end,
                },
            },
            {
                {
                    text = _("上次自动回顾"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showLastAutoRecap()
                    end,
                },
                {
                    text = _("关闭"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function MRI:showHomeDialog()
    if not self:ensureEpub() then
        return
    end
    local dialog
    dialog = ButtonDialog:new{
        title = "MRI",
        buttons = {
            {
                {
                    text = _("回顾阅读"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showRecapDialog()
                    end,
                },
                {
                    text = _("问这本书"),
                    callback = function()
                        UIManager:close(dialog)
                        self:askBook()
                    end,
                },
            },
            {
                {
                    text = _("人物表"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showEntityDirectory("people")
                    end,
                },
                {
                    text = _("地点表"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showEntityDirectory("places")
                    end,
                },
            },
            {
                {
                    text = _("概念表"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showEntityDirectory("concepts")
                    end,
                },
            },
            {
                {
                    text = _("上次自动回顾"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showLastAutoRecap()
                    end,
                },
                {
                    text = _("关闭"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function MRI:onMRIOpen()
    self:showHomeDialog()
end

function MRI:onMRIRecap()
    self:showRecapDialog()
end

function MRI:editProviderField(field, title, password)
    local provider = self:currentProvider()
    local value = field == "api_key" and provider.api_key or provider[field]
    local dialog
    dialog = InputDialog:new{
        title = title .. " · " .. Providers:name(provider.id),
        input = value or "",
        text_type = password and "password" or nil,
        description = password and _("Key 会以明文保存在本机 KOReader 设置中，不会写入日志。") or nil,
        buttons = {
            {
                {
                    text = _("取消"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("保存"),
                    is_enter_default = true,
                    callback = function()
                        local new_value = clean(dialog:getInputText())
                        self:saveSetting("provider_" .. provider.id .. "_" .. field, new_value)
                        UIManager:close(dialog)
                        self:showInfo(_("已保存。"), 2)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function MRI:providerMenuItems()
    local items = {}
    for unused_index, id in ipairs(Providers.order) do
        local provider_id = id
        table.insert(items, {
            text = Providers:name(provider_id),
            radio = true,
            checked_func = function()
                return self.settings:readSetting("provider", "openai") == provider_id
            end,
            callback = function()
                self:saveSetting("provider", provider_id)
            end,
        })
    end
    return items
end

function MRI:responseLengthMenuItems()
    local items = {}
    local choices = {
        { id = "short", name = _("短") },
        { id = "medium", name = _("中") },
        { id = "long", name = _("长") },
    }
    for unused_index, choice in ipairs(choices) do
        local value = choice.id
        table.insert(items, {
            text = choice.name,
            radio = true,
            checked_func = function()
                return self:responseLength() == value
            end,
            callback = function()
                self:saveSetting("response_length", value)
            end,
        })
    end
    return items
end

function MRI:showAbout()
    local version = self.meta and self.meta.version or MRI_VERSION
    local about
    about = TextViewer:new{
        title = _("关于 MRI"),
        text = table.concat({
            "MRI",
            "",
            _("版本") .. ": " .. tostring(version),
            _("作者") .. ": Frank Shi",
            "Copyright © 2026 Frank Shi",
            _("许可证") .. ": " .. _("GNU AGPL v3.0 或更新版本"),
            "",
            _("面向 Kindle 和 KOReader 的 EPUB AI 阅读助手。"),
            "",
            _("项目主页") .. ":",
            MRI_GITHUB_URL,
        }, "\n"),
        justified = false,
        buttons_table = {
            {
                {
                    text = _("打开 GitHub"),
                    callback = function()
                        if type(Device.canOpenLink) == "function"
                                and Device:canOpenLink()
                                and type(Device.openLink) == "function" then
                            Device:openLink(MRI_GITHUB_URL)
                        else
                            self:showInfo(_("这台设备无法直接打开网页。GitHub 地址已显示在页面中。"), 3)
                        end
                    end,
                },
                {
                    text = _("关闭"),
                    callback = function()
                        UIManager:close(about)
                    end,
                },
            },
        },
    }
    UIManager:show(about)
end

function MRI:addToMainMenu(menu_items)
    menu_items.mri = {
        text = "MRI",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("回顾阅读"),
                sub_item_table = {
                    {
                        text = _("当前章到这里"),
                        callback = function() self:manualRecap("chapter") end,
                    },
                    {
                        text = _("前两章"),
                        callback = function() self:manualRecap("previous") end,
                    },
                    {
                        text = _("开头到这里"),
                        callback = function() self:manualRecap("current") end,
                    },
                    {
                        text = _("全书简介"),
                        callback = function() self:generateBookIntro() end,
                    },
                    {
                        text = _("上次自动回顾"),
                        enabled_func = function() return self.last_auto_recap ~= nil end,
                        callback = function() self:showLastAutoRecap() end,
                    },
                },
            },
            {
                text = _("问这本书"),
                callback = function() self:askBook() end,
            },
            {
                text = _("人物、地点与概念"),
                sub_item_table = {
                    {
                        text = _("人物表"),
                        callback = function() self:showEntityDirectory("people") end,
                    },
                    {
                        text = _("地点表"),
                        callback = function() self:showEntityDirectory("places") end,
                    },
                    {
                        text = _("概念表"),
                        callback = function() self:showEntityDirectory("concepts") end,
                    },
                    {
                        text = _("更新人物表"),
                        callback = function() self:generateEntityDirectory("people") end,
                        separator = true,
                    },
                    {
                        text = _("更新地点表"),
                        callback = function() self:generateEntityDirectory("places") end,
                    },
                    {
                        text = _("更新概念表"),
                        callback = function() self:generateEntityDirectory("concepts") end,
                    },
                },
            },
            {
                text_func = function()
                    local id = self.settings:readSetting("provider", "openai")
                    return _("AI 服务与设置 · ") .. Providers:name(id)
                end,
                sub_item_table = {
                    {
                        text_func = function()
                            local id = self.settings:readSetting("provider", "openai")
                            return _("AI 服务 · ") .. Providers:name(id)
                        end,
                        sub_item_table = self:providerMenuItems(),
                    },
                    {
                        text_func = function() return self:computerConfigStatus() end,
                        callback = function() self:showComputerConfigStatus() end,
                    },
                    {
                        text_func = function()
                            return _("回答长度 · ") .. self:responseLengthName()
                        end,
                        sub_item_table = self:responseLengthMenuItems(),
                    },
                    {
                        text = _("MRI 先显示速览"),
                        checked_func = function() return self:mriQuickViewEnabled() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self.settings:flipNilOrTrue("mri_quick_view")
                            self.settings:flush()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("后台预生成资料表"),
                        checked_func = function() return self:directoryPrefetchEnabled() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self.settings:flipNilOrTrue("directory_prefetch")
                            self.settings:flush()
                            if not self:directoryPrefetchEnabled() and self._prefetch_job then
                                UIManager:unschedule(self._prefetch_job)
                                self._prefetch_job = nil
                            end
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("资料表只依据本书文字"),
                        checked_func = function() return self:directoryBookOnly() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:saveSetting("directory_book_only", not self:directoryBookOnly())
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("测试连接"),
                        callback = function() self:testConnection() end,
                    },
                    {
                        text = _("更多"),
                        sub_item_table = {
                            {
                                text = _("在 Kindle 设置 API Key（备用）"),
                                callback = function() self:editProviderField("api_key", "API Key", true) end,
                            },
                            {
                                text = _("设置模型"),
                                callback = function() self:editProviderField("model", _("模型")) end,
                            },
                            {
                                text = _("设置接口地址"),
                                callback = function() self:editProviderField("endpoint", _("接口地址")) end,
                            },
                            {
                                text = _("关于 MRI"),
                                callback = function() self:showAbout() end,
                                separator = true,
                            },
                        },
                    },
                    {
                        text = _("允许当前位置后剧透"),
                        checked_func = function() return self:spoilersEnabled() end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:saveSetting("allow_spoilers", not self:spoilersEnabled())
                            self:clearSession(false)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                        separator = true,
                    },
                    {
                        text = _("自动回顾刚读完的章节"),
                        checked_func = function() return self.settings:nilOrTrue("auto_recap") end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self.settings:flipNilOrTrue("auto_recap")
                            self.settings:flush()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("生成后立即显示回顾"),
                        checked_func = function() return self.settings:nilOrTrue("auto_recap_show") end,
                        enabled_func = function() return self.settings:nilOrTrue("auto_recap") end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self.settings:flipNilOrTrue("auto_recap_show")
                            self.settings:flush()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("清除临时对话"),
                        enabled_func = function() return self.session_messages ~= nil end,
                        callback = function() self:clearSession(true) end,
                        separator = true,
                    },
                    {
                        text = _("测试回顾速度（已读内容）"),
                        callback = function() self:runRecapBenchmark() end,
                    },
                    {
                        text = _("运行日志"),
                        callback = function() self:showLog() end,
                    },
                    {
                        text = _("使用与隐私说明"),
                        callback = function()
                            self:showInfo(_("只支持 EPUB。每次请求附带书名和阅读进度。剧透关闭时，只发送当前位置之前或你明确选中的文字；剧透开启时，MRI、全书简介、问这本书和人物地点概念表可以发送全书样本。连续对话关书即清空；自动回顾、章节记忆、三个资料表和最多 80 条 AI 回答缓存随本书保存。API Key 明文保存在 Kindle 本机。"), nil)
                        end,
                    },
                },
            },
        },
    }
end

function MRI:onPageUpdate(pageno)
    if not self._reader_ready or not self:isEpub() then
        return
    end
    local new_start = self.context:chapterStartPage(pageno)
    local new_title = self.context:chapterTitle(pageno)
    local old_start = self.last_chapter_start
    local old_title = self.last_chapter_title
    if not old_start then
        self.last_chapter_start = new_start
        self.last_chapter_title = new_title
        return
    end
    if new_start == old_start then
        self.last_chapter_title = new_title
        return
    end
    self.last_chapter_start = new_start
    self.last_chapter_title = new_title
    -- Pagination changes after a font/layout update can move ToC page numbers.
    -- Treat an unchanged chapter title as reflow, not as reading progress.
    if new_title ~= "" and new_title == old_title then
        return
    end
    if new_start > old_start and self.settings:nilOrTrue("auto_recap") then
        self:queueAutoRecap(old_start, new_start)
    end
end

function MRI:onReaderReady()
    -- CRE and the ToC are still settling while document plugins are created.
    -- Wait for a real page update before touching XPointer/ToC APIs.
    self._reader_ready = true
end

function MRI:queueAutoRecap(start_page, end_page)
    if self.last_auto_recap and self.last_auto_recap.end_page == end_page then
        return
    end
    if self._auto_job then
        UIManager:unschedule(self._auto_job)
    end
    self._auto_job = function()
        self._auto_job = nil
        if self._auto_busy or not self.settings:nilOrTrue("auto_recap") then
            return
        end
        if not NetworkMgr:isConnected() then
            self:logEvent(_("跳过"), _("自动回顾"), _("网络未连接"))
            return
        end
        local provider = self:currentProvider()
        local valid, validation_error = self.api:validate(provider)
        if not valid then
            self:logEvent(_("失败"), _("自动回顾"), validation_error)
            return
        end
        self._auto_busy = true
        Trapper:wrap(function()
            local range = self.context:finishedChapter(start_page, end_page)
            if range then
                local answer = self:generateRecap(range, true)
                if answer then
                    self.last_auto_recap = {
                        title = range.name,
                        text = answer,
                        start_page = start_page,
                        end_page = end_page,
                        created_at = os.time(),
                    }
                    self:saveChapterMemory(self.last_auto_recap)
                    if self.ui.doc_settings then
                        self.ui.doc_settings:saveSetting("mri_last_auto_recap", self.last_auto_recap)
                    end
                    if self.settings:nilOrTrue("auto_recap_show") then
                        UIManager:nextTick(function()
                            self:showLastAutoRecap()
                        end)
                    end
                end
            end
            self._auto_busy = false
        end)
    end
    UIManager:scheduleIn(2, self._auto_job)
end

function MRI:onFlushSettings()
    self.settings:flush()
end

function MRI:onCloseDocument()
    self._reader_ready = false
    if self._auto_job then
        UIManager:unschedule(self._auto_job)
        self._auto_job = nil
    end
    if self._prefetch_job then
        UIManager:unschedule(self._prefetch_job)
        self._prefetch_job = nil
    end
    self:clearSession(false)
end

return MRI
