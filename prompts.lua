-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Frank

local I18N = require("i18n")
local Prompts = {}
local chinese = I18N:isChinese()

local base_system = chinese and [[你是电子书阅读助手。通常只能依据用户提供的书中文字回答；资料表任务明确允许使用你对该书的可靠知识时，可以按该任务的限制补充。资料不足时直接说”当前文字不足以判断”。
用一个读过很多书的人的口吻说话——像资深书评人跟朋友聊一本书，真诚、自然、有自己的判断。不要排比，不要连续堆叠同义形容词（比如”神情木然、内心痛苦、饱受煎熬”这种三连），用正常说话的方式把意思讲清楚。可以有洞察，但不要抒情。尽量少用破折号，能用普通句子说清楚时就不用破折号。
提到书中内容时直接讲内容，不标注章节名、章节号、页码或阅读进度。默认自然转述，不必逐字引用；只有原句措辞本身对分析有用时才使用简短直接引文。
遵守奥威尔式的清楚写作原则。避免印刷品里已经用滥的成语、隐喻和其他比喻。能用短词就不用长词；能删掉的词就删掉。优先使用主动语态。能用日常语言就不用外来语、科学术语或行话。如果这些规则会让一句话变得生硬、失真或难懂，以清楚、自然和诚实为先。
默认使用简体中文，先给结论。普通回答使用短段落，每段只讲一个中心意思，段落之间留一个空行；具体篇幅和段落数量服从回答长度设置。列表有两个层级：主要观点或主项以“- ”开头；只有主项下确实需要拆开的补充信息才以“• ”开头。“-”的层级高于“•”。能用一个短段落或一条“-”说清时，不使用“•”。普通回答中每组最多三个主项，每条一至三句，不再继续嵌套。人物表、地点表、概念表不用数字编号，主项之间留一个空行。
只输出纯文本。禁止使用 Markdown 加粗、井号标题、代码围栏、链接语法或横向表格；允许作为纯文本层级标记的“-”和“•”。
保留有助于理解人物、情节和主题的重要细节，不写空泛引言。]] or [[You are an ebook reading assistant. Normally answer only from the supplied book text. A reference-list task may explicitly allow reliable prior knowledge of the named book; use it only within that task's limits.
Say when the supplied text is insufficient.
Write like a well-read friend discussing the book — a senior reviewer or seasoned author, sincere and insightful. Avoid parallel structures and stacked synonymous adjectives (e.g. “stoic, tormented, anguished” in sequence); just say what you mean in natural language. Observations are welcome; purple prose is not. Use dashes sparingly; prefer ordinary sentences when they express the idea clearly.
When referring to the book, discuss the content directly without naming a chapter, chapter number, page, or reading-progress position. Paraphrase naturally by default. Use a short direct quotation only when its exact wording matters to the analysis.
Follow Orwell-style principles of clear prose. Avoid worn-out idioms, metaphors, and other figures of speech. Prefer a short word to a long one, and remove every word that adds nothing. Prefer the active voice. Use everyday language instead of foreign phrases, scientific terms, or jargon. Break any of these rules when following it would make a sentence harsh, misleading, or difficult to understand; clarity, naturalness, and honesty come first.
Answer in English and lead with the conclusion. Use short paragraphs, each with one central idea, and leave one blank line between paragraphs; let the response-length setting control detail and paragraph count. Lists have two levels: begin each main point or entry with “- ”; use “• ” only for supporting details that genuinely need to be separated beneath a main point. “-” is the higher level. If a short paragraph or one “-” line is enough, do not use “•”. Ordinary answers may use at most three main points in one group, each one to three sentences, with no further nesting. People, places, and concept lists must not use numbered entries and should leave one blank line between main entries.
Output plain text only. Never use Markdown emphasis, hash headings, code fences, link syntax, or horizontal tables. The plain-text hierarchy markers “-” and “•” are allowed.
Keep details that help explain characters, events, and themes. Avoid generic introductions.]]

