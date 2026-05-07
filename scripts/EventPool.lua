-- ============================================================================
-- EventPool.lua - 集中事件配置 + 查询模块
-- 对标 Godot 版 event_pool.gd / event_pool.json，将散落在各模块的事件数据
-- 统一到一个文件，提供类型安全的查询 API。
-- ============================================================================

local M = {}

-- ============================================================================
-- §1  事件类型定义
-- ============================================================================

--- 可随机生成的事件类型（翻牌时 randomEvent 的候选）
M.EVENT_TYPES = { "safe", "monster", "trap", "reward", "plot", "clue" }

--- 兼容旧代码的完整类型列表（含特殊地点/特殊事件）
M.ALL_TYPES = {
    "safe", "home", "landmark", "shop",
    "monster", "trap", "reward", "plot", "clue",
    "photo", "rift",
}

-- ============================================================================
-- §2  地点定义
-- ============================================================================

--- 地点信息 { icon, label }
M.LOCATION_INFO = {
    -- 特殊地点
    home        = { icon = "🏠", label = "家"      },
    -- 商店地点
    convenience = { icon = "🏪", label = "便利店"  },
    -- 地标地点（有祛邪光环）
    church      = { icon = "⛪", label = "教堂"    },
    police      = { icon = "🚔", label = "警察局"  },
    -- 普通地点
    company     = { icon = "🏢", label = "公司"    },
    school      = { icon = "🏫", label = "学校"    },
    park        = { icon = "🌳", label = "公园"    },
    alley       = { icon = "🌙", label = "小巷"    },
    station     = { icon = "🚉", label = "车站"    },
    hospital    = { icon = "🏥", label = "医院"    },
    library     = { icon = "📚", label = "图书馆"  },
    bank        = { icon = "🏦", label = "银行"    },
    cemetery    = { icon = "🪦", label = "墓地"    },
    gym         = { icon = "🏋️", label = "健身房"  },
}

--- 普通地点（棋盘随机填充用）
M.REGULAR_LOCATIONS = {
    "company", "school", "park", "alley", "station",
    "hospital", "library", "bank", "cemetery", "gym",
}

--- 地标地点（固定出现，有光环保护效果）
M.LANDMARK_LOCATIONS = { "church", "police" }

-- ============================================================================
-- §3  事件权重
-- ============================================================================

--- 基础事件权重 (array of {type, weight})
M.BASE_EVENT_WEIGHTS = {
    { "safe",    30 },
    { "monster", 20 },
    { "trap",    15 },
    { "reward",  15 },
    { "plot",    10 },
    { "clue",    10 },
}

--- 地点对基础权重的偏移值
--- 正值增加该类型概率，负值降低
M.LOCATION_WEIGHT_OFFSET = {
    cemetery = { monster = 10, trap = 3 },
    alley    = { monster = 3,  trap = 5 },
    gym      = { reward = 5, safe = 3 },
    hospital = { reward = 3, safe = 2 },
    park     = { safe = 5 },
    school   = { clue = 3 },
    station  = { trap = 3 },
    market   = { reward = 2 },
    company  = {},
    police   = { safe = 5 },
}

-- ============================================================================
-- §4  陷阱子类型
-- ============================================================================

--- 陷阱子类型权重 (array of {subtype, weight})
M.TRAP_SUBTYPE_WEIGHTS = {
    { "sanity",   30 },
    { "money",    30 },
    { "film",     20 },
    { "teleport", 20 },
}

--- 陷阱子类型信息（Toast 中覆盖默认 trap 图标）
M.TRAP_SUBTYPE_INFO = {
    sanity   = { icon = "👁️",  label = "阴气侵蚀" },
    money    = { icon = "💸", label = "财物散失" },
    film     = { icon = "📷", label = "灵雾曝光" },
    teleport = { icon = "🌀", label = "空间错位" },
}

--- 陷阱子类型效果
M.TRAP_SUBTYPE_EFFECTS = {
    sanity   = { { "san", -1 } },
    money    = { { "money", -10 } },
    film     = { { "film", -1 } },
    teleport = {},   -- 无属性效果，触发传送逻辑
}

