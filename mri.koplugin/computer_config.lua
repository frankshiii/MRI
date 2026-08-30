-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Frank

local JSON = require("json")
local _ = require("i18n")

local ComputerConfig = {}
ComputerConfig.__index = ComputerConfig

function ComputerConfig:new(path)
    return setmetatable({
        path = path,
        status = "missing",
        error = nil,
    }, self)
end

function ComputerConfig:load()
    local file = io.open(self.path, "rb")
    if not file then
        self.status = "missing"
        self.error = nil
        return {}
    end

    local content = file:read("*all")
    file:close()
    if not content or #content > 65536 then
        self.status = "error"
        self.error = _("电脑配置文件为空或过大")
        return {}
    end
    content = content:gsub("^\239\187\191", "")

    local ok, config = pcall(JSON.decode, content)
    if not ok or type(config) ~= "table" then
        self.status = "error"
        self.error = _("config.json 格式错误")
        return {}
    end
    if config.api_keys ~= nil and type(config.api_keys) ~= "table" then
        self.status = "error"
        self.error = _("api_keys 必须是 JSON 对象")
        return {}
    end
    if config.models ~= nil and type(config.models) ~= "table" then
        self.status = "error"
        self.error = _("models 必须是 JSON 对象")
        return {}
    end
    if config.endpoints ~= nil and type(config.endpoints) ~= "table" then
        self.status = "error"
        self.error = _("endpoints 必须是 JSON 对象")
        return {}
    end

    self.status = "loaded"
    self.error = nil
    return config
end

return ComputerConfig