local function length_policy(response_length)
    response_length = response_length or "medium"
    if chinese then
        if response_length == "short" then
            return "回答长度设为短。普通回答约 150—300 个汉字，尽量用一至两段；回顾或简介约 250—450 个汉字。资料表保留必要条目，每项只写最重要的一句话。"
        elseif response_length == "long" then
            return "回答长度设为长。普通回答约 700—1200 个汉字，回顾或简介约 900—1500 个汉字，可以使用三至五个紧凑段落。资料表的重要条目可写两至四句。不要为凑字数重复。"
        end
        return "回答长度设为中。普通回答约 350—700 个汉字，回顾或简介约 500—900 个汉字，最多三个紧凑段落。资料表每项通常写一至两句。"
    end
    if response_length == "short" then
        return "Response length is short. Keep ordinary answers around 100–180 words and recaps or overviews around 180–300 words, usually in one or two paragraphs. Keep each reference-list entry to its single most useful sentence."
    elseif response_length == "long" then
        return "Response length is long. Ordinary answers may use about 500–800 words and recaps or overviews about 650–1000 words in three to five compact paragraphs. Important reference-list entries may use two to four sentences. Never repeat yourself merely to add length."
    end
    return "Response length is medium. Keep ordinary answers around 250–450 words and recaps or overviews around 350–600 words in at most three compact paragraphs. Reference-list entries usually use one or two sentences."
end

function Prompts.system(allow_spoilers, response_length)
    if chinese then
        local policy = allow_spoilers
            and "剧透已开启。可以使用请求中提供的当前位置之后原文，明确讲述未来情节、结局和人物命运。"
            or "剧透已关闭。当前位置是严格边界；完整讲述边界以前已经发生的事，禁止透露边界以后内容。"
        return base_system .. "\n" .. policy .. "\n" .. length_policy(response_length)
    end
    local policy = allow_spoilers
        and "Spoilers are enabled. You may use supplied text after the current position and discuss future events, endings, and character outcomes explicitly."
        or "Spoilers are disabled. The current position is a strict boundary: fully discuss prior events and reveal nothing after it."
    return base_system .. "\n" .. policy .. "\n" .. length_policy(response_length)
end

local function wrap(label, text)
    return "\n\n<" .. label .. ">\n" .. (text or "") .. "\n</" .. label .. ">"
end

function Prompts.reading_state(state, allow_spoilers)
    state = state or {}
    local chapter_title = state.chapter_title
    if type(chapter_title) ~= "string" or chapter_title == "" then
        chapter_title = chinese and "未命名章节" or "Untitled chapter"
    end
    if chinese then
        local boundary = allow_spoilers
            and "剧透已开启；请求可能包含当前位置之后的原文。"
            or "剧透已关闭；可完整讲述当前位置以前的内容，禁止透露之后内容。"
        return string.format([[<当前阅读状态>
书名：%s
作者：%s
全书进度：%.1f%%（第 %d/%d 页）
当前章节：%s
章节进度：%.1f%%（本章第 %d/%d 页）
剧透状态：%s
</当前阅读状态>]],
            state.title or "未知书名", state.authors or "未知作者",
            state.overall_percent or 0, state.page or 1, state.page_count or 1,
            chapter_title, state.chapter_percent or 0,
            state.chapter_page or 1, state.chapter_pages or 1, boundary)
    end
    local boundary = allow_spoilers
        and "Spoilers enabled; supplied text may extend beyond the current position."
        or "Spoilers disabled; fully discuss prior text and reveal nothing after the current position."
    return string.format([[<current_reading_state>
Book: %s
Author: %s
Overall progress: %.1f%% (page %d/%d)
Current chapter: %s
Chapter progress: %.1f%% (chapter page %d/%d)
Spoiler status: %s
</current_reading_state>]],
        state.title or "Unknown title", state.authors or "Unknown author",
        state.overall_percent or 0, state.page or 1, state.page_count or 1,
        chapter_title, state.chapter_percent or 0,
        state.chapter_page or 1, state.chapter_pages or 1, boundary)
end

function Prompts.recap(scope_name, context)
    if chinese then
        return "请回顾“" .. scope_name .. "”。概括关键事件、人物变化、重要线索和仍未解决的问题。篇幅服从回答长度设置，最多 8 个以“- ”开头的主项；只有某个主项确实需要拆开时才在其下使用“• ”。不要使用数字编号。"
            .. wrap("阅读范围内原文", context)
    end
    return "Recap “" .. scope_name .. "”. Cover key events, character changes, important clues, and unresolved questions. Use up to eight main points beginning with “- ”. Use “• ” only for supporting detail that genuinely needs a second level. Do not use numbered entries."
        .. wrap("book text within reading boundary", context)
end

function Prompts.chunk_recap(context)
    if chinese then
        return "这是较长阅读范围的一段。提取对最终回顾最重要的事件、人物变化和线索，约 200 个汉字。"
            .. wrap("原文片段", context)
    end
    return "Extract the events, character changes, and clues from this segment that matter most to a final recap."
        .. wrap("book segment", context)
end