--- 陷阱子类型文本模板（覆盖通用 TEMPLATES.trap）
--- 格式: { title = "标题", desc = "描述" }
M.TRAP_SUBTYPE_TEMPLATES = {
    sanity = {
        { title = "阴气侵蚀", desc = "一股寒意从地面渗入脚底，直冲脑门。周围的空气变得凝重，理智在无声中消磨。" },
        { title = "低语缠绕", desc = "耳边响起断断续续的低语，内容听不清楚。你的思维开始变得混乱。" },
        { title = "幻象涌动", desc = "视野边缘浮现模糊的影像，分不清是真实还是幻觉。你努力保持清醒。" },
    },
    money = {
        { title = "财物散失", desc = "口袋突然变轻了——零钱从破洞滑落，怎么也捡不回来。" },
        { title = "无形窃取", desc = "一转眼，钱包里的钞票少了几张。你确信没有人靠近过。" },
        { title = "诅咒流失", desc = "硬币在手中变得灼热，你不得不松手。它们落地后消失不见。" },
    },
    film = {
        { title = "灵雾曝光", desc = "一团幽蓝色的雾气突然涌来，相机发出咔嗒声——胶卷被意外曝光了。" },
        { title = "闪光干扰", desc = "空气中闪过一道强光，相机自动触发了快门。一卷珍贵的胶卷报废了。" },
        { title = "异光侵蚀", desc = "从墙缝渗出的异样光芒照射到你的相机上，胶卷上留下了无法冲洗的痕迹。" },
    },
    teleport = {
        { title = "空间错位", desc = "脚下的地面突然扭曲，你的身体被一股力量拉扯到了别处！" },
        { title = "维度跳跃", desc = "眨眼之间，周围的景色全变了。你不知道自己被传送到了哪里。" },
        { title = "瞬间位移", desc = "一阵眩晕过后，你发现自己站在一个完全不同的地方。" },
    },
}

-- ============================================================================
-- §5  事件效果
-- ============================================================================

--- 基础事件效果 { { resourceKey, delta }, ... }
M.CARD_EFFECTS = {
    safe     = { { "san", 1 } },
    landmark = {},
    shop     = {},                           -- 商店由 ShopPopup 处理
    monster  = { { "san", -2 }, { "health", -1 } },
    trap     = {},                           -- 陷阱效果取决于子类型
    reward   = { { "money", 15 }, { "film", 1 } },
    plot     = { { "inspiration", 1 } },
    clue     = { { "film", 1 } },
    photo    = {},                           -- 照片事件无直接效果
    rift     = {},                           -- 裂隙事件走 confirm 流程
}

--- 安全格按地点场景的差异化奖励
--- 不在表中的地点回落到 CARD_EFFECTS.safe 默认值 (+1 san)
M.SAFE_LOCATION_EFFECTS = {
    park      = { { "health", 1 } },                -- 公园: 散步恢复体力
    gym       = { { "health", 1 } },                -- 健身房: 锻炼恢复体力
    hospital  = { { "health", 1 } },                -- 医院: 治疗恢复体力
    library   = { { "inspiration", 1 } },           -- 图书馆: 阅读获得灵感
    school    = { { "inspiration", 1 } },           -- 学校: 学习获得灵感
    church    = { { "san", 2 } },                   -- 教堂: 安宁恢复更多理智
    police    = { { "san", 1 }, { "health", 1 } },  -- 警察局: 安全感 + 休整
    bank      = { { "money", 8 } },                 -- 银行: 取点钱
    -- 默认 (home/convenience/company/station/alley/cemetery): 走 CARD_EFFECTS.safe → +1 san
}

--- 获取 safe 格的效果 (按地点分化)
---@param location string|nil
---@return table effects
function M.getSafeEffects(location)
    if location and M.SAFE_LOCATION_EFFECTS[location] then
        return M.SAFE_LOCATION_EFFECTS[location]
    end
    return M.CARD_EFFECTS.safe
end

