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
-- 格式: { title = "标题", desc = "描述"[, baiiye = "白夜台词"] }
-- desc: 苏柚第一人称视角，带情绪，符合她嘴硬心软的性格
-- baiiye: 可选，白夜的碎碎念（彩蛋，部分事件专属）

--- 通用事件文本（无地点特化时的 fallback）
M.TEMPLATES = {
    safe = {
        { title = "喘口气",     desc = "没什么异常。周围安静得像普通的下班路。你靠着墙站了一会儿，感觉脑子里的噪音小了一点。",
          baiiye = "回来了就好。" },
        { title = "还好",       desc = "什么都没发生。你确认了四周三遍，手机信号正常，影子没有乱动。今天这一格是安全的。" },
        { title = "普通的街角", desc = "路灯亮着，有猫从墙头跳下来。你看了它一眼，它也看了你一眼，然后走了。不是灵体，只是猫。",
          baiiye = "那只猫……我认识。" },
    },
    landmark = {
        { title = "地标",       desc = "这座建筑矗在这里不知道多少年了。光晕覆盖的区域感觉更实在一些，像踩在有重量的地面上。" },
        { title = "庇护所边缘", desc = "地标的气场渗过来，你感觉肩膀轻了一点。不是安全，但至少暂时没有东西敢靠近。" },
    },
    shop = {
        { title = "暗巷交易",   desc = "对方没有抬头，把东西推过来，等你放钱。不问来路，不留名字。这种交易有种奇异的公平。" },
        { title = "旧货铺",     desc = "货架上的东西来历不明，但标价清楚。你盯着那卷胶卷看了很久，最后还是买了。",
          baiiye = "那家店的老板……不是人。你下次少去。" },
        { title = "自动售货机", desc = "投了一枚硬币，出来的东西不是你选的。但它确实是你现在需要的。这台机器懂你。" },
    },
    monster = {
        { title = "影子追来了", desc = "背后有东西。你没有回头——白夜说过，回头等于告诉它你知道它在那里。你加快了脚步。",
          baiiye = "下次叫我。不要自己扛。" },
        { title = "它看见我了", desc = "橱窗玻璃里多了一张脸，不是你的。你举起相机，手在抖，还是按下了快门。",
          baiiye = "拍得很准。" },
        { title = "脚步声",     desc = "身后的脚步和你走得一模一样，停的时候也停，走的时候也走。你深吸一口气，转身。什么都没有，但理智已经消耗了。" },
    },
    trap = {
        { title = "脚下一空",   desc = "地面突然不对劲。你反应过来的时候已经摔了，撑地的手掌火辣辣的。疼是真的，至少说明你还在这个世界。" },
        { title = "迷雾",       desc = "雾涌进来，很快，方向感全丢了。你站在原地数到十，深呼吸，告诉自己不要跑。雾散开以后，你已经不知道走了多远。",
          baiiye = "下次遇到雾，蹲下来。雾层不厚，蹲着能看见地面。" },
        { title = "时间吃掉了", desc = "手表不对了。你确定刚才只走了两步，但周围的人已经换了一批，天色深了一个层次。有什么东西偷走了时间。" },
    },
    reward = {
        { title = "意外之财",   desc = "墙缝里有个锡盒。里头是钱和没曝光的胶卷，叠得整整齐齐，像有人特意留给会找到这里的人。",
          baiiye = "是谁留的？" },
        { title = "邮件",       desc = "邮箱里躺着个没有寄件地址的包裹，写着你的名字。打开来，东西实用得出奇。你站在路边开了很久，想不起来是谁寄的。" },
        { title = "留下来的东西", desc = "桌上摆着钱和一卷胶片。没有便条，没有留言。像是有人知道你会来，把需要的东西先放在这里。" },
    },
    plot = {
        { title = "字条",       desc = "折叠的纸条塞在门缝里，字迹很熟悉，但你想不起来在哪见过。上面写着：「不要相信第三面墙。」",
          baiiye = "第三面墙是……先别去碰。" },
        { title = "电话",       desc = "废弃电话亭里，话筒从没有人碰的地方掉下来了。你犹豫了一下，还是拿起来。里面有人在说话，声音很远，像是从很久以前传过来的。" },
        { title = "旧报纸",     desc = "头版是一则失踪通告，照片模糊，日期是明天。你把它折起来放进口袋，说不清为什么。" },
    },
    clue = {
        { title = "暗号",       desc = "涂鸦里有你看得懂的东西。不知道是谁画的，但它对你有意义。你举起相机，胶卷咔嗒一声，记录下来了。",
          baiiye = "……我见过这个符号。" },
        { title = "监控里的画面", desc = "碎屏幕闪了一下，定格在一帧——一个你没去过的地方，但你认出了背景里的某个细节。你站在那里看了很久，没有拍照。" },
        { title = "磁带",       desc = "录音机里的声音很旧，带着磁粉的嗡嗡声。对话内容你只听懂了一个名字，但那个名字让你心里沉了一下。" },
    },
    photo = {
        { title = "拍下来了",   desc = "快门按下去的瞬间，阴影消散了。相纸上定格的是普通的街景，像什么都没发生过。但你知道有什么东西被封进去了。" },
        { title = "胶卷净化",   desc = "曝光的胶片把那团东西困住了。白夜说过，被相机拍到的灵体会暂时失去对现实的附着力。有效，虽然你还是不太信。",
          baiiye = "信不信都管用。" },
    },
    rift = {
        { title = "裂隙",       desc = "地砖裂开了，缝里渗出幽蓝的光。你认出了这个——暗面的入口。白夜的声音像是从那边传来的，在问你要不要进去。" },
        { title = "缝隙",       desc = "空气扭曲了一块，像热浪，但带着凉意。裂隙另一边的东西若隐若现，你看了一眼，赶紧别开眼睛。",
          baiiye = "进来。我在里面。" },
        { title = "异界入口",   desc = "暗紫色的雾从地缝涌出来，散在你脚边。脚下没有危险，但你知道跨过去就是另一个世界。你深呼吸，想了想，还是走进去了。" },
    },
}