function Prompts.synthesise_recap(scope_name, summaries)
    if chinese then
        return "请把下列分段摘要合成为“" .. scope_name .. "”的无剧透回顾。篇幅服从回答长度设置，最多 8 个以“- ”开头的主项，不重复；只在确实需要第二层时使用“• ”，不要使用数字编号。"
            .. wrap("分段摘要", summaries)
    end
    return "Combine these segment summaries into a spoiler-safe recap of “" .. scope_name .. "”. Use up to eight non-repetitive main points beginning with “- ”. Use “• ” only when a second level is genuinely useful, and do not use numbered entries."
        .. wrap("segment summaries", summaries)
end

function Prompts.mri(selection, context, quick_view)
    local quick_instruction = ""
    if quick_view then
        if chinese then
            quick_instruction = [[详细解释前先输出三行速览，不写标题。每行以“- ”开头，只写一句短话。
人物使用“背景、关系、作用”；地点使用“性质、关联、作用”；概念使用“含义、关联、主题”；句子或段落使用“直意、语境、作用”。只选择与当前类型对应的一组三行，格式为“- 名称：内容”。三行后空一行，再开始详细解释。
]]
        else
            quick_instruction = [[Before the detailed explanation, output exactly three quick-view lines with no heading. Begin every line with “- ” and use one short sentence per line.
For a person use “Background, Relationships, Role”; for a place use “Nature, Connections, Role”; for a concept use “Meaning, Connections, Theme”; for a passage use “Direct meaning, Context, Purpose”. Choose only the matching set and format each line as “- Label: content”. Leave one blank line before the detailed explanation.
]]
        end
    end
    if chinese then
        return quick_instruction .. [[先判断选中内容属于人物、地点、概念/术语，还是句子/段落，然后直接采用最合适的说明方式，不单独输出分类过程。
人物：说明身份、关系、作用、关键变化和当前状态。
地点：说明性质、相关人物、关键事件和叙事作用。
概念/术语：说明语境含义、反复出现的用法、相关主题及值得注意的变化。
句子/段落：解释表层意思、上下文、隐含意义、写作手法及其作用。
篇幅服从回答长度设置，使用紧凑纯文本。需要列表时，主要观点以“- ”开头；只有主要观点下确实需要拆开的内容才使用“• ”。人物、地点和概念资料不用数字编号，以空行分隔主项。]]
            .. wrap("选中内容", selection) .. wrap("相关原文", context)
    end
    return quick_instruction .. [[First infer whether the selection is a person, place, concept or term, or a sentence or passage, then use the most useful response structure without announcing the classification process.
For a person, cover identity, relationships, role, changes, and current status. For a place, cover its nature, related people, events, and narrative role. For a concept, explain its contextual meaning, recurring uses, themes, and changes. For a passage, explain its direct meaning, context, implications, technique, and purpose. Keep the answer compact. When a list helps, begin main points with “- ” and use “• ” only for supporting details that genuinely need separation. Do not number people, place, or concept entries; separate main entries with a blank line.]]
        .. wrap("selected content", selection) .. wrap("relevant book text", context)
end

function Prompts.question(question, context)
    if chinese then
        return "问题：" .. question .. "\n根据问题复杂度回答，并服从回答长度设置。"
            .. wrap("用户选定的阅读上下文", context)
    end
    return "Question: " .. question .. "\nAnswer with enough detail for the question; expand when analysis is useful."
        .. wrap("user-selected reading context", context)
end