--- 怪物效果（动态，基于灵感值缩放伤害）
--- san -(2+extra), health -1
--- extra = min(3, max(0, floor((inspiration-10)/15)))
---@param inspiration number 当前灵感值
---@return table effects { { resKey, delta }, ... }
function M.getMonsterEffects(inspiration)
    local extra = math.min(3, math.max(0, math.floor((inspiration - 10) / 15)))
    return {
        { "san", -(2 + extra) },
        { "health", -1 },
    }
end

-- ============================================================================
-- §6  事件文本模板
-- ============================================================================

--- 事件文本模板（随机选取一条）
--- 格式: { title = "标题", desc = "描述" }
M.TEMPLATES = {
    safe = {
        { title = "安全屋",   desc = "一间整洁的公寓，窗帘紧闭。你短暂休整，理智稍有恢复。" },
        { title = "便利店",   desc = "24小时亮着灯的便利店，店员面无表情。热咖啡让你安心不少。" },
        { title = "公园长椅", desc = "街边公园空无一人。你坐下来深呼吸，周围暂时没有异常。" },
    },
    landmark = {
        { title = "地标建筑", desc = "这座建筑是这片区域的标志。周围的街道以它为中心延伸。" },
        { title = "钟塔广场", desc = "古老的钟塔矗立在十字路口。指针停在了一个不存在的时刻。" },
    },
    shop = {
        { title = "黑市商人", desc = "\"需要什么？\" 戴兜帽的人低声问道。交易总是伴随代价。" },
        { title = "旧货铺",   desc = "货架上摆满了不知来源的物品。有些东西看起来不属于这个世界。" },
        { title = "自动售货机", desc = "孤零零的售货机发出嗡嗡声。投币口旁刻着你看不懂的符号。" },
    },
    monster = {
        { title = "阴影蠕动", desc = "墙壁上的影子扭曲变形，朝你涌来。你的理智在动摇……" },
        { title = "回声追踪", desc = "身后传来与你步伐完全同步的脚步声。你不敢回头。" },
        { title = "镜中来客", desc = "橱窗玻璃里映出的不是你的倒影。它在微笑。" },
    },
    trap = {
        { title = "地面塌陷", desc = "脚下的地面突然下沉！你勉强抓住边缘，身体传来一阵剧痛。" },
        { title = "迷雾弥漫", desc = "浓雾从巷子里涌出，方向感瞬间消失。你开始怀疑自己是否还在原地。" },
        { title = "时间错乱", desc = "手表指针疯狂旋转。你感觉刚刚过了一秒，但街上的人都不见了。" },
    },
    reward = {
        { title = "隐藏宝箱", desc = "墙缝里藏着一个锡盒，里面是现金和一卷未曝光的胶卷。" },
        { title = "神秘馈赠", desc = "邮箱里有一个写着你名字的包裹。里面的东西意外地有用。" },
        { title = "失物招领", desc = "桌上放着一叠钞票和记录着什么的胶片。似乎有人特意留给你。" },
    },
    plot = {
        { title = "字条",     desc = "折叠的纸条上写着：\"不要相信第三面墙。\" 你似乎领悟了什么。" },
        { title = "电话响了", desc = "废弃电话亭的话筒在震动。你接起来，听到了很久以前的声音。" },
        { title = "旧报纸",   desc = "报纸头版刊登着一则不可能的新闻——日期是明天。" },
    },
    clue = {
        { title = "涂鸦暗号", desc = "墙上的涂鸦里藏着符号。你举起相机，胶卷自动记录了一切。" },
        { title = "监控残影", desc = "碎裂的屏幕闪过一帧画面——那是一张你从未去过的地方的照片。" },
        { title = "录音磁带", desc = "老旧的录音机里残留着一段对话，说的是一个你似乎忘记的名字。" },
    },
    photo = {
        { title = "留影", desc = "相片上定格的画面取代了原本的恐惧。这里现在安全了。" },
        { title = "净化", desc = "曝光的胶片封印了阴影。被拍下的事物不再具有威胁。" },
    },
    rift = {
        { title = "时空裂隙", desc = "地面出现一道蜿蜒的裂缝，透出幽蓝色的微光。你感到另一个世界在呼唤。" },
        { title = "维度缝隙", desc = "空气中浮现扭曲的纹路，仿佛现实被撕开了一道口子。裂隙另一端的景象若隐若现。" },
        { title = "异界入口", desc = "脚下的地砖突然龟裂，缝隙中涌出暗紫色的雾气。这是通往暗面世界的通道。" },
    },
}