-- ============================================================================
-- §6.5  地点专属事件文本（优先于通用 TEMPLATES）
-- ============================================================================
-- 格式: LOCATION_EVENT_TEMPLATES[locKey][eventType] = { {title, desc[, baiiye]}, ... }
-- 命名体现地点特色；desc 保持苏柚视角，融入该地点的氛围

M.LOCATION_EVENT_TEMPLATES = {
    -- 公司
    company = {
        safe    = {
            { title = "加班到天黑", desc = "今天没发生什么。坐在工位上，听着键盘声和空调声，感觉自己是个普通人。难得的一天。" },
            { title = "茶水间",     desc = "倒了杯热水，靠着窗台站了一会儿。楼下是普通的街道，没有阴影，没有异声。你喝完了整杯。" },
        },
        monster = {
            { title = "加班的同事", desc = "走廊尽头坐着人，背对你，一动不动。你绕了半圈确认——那个工位今天没有排班。你没叫保安，直接走了。",
              baiiye = "下次叫我先看一眼。" },
            { title = "电梯里",     desc = "电梯门关上以后，里面多了一个影子。你盯着楼层数字，数到一楼，出去。不要想电梯里到底有几个人。" },
        },
        trap    = {
            { title = "文件消失了", desc = "你明明把胶卷锁在抽屉里了。打开来，不见了。这不是忘记，这是有东西进来过。",
              baiiye = "是那种会开锁的。以后放包里。" },
            { title = "会议室的门", desc = "推开会议室，里面有东西从角落闪过去。你直接把门关上了，绕路走。今天不开会了。" },
        },
        reward  = {
            { title = "快递到了",   desc = "前台递来一个没有寄件信息的包裹，说是今早到的，没有人认领。里面是你用得着的东西，分量刚好。" },
            { title = "奖金",       desc = "工资条里多了一行，没有标注。你没有去问财务，把钱存起来了。" },
        },
        clue    = {
            { title = "同事的电脑", desc = "同事临时离开，屏幕没锁。你只是扫了一眼，然后看到了一封没发出去的邮件——收件人的名字你认识。",
              baiiye = "截图了吗？" },
            { title = "碎纸机边",   desc = "碎纸机旁边的纸篓里有一张没进去的。你把碎片拼了拼，认出了几个词——和你在找的事有关。" },
        },
        plot    = {
            { title = "会议记录",   desc = "翻到最后一页，多了一行不是会议内容的字：「她在七楼。」没有人知道是谁写的，七楼长期空置。" },
        },
    },

    -- 学校
    school = {
        safe    = {
            { title = "操场",       desc = "下午的操场空着，阳光很正常，不带任何滤镜。你在跑道上走了一圈，什么都没发生。好像回到了很久以前的某个下午。" },
            { title = "图书室",     desc = "书架一排排的，气味是旧纸和木头。你随手翻了本书，里面没有夹东西，没有眼睛，只是书。" },
        },
        monster = {
            { title = "空教室",     desc = "走廊里亮着灯的那间教室，里面的黑板上有字。你凑近看，字在变。你退出来，不再靠近。" },
            { title = "操场角落",   desc = "操场角落的单杠边站着一个人形。你举起相机——镜头里什么都没有，但人形还在。你按下快门，它消失了。",
              baiiye = "相机只是让你镇定。" },
        },
        trap    = {
            { title = "作业",       desc = "不知道从哪里飘来一张卷子，写着你的名字。你拿起来，字迹开始晕染，烧进掌心。理智消耗了。" },
            { title = "门锁",       desc = "推开门，里面把你锁上了。你在黑暗里站了一段时间，等锁自己开。等到了，但不知道过去了多久。" },
        },
        reward  = {
            { title = "失物箱",     desc = "走廊角落有个失物招领箱，里头有一卷胶卷和一些零钱，没有名字牌。你把它们带走了，觉得它们是给你的。" },
            { title = "借书证",     desc = "图书室阿姨塞给你一张条，说是有人托她留着的。里面夹着一些钱，折得整整齐齐。" },
        },
        clue    = {
            { title = "旧课桌",     desc = "课桌角上刻着字，很细，要侧着光才能看见。不是名字，是一句话，写着你看得懂的暗语。",
              baiiye = "……我以前也刻过这种东西。" },
            { title = "旧笔记本",   desc = "扉页写着一个名字，但内容是你在找的事情。像是日记，又像是留给你看的。你翻到最后一页，空白的。" },
        },
        plot    = {
            { title = "广播响了",   desc = "校园广播突然开机，没有声音，只有一段很旧的录音底噪。然后说了一个名字，然后关掉了。就那一个名字。" },
        },
    },

    -- 公园
    park = {
        safe    = {
            { title = "长椅",       desc = "坐下来，闭上眼，听风。没有脚步声跟着，没有影子贴过来。就是风。你坐了一会儿，起身，感觉脑子轻了点。",
              baiiye = "下次我也想去。" },
            { title = "散步",       desc = "走了一段，什么都没有。路灯一个一个亮起来，行人正常地走路。你数了数，七盏路灯，都正常。安全的。" },
        },
        monster = {
            { title = "湖面",       desc = "湖面上漂着东西，太暗了看不清。你没有靠近，绕了一大圈。等你回头，湖面是干净的，但你跑了很多步。" },
            { title = "树影",       desc = "树影在动，但没有风。你站着看了一会儿，树影越来越多。你举起相机，按了快门。影子停了。" },
        },
        trap    = {
            { title = "雾",         desc = "公园的雾来得莫名其妙，你走进去，再走出来，已经不在原来的位置了。迷失了方向感，胸口很闷。",
              baiiye = "说了遇到雾要蹲下来……" },
            { title = "石板路",     desc = "脚下一块石板松了，踩下去整个腿陷进去。你把自己拽出来，腿上一道划伤，裤子破了，心情也破了。" },
        },
        reward  = {
            { title = "草地里",     desc = "走错了路，踩进草地，脚边多了个塑料袋。里面是钱和一包没拆封的东西。你看了看，带走了。" },
            { title = "自动售卖机", desc = "公园里的旧售卖机投了硬币，掉下来两瓶，只买一瓶的。你拿走了，喝了一瓶，感觉今天运气不差。" },
        },
        clue    = {
            { title = "长椅刻字",   desc = "长椅背面有字，很旧，但能认出来。你拍下来，看了几遍，这是在找的那个人留下的。",
              baiiye = "……我认识这个地方。" },
            { title = "草地里的东西", desc = "你没打算去找，但脚踢到了一个信封。里头的照片被雨淋过，模糊了大半，但还剩下一个细节。" },
        },
        plot    = {
            { title = "留言",       desc = "告示牌上多了一张贴纸，颜色和告示牌差不多，要认真看才能发现。上面写着一行字，内容是你一直想知道的。" },
        },
    },

    -- 小巷
    alley = {
        safe    = {
            { title = "穿过去了",   desc = "小巷比预想的短。你屏着气走完了，出来的时候回头看了一眼——黑的，安静，什么都没追出来。今天走运。" },
            { title = "猫",         desc = "巷子里有猫，普通的橘猫，蹲在纸箱上看你。你停下来确认了一下，不是灵体，只是猫。你松了口气。" },
        },
        monster = {
            { title = "巷子里的东西", desc = "走到一半，后面有声音。不是脚步声，是那种会爬的东西发出的声音。你跑完了剩下的路，没有回头。",
              baiiye = "那条巷子以后绕开。" },
            { title = "等在出口",   desc = "出口处站着一个影子，没有脸，但有轮廓。你往回走，绕远路。花了三倍的时间，但活着出来了。" },
        },
        trap    = {
            { title = "袋子",       desc = "墙角的纸袋一碰就炸开，里面是什么你看不清，但那股气味让你头晕了很久，走了三格才缓过来。" },
            { title = "地上的东西", desc = "踩了一下，脚底传来灼烧感。你抬脚看，什么都没有，但疼是真实的，理智也消耗了。" },
        },
        reward  = {
            { title = "藏着的盒子", desc = "砖头缝里塞着一个锡盒。里头有钱和一卷没开封的胶卷，叠得整整齐齐，像是有人特意留在这里的。",
              baiiye = "有人帮你留的。" },
            { title = "地上的包",   desc = "背包压在垃圾堆边上，像是故意放在那里。里头的东西你都用得着，没有多余的，也没有缺少的。" },
        },
        clue    = {
            { title = "涂鸦",       desc = "墙上的涂鸦换了，上面多了一组符号。你举起相机拍了，放大看，是在找的那件事留下的痕迹。" },
            { title = "路灯下",     desc = "路灯下有个信封，是干的，像是刚放上去的。里头的内容让你站在原地读了三遍。" },
        },
        plot    = {
            { title = "陌生人",     desc = "有人从你身边走过，塞给你一张纸条，没有停下来。你展开来——三个字，一个地址。你不确定要不要去。" },
        },
    },

    -- 车站
    station = {
        safe    = {
            { title = "候车",       desc = "候车厅嘈杂，行人正常走路。你找了个角落站着，看了会儿人来人往，没有人盯着你，没有影子。普通的人群。" },
            { title = "夜班车",     desc = "末班车只剩几个人。你找了个靠窗的位置，车窗外的路灯一闪一闪，全都是正常的灯。你睡了一小段路。",
              baiiye = "你睡着了……没事，我看着。" },
        },
        monster = {
            { title = "站台末端",   desc = "站台最后一格，有个人形一直站着，列车来了它没上，列车走了它还在。你在另一头等，没有走近。" },
            { title = "空车厢",     desc = "你进的那节车厢是空的。坐下以后，玻璃里有多出来的倒影。你看着它，它也看着你，直到下一站你提前下了。" },
        },
        trap    = {
            { title = "检票口",     desc = "检票口的感应器扫了你一下，有什么东西附着上来了。你感觉到了，但看不见——直到理智开始消耗，你才明白已经晚了。",
              baiiye = "以后过检票口快点过。别在那里停。" },
            { title = "时刻表",     desc = "对着时刻表看，眼睛突然花了，等回过神，手表快了一个小时。时间被吃掉了，你错过了你需要去的地方。" },
        },
        reward  = {
            { title = "失物招领处", desc = "失物招领台上放着一个没人认领的袋子，工作人员说让你拿走。里头是钱和一卷好胶卷，正是你缺的。" },
            { title = "座位下面",   desc = "座位下有个纸袋，里头有钱，用橡皮筋扎着。没有留言，但你知道是留给你的。" },
        },
        clue    = {
            { title = "旧行李箱",   desc = "行李寄存处有个箱子，号码是你见过的一组数字。你用那组数字开了锁，里头有你要找的东西的痕迹。",
              baiiye = "……那组数字，你是从哪里见到的？" },
            { title = "广播",       desc = "广播里报了一个站名，夹在正常广播中间，出现了两秒。你确认听见了，但没人抬头看，只有你知道那个名字的意义。" },
        },
        plot    = {
            { title = "月台上",     desc = "末班车开走以后，月台上只剩你一个人。然后广播响了，说的是一个已经关闭的线路名。你看了看空旷的轨道，转身走了。" },
        },
    },

    -- 医院
    hospital = {
        safe    = {
            { title = "诊室外",     desc = "等候区的椅子硬，人很多，气味是消毒水。你坐了一会儿，填了表，检查说没问题。普通的一次普通的就诊。" },
            { title = "走廊",       desc = "走廊灯是白的，脚步声回响。你走了很长一段，没有影子跟着，没有声音在你背后。只是医院的走廊，不是别的什么。" },
        },
        monster = {
            { title = "病房走廊",   desc = "某间病房的门是开着的，里头没有病人，但床单是凹着的，像有人躺着。你没有进去，走快了几步。",
              baiiye = "那间病房……你以后不要去那边走。" },
            { title = "电梯里",     desc = "医院的电梯最后只剩你一个人，然后不是你一个人了。你盯着电梯镜子，手指按着开门键，一直按到一楼。" },
        },
        trap    = {
            { title = "药",         desc = "护士给了一包药，说是你的，但你没挂号。你接了，走到门口，感觉有什么东西渗进来了。理智消耗了。",
              baiiye = "来路不明的东西不要吃……" },
            { title = "走错了楼层", desc = "电梯开错了层，你出来才发现这层的灯是坏的。等你找到楼梯走下来，时间不对，健康也消耗了一些。" },
        },
        reward  = {
            { title = "药房",       desc = "药房的老阿姨塞给你一瓶说是「别人忘拿的」，但分量和你情况刚好对上。你道了谢，没问太多。",
              baiiye = "那位阿姨……是好人。" },
            { title = "自动售货机", desc = "医院走廊的售货机里投了一枚硬币，掉出来两罐。你拿了，感觉今天的运气可以用在更重要的地方了。" },
        },
        clue    = {
            { title = "病历",       desc = "护士台散落着一张病历，你只是扫了一眼，然后认出了备注栏里那个名字。你把它拍了下来，手在抖。" },
            { title = "留言板",     desc = "医院入口的留言板上贴着一张便条，被其他东西压着，差点看不见。便条上写的，是一个你一直在找的细节。" },
        },
        plot    = {
            { title = "值班室",     desc = "值班医生在睡觉，值班室的门没关紧。里头的显示器上滚着一行字，内容和苏瑶的消失有关。你只来得及拍了一半。" },
        },
    },

    -- 图书馆
    library = {
        safe    = {
            { title = "阅览室",     desc = "书页翻动的声音，空调的嗡嗡声。没有人看你，你坐下来，翻了本书，什么都没发生。图书馆是安全的，至少今天。" },
            { title = "安静的角落", desc = "最里面的角落，书架挡着，没有人来。你靠着书架站了一会儿，感觉脑子里的杂音小了一点。",
              baiiye = "你喜欢这种地方。" },
        },
        monster = {
            { title = "会自己翻的书", desc = "书架上某本书一直在翻页，你走过去，它停了。你往回走，它又开始翻了。你举起相机对准，快门按下，声音没了。" },
            { title = "馆员",       desc = "馆员一直看着你，从你进来就开始。你检查了三遍，确认她不是正常的人。你绕到另一侧书架，等她的视线移开，快步离开。" },
        },
        trap    = {
            { title = "禁书区",     desc = "你不小心碰了一本不该碰的书，书页黏住了手，撕开来，手心有什么东西留下了。理智消耗了。",
              baiiye = "那一排书……以后别碰。" },
            { title = "拷贝机",     desc = "拷贝机扫了一下你，不是你放进去拷贝的东西，是你自己。机器嗡了一声，你的胶卷少了一张。" },
        },
        reward  = {
            { title = "还书箱",     desc = "还书箱里有本书，夹着一个信封，没有名字。信封里有钱和一张小纸条，写着你今天需要知道的事。" },
            { title = "馆员推荐",   desc = "一位老馆员把一本书推到你面前，说是「有人预约了，没来取」。书里夹着的东西比书本身有用得多。" },
        },
        clue    = {
            { title = "旧档案室",   desc = "档案室的门没锁，里面有一盒旧资料，最上面一份写着你认识的名字。你把关键内容拍了下来，相机的快门声在空屋子里很响。" },
            { title = "古籍",       desc = "古籍区一本书的书脊上刻着符号，和你在别处见过的符号一样。你翻开来，里面有人用铅笔做了标注。",
              baiiye = "那些符号……有人比你早来过。" },
        },
        plot    = {
            { title = "阅览室的书签", desc = "阅览室一张桌上，书签夹在某页。那一页的内容，和苏瑶最后的位置描述吻合。你把书签翻过来，背面有字：「快一点。」" },
        },
    },

    -- 银行
    bank = {
        safe    = {
            { title = "取款机",     desc = "队排了很长，柜员说了好几遍「请稍等」。最终一切正常，号码对了，钱到了，签字，离开。普通的银行，普通的排队。" },
            { title = "等候区",     desc = "塑料椅子，叫号广播，空调冷。你坐着等了很久，什么异常都没有。银行今天是安全的，你可以把这格划掉了。" },
        },
        monster = {
            { title = "金库那层",   desc = "不知道怎么走到了负一层，金库门是开着的，里面有东西在动。你没有进去，按了很久电梯，等上来。",
              baiiye = "银行地下层……有些东西在那里住了很久了。" },
            { title = "摄像头",     desc = "银行的摄像头一直转向你，跟着你走。你看了一眼监控显示器，屏幕上你的位置周围多了几个影子，现实里看不见。你快步走出去了。" },
        },
        trap    = {
            { title = "ATM",        desc = "ATM屏幕闪了一下，卡被吞进去了。等你去挂失的时候，账户里的一部分钱已经不见了。不是盗刷，是更麻烦的东西。" },
            { title = "保险箱",     desc = "你根本没有打开保险箱，但钱包里的钱少了。你翻遍了口袋，检查了三遍，确认是少了。这家银行有贼，不是人的那种。" },
        },
        reward  = {
            { title = "金库",       desc = "柜员说有一笔之前被冻结的钱可以取出来了，你没有追问原因，签了字，拿走了。" },
            { title = "保险柜",     desc = "保险柜里有之前存的东西，加上一些不知道什么时候多出来的。你没有纠结那些多出来的来历，用了。" },
        },
        clue    = {
            { title = "档案",       desc = "银行历史档案室里有一份账户记录，开户人名字你认识。你拍了下来，账目里的某些流向说明了一些事情。" },
            { title = "监控录像",   desc = "保安去上厕所，监控室没锁。你快步进去，调了一段录像，关键的那一帧正好没被覆盖掉，你截了图。" },
        },
        plot    = {
            { title = "可疑记录",   desc = "柜员打印了一份「异常账户提示」，塞给你说「这是你的」，但那个账号不是你的。上面记录的那些交易时间，和苏瑶失踪的日期重叠。" },
        },
    },

    -- 墓地
    cemetery = {
        safe    = {
            { title = "安静",       desc = "墓地今天出奇地安静，连风声都轻。你走完了这一格，没有东西靠近，没有声音跟着。你不确定这是好事还是坏事。",
              baiiye = "今天的墓地……比较干净。" },
            { title = "无事",       desc = "你走进去，走出来，没有发生任何事。墓地今天就是普通的墓地，不是别的什么。你把这件事记在心里，以备后用。" },
        },
        monster = {
            { title = "碑后面",     desc = "墓碑后面有东西，你绕过去看，它已经不在那里了，但声音还在，围着你转了几圈，然后离开了。理智消耗了。",
              baiiye = "不要主动去看那种东西。听见就走。" },
            { title = "深夜的墓地", desc = "入夜以后墓地的规则变了。你发现的时候已经走进太深了，跑出来的时候什么附着在身上，抖了很久才把它抖掉。" },
        },
        trap    = {
            { title = "地陷了",     desc = "脚踩下去，地面松了，陷了半截。你把自己拽出来，鞋底留在泥里，腿上是冷的。墓地不是所有地方都稳固的。" },
            { title = "纸钱",       desc = "有人在烧纸钱，火势突然朝你涌过来。等你退开，有什么东西已经附着在衣服上了，烧也烧不干净。",
              baiiye = "烧纸钱的时候别靠近……以后记住。" },
        },
        reward  = {
            { title = "守墓人",     desc = "守墓老人把一个旧锡盒递给你，说是「早就该有人来拿了」。里头有你能用的东西，他不解释，你也没有问。" },
            { title = "供品",       desc = "无主的供品摆在那里，没有人认领。你犹豫了一下，带走了——能用的不该浪费，不管来路。" },
        },
        clue    = {
            { title = "墓碑背面",   desc = "墓碑背面刻着一行字，不是正常的墓志铭，是一段坐标和日期。你举起相机拍下来，手有点凉。",
              baiiye = "……这块碑是新的。" },
            { title = "花圈",       desc = "新鲜的花圈，但墓碑上的日期是很久以前的。花圈里插着一张纸，上面的字和你在找的事有关联。" },
        },
        plot    = {
            { title = "无名碑",     desc = "角落里有块没有名字的碑，只有日期，和苏瑶失踪的那天一样。你站在那里，没有动，站了很久。" },
        },
    },

    -- 健身房
    gym = {
        safe    = {
            { title = "训练",       desc = "跑了几公里，做了几组，出了一身汗。身体是实在的，疲惫是实在的。运动以后什么都清醒一些，包括感觉到有东西时的第一反应。",
              baiiye = "流汗了就擦一下嘛……" },
            { title = "器材区",     desc = "健身房今天没有异常，器材是正常的器材，镜子里是正常的你。你训练了一会儿，感觉恢复了一些体力。" },
        },
        monster = {
            { title = "镜子",       desc = "镜子里你身边多了一个影子，跟着你做同样的动作。你没有理它，专注盯着自己，等它消失了你才回过神来擦汗。" },
            { title = "更衣室",     desc = "更衣室里有东西，你还没进去就感觉到了。你在门口站了一秒，转身走了。今天不换衣服了。" },
        },
        trap    = {
            { title = "器械故障",   desc = "杠铃卡住了，重量全压在身上，抬不起来。好不容易撑开，身上疼了好一会儿。不是器械故障，是有东西在压着它。" },
            { title = "水",         desc = "直饮机的水喝了一口，味道不对，但已经晚了。不是真的有毒，是渗了什么进来。理智消耗了。",
              baiiye = "以后别用那台直饮机。" },
        },
        reward  = {
            { title = "忘拿的包",   desc = "更衣室里有个包，锁着，上面贴着字条：「给下一个来的人」。打开来，里头有你今天正好需要的东西。" },
            { title = "赛后奖品",   desc = "前台说你参加了一个你不记得报名的比赛，奖品是一些物资。你接了，确认没有问题，拿走了。" },
        },
        clue    = {
            { title = "会员记录",   desc = "前台的平板上调出了一个会员的打卡记录，上面有个熟悉的名字——你一直在找她的痕迹，她来过这里。",
              baiiye = "她去过很多地方……你慢慢找。" },
            { title = "教练的笔记", desc = "器械架下面有本小笔记本，不是训练日志，是观察记录。里头有几行描述的是你在找的那件事的细节。" },
        },
        plot    = {
            { title = "镜子后面",   desc = "健身房大镜子的后面有道缝，缝里塞着个信封，像是有人刻意放进去的。信封里的内容，关于苏瑶最后一次在现实世界的位置。" },
        },
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