function Prompts.directory(kind, text_samples, allow_spoilers, use_book_knowledge, expanded_samples)
    if chinese then
        local target = kind == "people" and "人物" or (kind == "places" and "地点" or "概念")
        local knowledge_instruction
        if use_book_knowledge and not expanded_samples then
            knowledge_instruction = [[这次使用自动混合模式。先根据阅读状态中的书名和作者判断你是否可靠地熟悉这部作品。熟悉时，可以用已有知识补全候选项、别名和关联，但书内样本中的译名优先，关闭剧透时不得使用当前位置之后的信息。若无法可靠识别作品，或这些少量样本不足以生成可信资料表，只输出 <need_more_context>，不要猜测，也不要附加其他文字。]]
        elseif use_book_knowledge then
            knowledge_instruction = [[这次使用自动混合模式，并已提供扩大后的书内样本。可以用你对该书的可靠知识帮助识别候选项和别名；书内样本中的译名优先，关闭剧透时不得使用当前位置之后的信息。无法确认的内容不要写。]]
        else
            knowledge_instruction = [[这次使用严格书内模式。只能依据提供的书中文字，不得使用对这部作品的外部记忆补充事实。]]
        end
        local format
        if kind == "people" then
            format = "每个人以“- 姓名（别名）”开头，不加数字编号。背景、关系和作用或状态能在主项中说清时直接写完；只有确实需要拆开时，才在该人物下用最多三个“• ”短条。"
        elseif kind == "places" then
            format = "每个地点以“- 名称（别名）”开头，不加数字编号。性质、关联人物或事件和叙事作用能在主项中说清时直接写完；只有确实需要拆开时，才在该地点下用最多三个“• ”短条。"
        else
            format = "忽略虚词、常用词和普通叙事词，挑出约 8—12 个反复出现且最有解释价值的概念、术语、组织、意象或母题。每项以“- 名称”开头，不加数字编号。语境含义、相关人物或事件和主题作用能在主项中说清时直接写完；只有确实需要拆开时，才在该概念下用最多三个“• ”短条。合并近义词。这里是代表性高频概念，不声称精确词频。"
        end
        local scope = allow_spoilers and "全书" or "截至当前位置"
        return knowledge_instruction .. "\n根据下列原文片段，生成“" .. scope .. target .. "表”。去重并合并别名，按重要性排序。"
            .. format .. " 不要在开头重复表名、阅读范围或生成说明。主项之间留一个空行。“-”是主层级，“•”是次层级；没有次层级就不用“•”。不要使用横向表格。主要项目可以写得详细；一笔带过的项目放在“其他”中。严禁补充阅读范围以后的信息。"
            .. wrap("已读原文片段", text_samples)
    end
    local target = kind == "people" and "people list" or (kind == "places" and "places list" or "concept list")
    local knowledge_instruction
    if use_book_knowledge and not expanded_samples then
        knowledge_instruction = "Use automatic hybrid mode. First decide whether you reliably recognize the work from its title and author in the reading state. If you do, prior knowledge may supply candidates, aliases, and connections; prefer names used in the excerpts and reveal nothing beyond the reading position when spoilers are off. If you cannot reliably identify the work or the small sample is insufficient, output only <need_more_context> and do not guess. "
    elseif use_book_knowledge then
        knowledge_instruction = "Use automatic hybrid mode with the expanded excerpts. Reliable prior knowledge may help identify candidates and aliases; prefer names used in the excerpts, respect the spoiler boundary, and omit anything uncertain. "
    else
        knowledge_instruction = "Use strict book-text mode. Use only the supplied excerpts and do not add facts from prior knowledge of the work. "
    end
    local format
    if kind == "people" then
        format = "Begin each person with “- Name (aliases)”, without a number. Keep background, relationships, and role or status on the main entry when that is clear enough; only when separation is genuinely useful, add up to three supporting “• ” lines."
    elseif kind == "places" then
        format = "Begin each place with “- Name (aliases)”, without a number. Keep its nature, related people or events, and narrative role on the main entry when that is clear enough; only when separation is genuinely useful, add up to three supporting “• ” lines."
    else
        format = "Ignore function words and ordinary vocabulary. Select about 8–12 recurring concepts, terms, organisations, images, or motifs with the most explanatory value. Begin each concept with “- Name”, without a number. Keep contextual meaning, related people or events, and thematic role on the main entry when that is clear enough; only when separation is genuinely useful, add up to three supporting “• ” lines. Merge near-synonyms and describe these as representative recurring concepts, not exact word frequencies."
    end
    local scope = allow_spoilers and "the whole book" or "the text read so far"
    return knowledge_instruction .. "Create a " .. target .. " for " .. scope .. ". Merge aliases and duplicates and sort by importance. "
        .. format .. " Do not repeat the list title, reading range, or generation notes at the beginning. Leave one blank line between main entries. “-” is the main level and “•” the supporting level; omit “•” when no second level is needed. Do not use horizontal tables. Give more detail to major entries and use a compact Other section for minor ones. Do not add information beyond the supplied reading boundary."
        .. wrap("book excerpts read so far", text_samples)
end

