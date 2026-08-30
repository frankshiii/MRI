-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Frank

local Trapper = require("ui/trapper")
local _ = require("i18n")
local util = require("util")

local ReaderContext = {}
ReaderContext.__index = ReaderContext

function ReaderContext:new(ui)
    return setmetatable({ ui = ui, document = ui.document }, self)
end

local function clean(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("\194\160", " ")
    return util.cleanupSelectedText(text)
end

local function utf8_tail(text, max_bytes)
    local start_pos = math.max(1, #text - max_bytes + 1)
    while start_pos <= #text do
        local byte = text:byte(start_pos)
        if not byte or byte < 128 or byte >= 192 then
            break
        end
        start_pos = start_pos + 1
    end
    return text:sub(start_pos)
end

function ReaderContext:currentPage()
    if self.ui.getCurrentPage then
        return self.ui:getCurrentPage()
    end
    return self.document:getCurrentPage()
end

function ReaderContext:currentXPointer()
    return self.document:getXPointer()
end

local function normalized_prop(value)
    if type(value) == "table" then
        local parts = {}
        for unused_index, item in ipairs(value) do
            if type(item) == "string" and clean(item) ~= "" then
                table.insert(parts, clean(item))
            end
        end
        return table.concat(parts, ", ")
    end
    if type(value) == "string" then
        return clean(value)
    end
    return ""
end

function ReaderContext:bookProps()
    local title = ""
    local authors = ""
    local ok, props = pcall(function()
        return self.document:getProps()
    end)
    if ok and type(props) == "table" then
        title = normalized_prop(props.title)
        authors = normalized_prop(props.authors)
    end
    if self.ui.doc_settings then
        local ok_child, saved_props = pcall(function()
            return self.ui.doc_settings:child("doc_props")
        end)
        if ok_child and saved_props then
            local ok_saved, saved_title, saved_authors = pcall(function()
                return saved_props:readSetting("title"), saved_props:readSetting("authors")
            end)
            if ok_saved then
                title = title ~= "" and title or normalized_prop(saved_title)
                authors = authors ~= "" and authors or normalized_prop(saved_authors)
            end
        end
    end
    if title == "" then
        local filename = type(self.document.file) == "string" and self.document.file:match("([^/]+)$") or ""
        title = filename:gsub("%.[Ee][Pp][Uu][Bb]$", "")
    end
    return {
        title = title ~= "" and title or "Unknown title",
        authors = authors ~= "" and authors or "Unknown author",
    }
end

function ReaderContext:readingState()
    local page = math.max(1, tonumber(self:currentPage()) or 1)
    local ok, page_count = pcall(function()
        return self.document:getPageCount()
    end)
    page_count = ok and math.max(page, tonumber(page_count) or page) or page
    local overall_percent = math.min(100, math.max(0, page / math.max(1, page_count) * 100))

    local chapter_start = self:chapterStartPage(page)
    local chapter_end_exclusive = page_count + 1
    for unused_index, tick in ipairs(self:chapterTicks()) do
        if tick > chapter_start then
            chapter_end_exclusive = tick
            break
        end
    end
    local chapter_pages = math.max(1, chapter_end_exclusive - chapter_start)
    local chapter_page = math.min(chapter_pages, math.max(1, page - chapter_start + 1))
    local chapter_percent = math.min(100, math.max(0, chapter_page / chapter_pages * 100))

    local props = self:bookProps()
    return {
        title = props.title,
        authors = props.authors,
        page = page,
        page_count = page_count,
        overall_percent = overall_percent,
        chapter_title = self:chapterTitle(page),
        chapter_page = chapter_page,
        chapter_pages = chapter_pages,
        chapter_percent = chapter_percent,
    }
end

function ReaderContext:chapterTicks()
    if not self.ui.toc then
        return {}
    end
    local ok, ticks = pcall(function()
        return self.ui.toc:getTocTicksFlattened(true)
    end)
    if not ok or type(ticks) ~= "table" then
        return {}
    end
    local normalized = {}
    local seen = {}
    for unused_index, tick in ipairs(ticks) do
        tick = tonumber(tick)
        if tick and tick >= 1 and not seen[tick] then
            seen[tick] = true
            table.insert(normalized, tick)
        end
    end
    table.sort(normalized)
    return normalized
end

function ReaderContext:chapterStartPage(page)
    page = page or self:currentPage()
    local start_page = 1
    for unused_index, tick in ipairs(self:chapterTicks()) do
        if tick > page then
            break
        end
        start_page = tick
    end
    return start_page
end

function ReaderContext:chapterTitle(page)
    if not self.ui.toc then
        return ""
    end
    local ok, title = pcall(function()
        return self.ui.toc:getTocTitleByPage(page)
    end)
    return ok and type(title) == "string" and clean(title) or ""
end

function ReaderContext:textBetween(start_xp, end_xp, invisible)
    if not start_xp or not end_xp then
        return nil, _("无法确定阅读范围")
    end
    local ordered = self.document:compareXPointers(start_xp, end_xp)
    if ordered == nil or ordered < 0 then
        return nil, _("阅读范围无效")
    end
    local text
    if Trapper:isWrapped() then
        local completed
        completed, text = Trapper:dismissableRunInSubprocess(function()
            local ok, extracted = pcall(function()
                return self.document:getTextFromXPointers(start_xp, end_xp)
            end)
            return ok and extracted or nil
        end, invisible and false or _("正在读取 EPUB 文字…轻触可取消"), true)
        if not completed then
            return nil, _("已取消")
        end
    else
        local ok
        ok, text = pcall(function()
            return self.document:getTextFromXPointers(start_xp, end_xp)
        end)
        if not ok then
            text = nil
        end
    end
    if type(text) ~= "string" then
        return nil, _("无法读取这段 EPUB 文字")
    end
    text = clean(text)
    if text == "" then
        return nil, _("这个范围没有可读取的文字")
    end
    return text
end

function ReaderContext:rangeFromPages(name, start_page, end_page, end_xp, invisible)
    local start_xp = self.document:getPageXPointer(math.max(1, start_page))
    end_xp = end_xp or self.document:getPageXPointer(end_page)
    local text, err = self:textBetween(start_xp, end_xp, invisible)
    if not text then
        return nil, err
    end
    return {
        name = name,
        text = text,
        start_page = start_page,
        end_page = end_page,
        start_xp = start_xp,
        end_xp = end_xp,
    }
end

function ReaderContext:currentChapter(invisible)
    local page = self:currentPage()
    local title = self:chapterTitle(page)
    local name = title ~= "" and (title .. _("（读到这里）")) or _("当前章到这里")
    return self:rangeFromPages(name, self:chapterStartPage(page), page, self:currentXPointer(), invisible)
end

function ReaderContext:previousTwoChapters(invisible)
    local page = self:currentPage()
    local current_start = self:chapterStartPage(page)
    local ticks = self:chapterTicks()
    local current_index
    for index, tick in ipairs(ticks) do
        if tick <= current_start then
            current_index = index
        else
            break
        end
    end
    if not current_index or current_index <= 1 then
        return nil, _("当前进度前还没有完整章节")
    end
    local start_index = math.max(1, current_index - 2)
    local start_page = ticks[start_index] or 1
    local end_xp = self.document:getPageXPointer(current_start)
    return self:rangeFromPages(_("前两章"), start_page, current_start, end_xp, invisible)
end

function ReaderContext:readToCurrent(invisible)
    local page = self:currentPage()
    return self:rangeFromPages(_("开头到这里"), 1, page, self:currentXPointer(), invisible)
end

function ReaderContext:finishedChapter(start_page, end_page)
    local title = self:chapterTitle(start_page)
    local name = title ~= "" and title or _("刚读完的章节")
    return self:rangeFromPages(name, start_page, end_page, self.document:getPageXPointer(end_page), true)
end

function ReaderContext:selection(selected_text)
    if type(selected_text) ~= "table" then
        return nil, _("没有有效选中文字")
    end
    local text = clean(selected_text.text)
    if text == "" and selected_text.pos0 and selected_text.pos1 then
        text = self:textBetween(selected_text.pos0, selected_text.pos1)
    end
    if not text or text == "" then
        return nil, _("没有有效选中文字")
    end
    return {
        name = _("选中文字"),
        text = text,
        start_xp = selected_text.pos0,
        end_xp = selected_text.pos1,
    }
end

local function result_text(item)
    return clean(table.concat({
        item.prev_text or "",
        item.matched_word_prefix or "",
        item.matched_text or "",
        item.matched_word_suffix or "",
        item.next_text or "",
    }, " "))
end

function ReaderContext:findMentions(term, current_xp, include_future)
    term = clean(term)
    if term == "" then
        return nil, _("请选择人物、地点或词语")
    end
    local search_message = include_future and _("正在查找全书出现位置…")
        or _("正在查找此前出现的位置…")
    local completed, results = Trapper:dismissableRunInSubprocess(function()
        return self.document:findAllText(term, true, 24, 2000, false)
    end, search_message)
    if not completed then
        return nil, _("已取消")
    end
    if type(results) ~= "table" then
        results = {}
    end

    local eligible = {}
    for unused_index, item in ipairs(results) do
        if type(item) == "table" and item.start then
            local comparison
            if not include_future then
                local ok_compare
                ok_compare, comparison = pcall(function()
                    return self.document:compareXPointers(item.start, current_xp)
                end)
                if not ok_compare then
                    comparison = nil
                end
            end
            if include_future or (comparison and comparison >= 0) then
                table.insert(eligible, item)
            end
        end
    end
    if #eligible == 0 then
        return nil, include_future and _("全书没有找到相关文字")
            or _("在当前位置之前没有找到相关文字")
    end

    -- Preserve introductions, sample the whole read history, and favour recent
    -- events. This keeps long novels from being represented only by early hits.
    local selected_indices = {}
    local selected_lookup = {}
    local function select_index(index)
        index = math.max(1, math.min(#eligible, math.floor(index + 0.5)))
        if not selected_lookup[index] then
            selected_lookup[index] = true
            table.insert(selected_indices, index)
        end
    end
    for index = 1, math.min(4, #eligible) do
        select_index(index)
    end
    for slot = 1, 12 do
        select_index(1 + (#eligible - 1) * slot / 13)
    end
    for index = math.max(1, #eligible - 11), #eligible do
        select_index(index)
    end
    for index = #eligible, 1, -1 do
        if #selected_indices >= 28 then
            break
        end
        select_index(index)
    end
    table.sort(selected_indices)

    local snippets = {}
    for unused_index, result_index in ipairs(selected_indices) do
        local item = eligible[result_index]
        if item then
            local page = self.document:getPageFromXPointer(item.start)
            local title = self:chapterTitle(page)
            local prefix
            if title ~= "" then
                prefix = "【" .. title .. "】"
            elseif _:isChinese() then
                prefix = "【第 " .. tostring(page) .. " 页】"
            else
                prefix = "[Page " .. tostring(page) .. "]"
            end
            local occurrence = _:isChinese()
                and ("出现 " .. tostring(result_index) .. "/" .. tostring(#eligible))
                or ("Occurrence " .. tostring(result_index) .. "/" .. tostring(#eligible))
            table.insert(snippets, prefix .. " [" .. occurrence .. "] " .. result_text(item))
        end
    end
    return table.concat(snippets, "\n")
end

function ReaderContext:sampleReadToCurrent(max_bytes, max_samples, final_page, final_xp, invisible)
    max_bytes = max_bytes or 12000
    max_samples = max_samples or 6
    local current_page = math.max(1, tonumber(final_page or self:currentPage()) or 1)
    local current_xp = final_page and final_xp or self:currentXPointer()
    local window_pages = 12
    local last_start = math.max(1, current_page - window_pages + 1)

    local completed, samples = Trapper:dismissableRunInSubprocess(function()
        local parts = {}
        local used_starts = {}
        for index = 0, max_samples - 1 do
            local ratio = max_samples == 1 and 1 or index / (max_samples - 1)
            local start_page = math.floor(1 + ratio * (last_start - 1) + 0.5)
            if not used_starts[start_page] then
                used_starts[start_page] = true
                local end_page = math.min(current_page, start_page + window_pages - 1)
                local start_xp = self.document:getPageXPointer(start_page)
                local end_xp
                if end_page >= current_page then
                    end_xp = current_xp
                    if not end_xp then
                        local ok_end
                        ok_end, end_xp = pcall(function()
                            return self.document:getPageXPointer(end_page + 1)
                        end)
                        if not ok_end or not end_xp then
                            end_xp = self.document:getPageXPointer(end_page)
                        end
                    end
                else
                    end_xp = self.document:getPageXPointer(end_page + 1)
                end
                local ok, excerpt = pcall(function()
                    return self.document:getTextFromXPointers(start_xp, end_xp)
                end)
                excerpt = ok and clean(excerpt) or ""
                if excerpt ~= "" then
                    if #excerpt > max_bytes then
                        if end_page >= current_page then
                            excerpt = utf8_tail(excerpt, max_bytes)
                        else
                            excerpt = util.fixUtf8(excerpt:sub(1, max_bytes), "")
                        end
                    end
                    local label = _:isChinese()
                        and ("第 " .. tostring(start_page) .. "–" .. tostring(end_page) .. " 页")
                        or ("Pages " .. tostring(start_page) .. "–" .. tostring(end_page))
                    table.insert(parts, "[" .. label .. "]\n" .. excerpt)
                end
            end
        end
        return table.concat(parts, "\n\n")
    end, invisible and false or _("正在读取 EPUB 文字…轻触可取消"), true)

    if not completed then
        return nil, _("已取消")
    end
    if type(samples) ~= "string" or samples == "" then
        return nil, _("无法读取这段 EPUB 文字")
    end
    return samples
end

function ReaderContext:sampleWholeBook(max_bytes, max_samples, invisible)
    local page_count
    if self.document.getLastLinearPage then
        local ok_linear, last_linear = pcall(function()
            return self.document:getLastLinearPage()
        end)
        if ok_linear then
            page_count = tonumber(last_linear)
        end
    end
    if not page_count then
        local ok_count, count = pcall(function()
            return self.document:getPageCount()
        end)
        if ok_count then
            page_count = tonumber(count)
        end
    end
    if not page_count then
        return nil, _("无法确定阅读范围")
    end
    return self:sampleReadToCurrent(max_bytes, max_samples, page_count, nil, invisible)
end

function ReaderContext:chunks(text, max_bytes, max_chunks)
    max_bytes = max_bytes or 42000
    max_chunks = max_chunks or 6
    if #text <= max_bytes then
        return { text }
    end

    local natural_count = math.ceil(#text / max_bytes)
    local count = math.min(natural_count, max_chunks)
    local chunks = {}
    if natural_count <= max_chunks then
        for start_pos = 1, #text, max_bytes do
            table.insert(chunks, util.fixUtf8(text:sub(start_pos, start_pos + max_bytes - 1), ""))
        end
    else
        local last_start = math.max(1, #text - max_bytes + 1)
        for index = 0, count - 1 do
            local ratio = count == 1 and 0 or index / (count - 1)
            local start_pos = math.floor(1 + ratio * (last_start - 1))
            table.insert(chunks, util.fixUtf8(text:sub(start_pos, start_pos + max_bytes - 1), ""))
        end
    end
    return chunks
end

return ReaderContext
