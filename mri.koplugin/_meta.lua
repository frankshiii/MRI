-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Frank

local I18N = require("i18n")

return {
    name = "mri",
    fullname = "MRI",
    version = "0.1.0-dev",
    description = I18N:isChinese()
        and "支持回顾、人物地点概念表、MRI 条目和上下文问答的 EPUB 阅读助手。"
        or "EPUB recaps, people, places and concepts, MRI entries, and contextual AI questions.",
}