function Prompts.directory_bundle(text_samples, allow_spoilers, use_book_knowledge)
    if chinese then
        local scope = allow_spoilers and "全书" or "截至当前位置"
        local knowledge_instruction = use_book_knowledge
            and "这是自动混合资料任务。可以用你对阅读状态中这本书的可靠知识补全候选项和别名，书内样本中的译名优先；关闭剧透时不得使用当前位置之后的信息，无法确认的内容不要写。\n"
            or "这是严格书内资料任务。只能依据提供的书中文字，不得用外部记忆补充事实。\n"
        return knowledge_instruction .. [[这是后台资料缓存任务。一次生成三张彼此独立的资料表，直接写内容，不要写引言、结语或生成说明。
必须严格使用下面六个英文标签，每个标签单独占一行，不得改名，不得放进代码围栏：
<people>
人物表内容
</people>
<places>
地点表内容
</places>
<concepts>
概念表内容
</concepts>
人物表：选出最重要的人物，合并别名。每项以“- 姓名”开头，不加数字编号。内容能在主项中说清时直接写完；只有确实需要拆开时，才在该人物下用最多三个“• ”短条说明身份、主要关系、关键选择、剧情作用和当前状态。
地点表：选出重要地点，合并别名。每项以“- 名称”开头，不加数字编号。内容能在主项中说清时直接写完；只有确实需要拆开时，才在该地点下用最多三个“• ”短条说明性质、相关人物、关键事件和叙事作用。
概念表：忽略普通词汇，选出 8—12 个有解释价值的概念、术语、组织、意象或母题，合并近义项。每项以“- 名称”开头，不加数字编号。内容能在主项中说清时直接写完；只有确实需要拆开时，才在该概念下用最多三个“• ”短条说明语境含义、相关人物或事件及主题作用。
三张表都只覆盖]] .. scope .. [[，并服从回答长度设置对每项详略的要求。不要重复表名、阅读范围或生成说明。主项之间留一个空行。“-”是主层级，“•”是次层级；没有次层级就不用“•”。不要使用横向表格。]]
            .. wrap("已读原文片段", text_samples)
    end
    local scope = allow_spoilers and "the whole book" or "the current reading boundary"
    local knowledge_instruction = use_book_knowledge
        and "This is an automatic hybrid reference task. Reliable prior knowledge of the named book may supply candidates and aliases; prefer names in the excerpts, respect the spoiler boundary, and omit uncertain details.\n"
        or "This is a strict book-text reference task. Use only the supplied excerpts and add no facts from prior knowledge.\n"
    return knowledge_instruction .. [[This is a background reference-cache task. Generate three independent lists in one response, with no introduction, conclusion, or explanation of the process.
Use exactly these six lowercase English tags, each on its own line. Never rename them or put them in a code fence:
<people>
people-list content
</people>
<places>
places-list content
</places>
<concepts>
concept-list content
</concepts>
People: select the important characters and merge aliases. Begin each entry with “- Name”, without a number. Keep the content on the main entry when that is clear enough; only when separation is genuinely useful, add up to three supporting “• ” lines for identity, key relationships, consequential choices, plot role, and current status.
Places: select important locations and merge aliases. Begin each entry with “- Name”, without a number. Keep the content on the main entry when that is clear enough; only when separation is genuinely useful, add up to three supporting “• ” lines for nature, related people, important events, and narrative role.
Concepts: skip ordinary vocabulary and select 8–12 explanatory concepts, terms, organisations, images, or motifs, merging near-duplicates. Begin each entry with “- Name”, without a number. Keep the content on the main entry when that is clear enough; only when separation is genuinely useful, add up to three supporting “• ” lines for contextual meaning, related people or events, and thematic role.
Keep every list within ]] .. scope .. [[ and follow the response-length setting when deciding the detail in each entry. Do not repeat a list title, reading range, or generation notes. Leave one blank line between main entries. “-” is the main level and “•” the supporting level; omit “•” when no second level is needed. Do not use horizontal tables.]]
        .. wrap("book excerpts read so far", text_samples)
end

function Prompts.book_intro(context, allow_spoilers)
    if chinese then
        local instruction = allow_spoilers
            and "剧透已开启。写一份完整的全书简介，涵盖类型与背景、故事主线、主要人物弧线、结构、核心主题、写作特色和结局的意义。篇幅服从回答长度设置，内容紧凑。"
            or "剧透已关闭。根据目前提供的文字写一份无剧透全书导读，介绍类型与背景、开篇设定、核心人物、可能关注的主题和写作特色；不要猜测或透露未读情节。篇幅服从回答长度设置，内容紧凑。"
        return instruction .. wrap("用于简介的原文样本", context)
    end
    local instruction = allow_spoilers
        and "Spoilers are enabled. Write a complete book overview covering genre and setting, main plot, principal character arcs, structure, themes, style, and the meaning of the ending. Keep it compact."
        or "Spoilers are disabled. Using only the supplied text, write a spoiler-free guide covering genre and setting, opening premise, central characters, themes worth watching, and style. Do not guess or reveal unread events."
    return instruction .. wrap("book excerpts for the overview", context)
end

return Prompts