-- ============================================================================
-- §7  阻塞事件（需要模态弹窗的事件类型）
-- ============================================================================

M.BLOCKING_EVENTS = {
    shop = true,
}

-- ============================================================================
-- §8  资源转换事件（特定地点的资源交换）
-- ============================================================================

M.CONVERSION_CONFIG = {
    hospital = {
        icon    = "🏥",
        title   = "医院 · 心理诊疗",
        desc1   = "医生提供了心理辅导服务",
        desc2   = "消耗 2 健康 → 恢复 2 理智？",
        costRes = "health", costAmt = 2,
        gainRes = "san",    gainAmt = 2,
        accent  = { r = 100, g = 180, b = 220 },
    },
    park = {
        icon    = "🌳",
        title   = "公园 · 散步疗愈",
        desc1   = "宁静的环境让身心放松",
        desc2   = "消耗 2 理智 → 恢复 2 健康？",
        costRes = "san",    costAmt = 2,
        gainRes = "health", gainAmt = 2,
        accent  = { r = 100, g = 190, b = 130 },
    },
    gym = {
        icon    = "🏋️",
        title   = "健身房 · 体能训练",
        desc1   = "专注训练让你恢复体力",
        desc2   = "消耗 2 理智 → 恢复 2 健康？",
        costRes = "san",    costAmt = 2,
        gainRes = "health", gainAmt = 2,
        accent  = { r = 220, g = 160, b = 80 },
    },
}

-- ============================================================================
-- §9  暗面世界信息
-- ============================================================================

--- 暗面地点对应的暗面名称  { [location][eventType] = { icon, label } }
M.DARKSIDE_INFO = {
    company = {
        safe    = { icon = "🏢", label = "空荡办公室" },
        monster = { icon = "🕴️", label = "影子上司" },
        trap    = { icon = "📋", label = "无尽加班令" },
        reward  = { icon = "💼", label = "遗落的公文包" },
        plot    = { icon = "🖥️", label = "异常邮件" },
        clue    = { icon = "📂", label = "机密档案" },
    },
    school = {
        safe    = { icon = "🏫", label = "安静教室" },
        monster = { icon = "👤", label = "无面教师" },
        trap    = { icon = "🔔", label = "永不下课" },
        reward  = { icon = "📒", label = "旧笔记本" },
        plot    = { icon = "🎒", label = "无主书包" },
        clue    = { icon = "📝", label = "黑板留言" },
    },
    park = {
        safe    = { icon = "🌳", label = "寂静长椅" },
        monster = { icon = "🌑", label = "树影低语" },
        trap    = { icon = "🕸️", label = "缠绕藤蔓" },
        reward  = { icon = "🍃", label = "净化之风" },
        plot    = { icon = "🗿", label = "奇怪雕像" },
        clue    = { icon = "🪶", label = "地上羽毛" },
    },
    alley = {
        safe    = { icon = "🌙", label = "寂静小巷" },
        monster = { icon = "👁️", label = "墙缝窥视" },
        trap    = { icon = "🕳️", label = "地面塌陷" },
        reward  = { icon = "📦", label = "角落包裹" },
        plot    = { icon = "🚪", label = "不存在的门" },
        clue    = { icon = "✍️", label = "涂鸦暗号" },
    },
    station = {
        safe    = { icon = "🚉", label = "末班列车" },
        monster = { icon = "🚇", label = "不停靠的车" },
        trap    = { icon = "🌀", label = "循环站台" },
        reward  = { icon = "🎫", label = "神秘车票" },
        plot    = { icon = "📻", label = "广播异响" },
        clue    = { icon = "🗺️", label = "失落线路图" },
    },
    hospital = {
        safe    = { icon = "🏥", label = "空病房" },
        monster = { icon = "💉", label = "游走护士" },
        trap    = { icon = "🩺", label = "错误诊断" },
        reward  = { icon = "💊", label = "遗留药品" },
        plot    = { icon = "📋", label = "诡异病历" },
        clue    = { icon = "🔬", label = "实验记录" },
    },
    library = {
        safe    = { icon = "📚", label = "安静角落" },
        monster = { icon = "📖", label = "自翻的书" },
        trap    = { icon = "🔇", label = "沉默诅咒" },
        reward  = { icon = "📜", label = "古老卷轴" },
        plot    = { icon = "📕", label = "禁书" },
        clue    = { icon = "🔖", label = "夹页纸条" },
    },
    bank = {
        safe    = { icon = "🏦", label = "空金库" },
        monster = { icon = "🎭", label = "面具柜员" },
        trap    = { icon = "🔒", label = "锁死的门" },
        reward  = { icon = "💰", label = "无主存款" },
        plot    = { icon = "🏧", label = "异常终端" },
        clue    = { icon = "🧾", label = "可疑账单" },
    },
    cemetery = {
        safe    = { icon = "🪦", label = "寂静墓园" },
        monster = { icon = "💀", label = "游荡亡灵" },
        trap    = { icon = "🕳️", label = "塌陷墓穴" },
        reward  = { icon = "📿", label = "古老护符" },
        plot    = { icon = "🪦", label = "无名墓碑" },
        clue    = { icon = "📜", label = "墓志铭文" },
    },
    gym = {
        safe    = { icon = "🏋️", label = "空旷训练场" },
        monster = { icon = "🥊", label = "暴走训练机" },
        trap    = { icon = "🔗", label = "锁死的器械" },
        reward  = { icon = "💪", label = "力量结晶" },
        plot    = { icon = "🪞", label = "扭曲镜面" },
        clue    = { icon = "🩹", label = "带血绷带" },
    },
}

