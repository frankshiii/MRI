-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Frank

local JSON = require("json")
local _ = require("i18n")
local logger = require("logger")
local Trapper = require("ui/trapper")
local ltn12 = require("ltn12")
local socket = require("socket")
local http = require("socket.http")
local socketutil = require("socketutil")

local ApiClient = {}
ApiClient.__index = ApiClient

function ApiClient:new()
    return setmetatable({}, self)
end

local function copy_table(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = copy_table(value)
        else
            result[key] = value
        end
    end
    return result
end

local function merge(target, extra)
    for key, value in pairs(extra or {}) do
        target[key] = copy_table(value)
    end
    return target
end

local function openai_body(provider, messages, max_tokens, disable_thinking)
    local body = {
        model = provider.model,
        messages = messages,
        max_tokens = max_tokens or 700,
        stream = false,
    }
    if disable_thinking then
        merge(body, provider.thinking_off)
    end
    return body
end

local function anthropic_body(provider, messages, max_tokens)
    local system_parts = {}
    local chat_messages = {}
    for unused_index, message in ipairs(messages) do
        if message.role == "system" then
            table.insert(system_parts, message.content)
        else
            table.insert(chat_messages, {
                role = message.role,
                content = message.content,
            })
        end
    end
    return {
        model = provider.model,
        system = table.concat(system_parts, "\n\n"),
        messages = chat_messages,
        max_tokens = max_tokens or 700,
        stream = false,
    }
end

local function headers_for(provider, encoded_body)
    local headers = {
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
        ["Content-Length"] = tostring(#encoded_body),
    }
    if provider.protocol == "anthropic" then
        headers["anthropic-version"] = "2023-06-01"
        if provider.api_key ~= "" then
            headers["x-api-key"] = provider.api_key
        end
    elseif provider.api_key ~= "" then
        headers["Authorization"] = "Bearer " .. provider.api_key
    end
    return headers
end

local function post_json(provider, body)
    local ok_encode, encoded = pcall(JSON.encode, body)
    if not ok_encode then
        return false, 0, _("无法生成请求：") .. tostring(encoded)
    end

    local sink = {}
    local request = {
        url = provider.endpoint,
        method = "POST",
        headers = headers_for(provider, encoded),
        source = ltn12.source.string(encoded),
        sink = socketutil.table_sink(sink),
    }

    socketutil:set_timeout(30, 120)
    local ok_request, code, response_headers, status = pcall(function()
        return socket.skip(1, http.request(request))
    end)
    socketutil:reset_timeout()

    if not ok_request then
        return false, 0, _("网络请求失败：") .. tostring(code)
    end

    local content = table.concat(sink)
    if response_headers == nil then
        return false, tonumber(code) or 0, _("网络不可用：") .. tostring(status or code or _("未知错误"))
    end
    local numeric_code = tonumber(code) or 0
    if numeric_code < 200 or numeric_code >= 300 then
        return false, numeric_code, content ~= "" and content or tostring(status or code)
    end
    return true, numeric_code, content
end

local function content_to_text(content)
    if type(content) == "string" then
        return content
    end
    if type(content) ~= "table" then
        return nil
    end
    local parts = {}
    for unused_index, item in ipairs(content) do
        if type(item) == "string" then
            table.insert(parts, item)
        elseif type(item) == "table" and type(item.text) == "string" then
            table.insert(parts, item.text)
        end
    end
    return table.concat(parts, "\n")
end

local function decode_answer(provider, content)
    local ok, decoded = pcall(JSON.decode, content)
    if not ok or type(decoded) ~= "table" then
        return nil, _("服务返回了无法解析的数据")
    end
    if decoded.error then
        local message = type(decoded.error) == "table" and decoded.error.message or decoded.error
        return nil, tostring(message or _("AI 服务返回错误"))
    end

    local answer
    if provider.protocol == "anthropic" then
        answer = content_to_text(decoded.content)
    elseif decoded.choices and decoded.choices[1] and decoded.choices[1].message then
        answer = content_to_text(decoded.choices[1].message.content)
    end
    if not answer or answer:match("^%s*$") then
        return nil, _("AI 服务没有返回正文")
    end
    return answer
end

local function supports_retry_without_thinking(provider, code, content)
    if not provider.thinking_off or (code ~= 400 and code ~= 422) then
        return false
    end
    local lower = string.lower(content or "")
    return lower:find("thinking", 1, true)
        or lower:find("reasoning_effort", 1, true)
        or lower:find("enable_thinking", 1, true)
end

function ApiClient:validate(provider)
    if not provider then
        return false, _("未选择 AI 服务")
    end
    if type(provider.endpoint) ~= "string" or not provider.endpoint:match("^https?://") then
        return false, _("接口地址必须以 http:// 或 https:// 开头")
    end
    if type(provider.model) ~= "string" or provider.model:match("^%s*$") then
        return false, _("请先填写模型名称")
    end
    if provider.api_key == "" and provider.id ~= "custom_openai" and provider.id ~= "custom_anthropic" then
        return false, _("请先填写这个服务的 API Key")
    end
    return true
end

function ApiClient:request(provider, messages, options)
    options = options or {}
    local valid, validation_error = self:validate(provider)
    if not valid then
        return nil, validation_error
    end

    local body
    if provider.protocol == "anthropic" then
        body = anthropic_body(provider, messages, options.max_tokens)
    else
        body = openai_body(provider, messages, options.max_tokens, true)
    end

    local trap = options.invisible and false or (options.progress_text or _("AI 正在阅读…轻触可取消"))
    local completed, success, code, content = Trapper:dismissableRunInSubprocess(function()
        return post_json(provider, body)
    end, trap)
    if not completed then
        return nil, _("已取消")
    end

    if not success and supports_retry_without_thinking(provider, code, content) then
        body = openai_body(provider, messages, options.max_tokens, false)
        completed, success, code, content = Trapper:dismissableRunInSubprocess(function()
            return post_json(provider, body)
        end, trap)
        if not completed then
            return nil, _("已取消")
        end
    end

    local transient = code == 0 or code == 408 or code == 409 or code == 429
        or code == 500 or code == 502 or code == 503 or code == 504
    if not success and transient then
        socket.sleep(code == 429 and 3 or 1)
        completed, success, code, content = Trapper:dismissableRunInSubprocess(function()
            return post_json(provider, body)
        end, trap)
        if not completed then
            return nil, _("已取消")
        end
    end

    if not success then
        local ignored_answer, readable_error = decode_answer(provider, content or "")
        logger.warn("MRI request failed, HTTP", code or 0, "provider", provider.id or "unknown")
        if readable_error and readable_error ~= _("服务返回了无法解析的数据") then
            return nil, readable_error
        end
        if code == 0 and type(content) == "string" and content ~= "" then
            return nil, content
        end
        return nil, _("请求失败（HTTP ") .. tostring(code or 0) .. _("）")
    end
    return decode_answer(provider, content)
end

return ApiClient
