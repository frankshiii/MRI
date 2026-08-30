-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Frank

local _ = require("i18n")
local Providers = {}

Providers.order = {
    "openai",
    "anthropic",
    "gemini",
    "qwen",
    "deepseek",
    "kimi",
    "custom_openai",
    "custom_anthropic",
}

Providers.presets = {
    openai = {
        name = "OpenAI",
        protocol = "openai",
        endpoint = "https://api.openai.com/v1/chat/completions",
        model = "gpt-4.1-mini",
    },
    anthropic = {
        name = "Anthropic",
        protocol = "anthropic",
        endpoint = "https://api.anthropic.com/v1/messages",
        model = "claude-haiku-4-5",
    },
    gemini = {
        name = "Gemini",
        protocol = "openai",
        endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        model = "gemini-2.5-flash-lite",
        thinking_off = { reasoning_effort = "none" },
    },
    qwen = {
        name = "Qwen / 千问",
        protocol = "openai",
        endpoint = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
        model = "qwen-plus",
        thinking_off = { enable_thinking = false },
    },
    deepseek = {
        name = "DeepSeek",
        protocol = "openai",
        endpoint = "https://api.deepseek.com/chat/completions",
        model = "deepseek-v4-flash",
        thinking_off = { thinking = { type = "disabled" } },
    },
    kimi = {
        name = "Kimi",
        protocol = "openai",
        endpoint = "https://api.moonshot.cn/v1/chat/completions",
        model = "kimi-k2.5",
        thinking_off = { thinking = { type = "disabled" } },
    },
    custom_openai = {
        name = "自定义 OpenAI 兼容",
        protocol = "openai",
        endpoint = "",
        model = "",
    },
    custom_anthropic = {
        name = "自定义 Anthropic 兼容",
        protocol = "anthropic",
        endpoint = "",
        model = "",
    },
}

local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = clone(item)
    end
    return result
end

local function external_value(config, group, id)
    local values = config and config[group]
    local value = type(values) == "table" and values[id] or nil
    if type(value) == "string" and not value:match("^%s*$") then
        return value
    end
    return nil
end

function Providers:get(id, settings, computer_config)
    local preset = self.presets[id]
    if not preset then
        return nil
    end

    local provider = clone(preset)
    provider.id = id
    provider.endpoint = settings:readSetting("provider_" .. id .. "_endpoint", provider.endpoint)
    provider.model = settings:readSetting("provider_" .. id .. "_model", provider.model)
    provider.api_key = settings:readSetting("provider_" .. id .. "_api_key", "")
    provider.endpoint = external_value(computer_config, "endpoints", id) or provider.endpoint
    provider.model = external_value(computer_config, "models", id) or provider.model
    provider.api_key = external_value(computer_config, "api_keys", id) or provider.api_key
    return provider
end

function Providers:name(id)
    local provider = self.presets[id]
    return provider and _(provider.name) or id
end

return Providers