-- ============================================================================
-- §10 日程模板
-- ============================================================================

M.SCHEDULE_TEMPLATES = {
    company     = { verb = "去公司上班",     reward = { "money", 10 } },
    school      = { verb = "去学校上课",     reward = { "money",  8 } },
    park        = { verb = "去公园散步",     reward = { "san",    1 } },
    alley       = { verb = "穿过小巷",       reward = { "money",  8 } },
    station     = { verb = "去车站接人",     reward = { "money",  6 } },
    hospital    = { verb = "去医院看病",     reward = { "san",    1 } },
    library     = { verb = "去图书馆学习",   reward = { "inspiration", 1 } },
    bank        = { verb = "去银行办事",     reward = { "money", 12 } },
    cemetery    = { verb = "去墓地调查",     reward = { "inspiration", 1 } },
    gym         = { verb = "去健身房锻炼",   reward = { "health", 1 } },
    convenience = { verb = "去便利店购物",   reward = { "money",  5 } },
    church      = { verb = "去教堂祈祷",     reward = { "san",    1 } },
    police      = { verb = "去警察局报案",   reward = { "san",    1 } },
}

-- ============================================================================
-- §11 传闻模板
-- ============================================================================

M.RUMOR_SAFE_TEXTS = {
    "今天%s很平静",
    "%s附近没有异常",
    "听说%s今天很安全",
}

M.RUMOR_DANGER_TEXTS = {
    "%s有脏东西",
    "别去%s，有危险",
    "听说%s闹鬼了",
}

-- ============================================================================
-- §12 查询 API
-- ============================================================================

--- 获取地点信息
---@param location string
---@return table|nil { icon, label }
function M.getLocationInfo(location)
    return M.LOCATION_INFO[location]
end

--- 获取地点标签（快捷方式）
---@param location string
---@return string
function M.getLocationLabel(location)
    local info = M.LOCATION_INFO[location]
    return info and info.label or location
end

--- 获取暗面信息
---@param location string
---@param eventType string
---@return table { icon, label }
function M.getDarksideInfo(location, eventType)
    local locData = M.DARKSIDE_INFO[location]
    if locData and locData[eventType] then
        return locData[eventType]
    end
    -- 回退：使用普通地点信息
    local locInfo = M.LOCATION_INFO[location]
    return {
        icon  = locInfo and locInfo.icon or "❓",
        label = (locInfo and locInfo.label or location) .. "(暗面)",
    }
end

--- 获取事件效果
---@param eventType string
---@return table effects { { resKey, delta }, ... }
function M.getEffects(eventType)
    return M.CARD_EFFECTS[eventType] or {}
end

--- 获取陷阱子类型效果
---@param subtype string
---@return table effects
function M.getTrapSubtypeEffects(subtype)
    return M.TRAP_SUBTYPE_EFFECTS[subtype] or {}
end

--- 获取陷阱子类型信息
---@param subtype string
---@return table { icon, label }
function M.getTrapSubtypeInfo(subtype)
    return M.TRAP_SUBTYPE_INFO[subtype] or { icon = "❓", label = "未知" }
end

--- 随机获取一条事件文本模板
---@param eventType string
---@return table { title: string, desc: string }
function M.getRandomText(eventType)
    local pool = M.TEMPLATES[eventType]
    if not pool or #pool == 0 then
        return { title = "事件", desc = "发生了一些事情..." }
    end
    return pool[math.random(1, #pool)]
end

--- 随机获取一条陷阱子类型文本模板
---@param subtype string
---@return table { title: string, desc: string }
function M.getRandomTrapText(subtype)
    local pool = M.TRAP_SUBTYPE_TEMPLATES[subtype]
    if not pool or #pool == 0 then
        return { title = "陷阱", desc = "遭遇了陷阱..." }
    end
    return pool[math.random(1, #pool)]
end

--- 判断事件是否阻塞（需要模态弹窗）
---@param cardType string
---@param hasChoices boolean|nil 是否有选择项
---@return boolean
function M.isBlockingEvent(cardType, hasChoices)
    if M.BLOCKING_EVENTS[cardType] then return true end
    if hasChoices then return true end
    return false
end

--- 加权随机生成事件类型
--- 复制 BASE_EVENT_WEIGHTS 并叠加 location 的偏移
---@param location string
---@return string eventType
function M.randomEvent(location)
    local offsets = M.LOCATION_WEIGHT_OFFSET[location]
    local total = 0
    local adjusted = {}
    for i, w in ipairs(M.BASE_EVENT_WEIGHTS) do
        local extra = offsets and offsets[w[1]] or 0
        local val = w[2] + extra
        adjusted[i] = { w[1], val }
        total = total + val
    end
    local roll = math.random(1, total)
    local acc = 0
    for _, w in ipairs(adjusted) do
        acc = acc + w[2]
        if roll <= acc then return w[1] end
    end
    return "safe"
end

--- 加权随机生成陷阱子类型
---@return string subtype
function M.randomTrapSubtype()
    local total = 0
    for _, w in ipairs(M.TRAP_SUBTYPE_WEIGHTS) do total = total + w[2] end
    local roll = math.random(1, total)
    local acc = 0
    for _, w in ipairs(M.TRAP_SUBTYPE_WEIGHTS) do
        acc = acc + w[2]
        if roll <= acc then return w[1] end
    end
    return "sanity"
end

--- 获取资源转换配置
---@param location string
---@return table|nil config
function M.getConversionConfig(location)
    return M.CONVERSION_CONFIG[location]
end

--- 获取日程模板
---@param location string
---@return table|nil { verb, reward }
function M.getScheduleTemplate(location)
    return M.SCHEDULE_TEMPLATES[location]
end

--- 获取随机传闻文本
---@param locationLabel string 地点的中文名
---@param isSafe boolean
---@return string
function M.getRandomRumorText(locationLabel, isSafe)
    local pool = isSafe and M.RUMOR_SAFE_TEXTS or M.RUMOR_DANGER_TEXTS
    local template = pool[math.random(1, #pool)]
    return string.format(template, locationLabel)
end

return M
