-- ============================================================================
-- data/mid_day_events.lua - 每日中段触发事件数据
-- 触发时机：玩家完成当日任务（抵达目标地点）时
--   1. 优先查 hookId="daily_goal_<location>" (地点专属)
--   2. 无匹配则查 hookId="daily_goal_any" (通用兜底，章节内随机)
--   3. 仍无则静默
-- ============================================================================

return {
    version = 1,
    events = {

        -- ====================================================================
        -- 苏醒章节（第 1-3 天）— 地点专属
        -- ====================================================================

        {
            id = "mid_hospital_aw",
            hookId = "daily_goal_hospital",
            priority = 10,
            onceFlag = "mid_hospital_aw",
            condition = { all = {
                { chapter = "awakening" },
                { not_flag = "mid_hospital_aw" },
            }},
            dialogue = {
                { speaker = "旁白", text = "路过医院门口，苏柚不由自主地放慢了脚步。" },
                { speaker = "白夜", text = "不喜欢这里吗？" },
                { speaker = "苏柚", text = "刚出院。我可不想再来第二次。" },
                { speaker = "白夜", text = "一股消毒水的味道。" },
                { speaker = "旁白", text = "它没再说话，悄悄飘到离医院大门远一点的位置，像是在回避什么。" },
            },
        },

        {
            id = "mid_park_aw",
            hookId = "daily_goal_park",
            priority = 10,
            onceFlag = "mid_park_aw",
            condition = { all = {
                { chapter = "awakening" },
                { not_flag = "mid_park_aw" },
            }},
            dialogue = {
                { speaker = "旁白", text = "路边花坛旁蹲着一只橘猫，白夜比苏柚先蹲下去了。" },
                { speaker = "白夜", text = "过来……过来……" },
                { speaker = "旁白", text = "橘猫抬起头，走了两步，直接从白夜身体里穿了过去。" },
                { speaker = "旁白", text = "白夜趴在地上，低头看了看自己的手。" },
                { speaker = "苏柚", text = "忘了她看不见你？" },
                { speaker = "白夜", text = "……忘了。" },
                { speaker = "旁白", text = "橘猫在远处回头看了一眼，白夜还趴在地上没动。" },
            },
        },

        {
            id = "mid_convenience_aw",
            hookId = "daily_goal_convenience",
            priority = 10,
            onceFlag = "mid_convenience_aw",
            condition = { all = {
                { chapter = "awakening" },
                { not_flag = "mid_convenience_aw" },
            }},
            dialogue = {
                { speaker = "旁白", text = "白夜在货架前停了很久，盯着一排泡面研究。" },
                { speaker = "苏柚", text = "想吃？" },
                { speaker = "白夜", text = "嗯。只是……棠不买这个。" },
                { speaker = "旁白", text = "沉默了一拍。" },
                { speaker = "白夜", text = "……没什么。走吧。" },
                { speaker = "苏柚", text = "（拿起方便面把篮子塞满）" },
                { speaker = "旁白", text = "白夜没说话，飘在苏柚身后，保持了比平时多一点的距离。" },
            },
        },

        -- ====================================================================
        -- 苏醒章节（第 1-3 天）— 通用兜底
        -- ====================================================================

        {
            id = "mid_amb_aw_01",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_aw_01",
            condition = { all = {
                { chapter = "awakening" },
                { not_flag = "mid_amb_aw_01" },
            }},
            dialogue = {
                { speaker = "旁白", text = "前面有人低着头快步走来，苏柚没注意。" },
                { speaker = "旁白", text = "白夜不知道什么时候飘到了她前面。" },
                { speaker = "旁白", text = "那人绕开了。只是走路的惯性，还是别的什么，说不清楚。" },
            },
        },

        {
            id = "mid_amb_aw_02",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_aw_02",
            condition = { all = {
                { chapter = "awakening" },
                { not_flag = "mid_amb_aw_02" },
            }},
            dialogue = {
                { speaker = "旁白", text = "等红灯的时候，苏柚正在给白夜解释为什么要等。" },
                { speaker = "苏柚", text = "……红的不能走，绿的可以走，黄的——" },
                { speaker = "旁白", text = "话说到一半，她停下来了。" },
                { speaker = "苏柚", text = "你在城市里住了这么久，这些你应该都知道的。" },
                { speaker = "白夜", text = "知道。" },
                { speaker = "苏柚", text = "那我在说什么。" },
                { speaker = "白夜", text = "不知道。但是你在说。" },
            },
        },

        {
            id = "mid_amb_aw_03",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_aw_03",
            condition = { all = {
                { chapter = "awakening" },
                { not_flag = "mid_amb_aw_03" },
            }},
            dialogue = {
                { speaker = "旁白", text = "迎面走来的人从白夜身体里穿了过去，白夜没动。" },
                { speaker = "旁白", text = "这已经是今天第三次了。" },
                { speaker = "苏柚", text = "……不难受吗？" },
                { speaker = "白夜", text = "早就习惯了。需要我看看你的内脏吗？" },
                { speaker = "旁白", text = "苏柚没再问，但走路的时候，悄悄往白夜那一侧靠了一点。" },
            },
        },

        {
            id = "mid_amb_aw_04",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_aw_04",
            condition = { all = {
                { chapter = "awakening" },
                { not_flag = "mid_amb_aw_04" },
            }},
            dialogue = {
                { speaker = "旁白", text = "苏柚往右边的橱窗里瞥了一眼，借着玻璃的倒影确认白夜还在。" },
                { speaker = "旁白", text = "白夜也正好在看她。" },
                { speaker = "旁白", text = "两个人同时把视线移开了。" },
            },
        },

        -- ====================================================================
        -- 磨合章节（第 4-7 天）— 地点专属
        -- ====================================================================

        {
            id = "mid_school_bo",
            hookId = "daily_goal_school",
            priority = 10,
            onceFlag = "mid_school_bo",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_school_bo" },
            }},
            dialogue = {
                { speaker = "旁白", text = "学校废弃操场的角落，白夜让苏柚沿墙走了一段路，然后说「再来一次」。" },
                { speaker = "苏柚", text = "这是你教我的第几个「走路方式」了？" },
                { speaker = "白夜", text = "暗面里的步法。迷路的时候有用。" },
                { speaker = "苏柚", text = "好。" },
                { speaker = "旁白", text = "她没有问为什么，也没有问棠是不是也这样学过。" },
                { speaker = "旁白", text = "然后意识到：什么时候开始不问了的？" },
            },
        },

        {
            id = "mid_company_bo",
            hookId = "daily_goal_company",
            priority = 10,
            onceFlag = "mid_company_bo",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_company_bo" },
            }},
            dialogue = {
                { speaker = "旁白", text = "楼道里撞见同事小周，她把苏柚拉到一边。" },
                { speaker = "小周", text = "你最近给我的感觉不一样了。是在和谁交往吗？" },
                { speaker = "苏柚", text = "一位老朋友啦，住在我家里。" },
                { speaker = "小周", text = "诶——老朋友，我懂我懂。" },
                { speaker = "旁白", text = "回家路上，苏柚把这段对话告诉了白夜。" },
                { speaker = "白夜", text = "……我算朋友吗？" },
                { speaker = "苏柚", text = "（停顿）算。" },
                { speaker = "白夜", text = "嗯。" },
            },
        },

        {
            id = "mid_alley_bo",
            hookId = "daily_goal_alley",
            priority = 10,
            onceFlag = "mid_alley_bo",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_alley_bo" },
            }},
            dialogue = {
                { speaker = "旁白", text = "白夜突然飘到苏柚前面，挡住了路。" },
                { speaker = "白夜", text = "从另一条路走。" },
                { speaker = "苏柚", text = "为什么？" },
                { speaker = "白夜", text = "这里不安全。" },
                { speaker = "旁白", text = "几个人走进了巷子里，等了几秒，远处传来一阵尖叫声，随即爆发出热烈的笑声。" },
                { speaker = "苏柚", text = "……谢谢你。" },
            },
        },

        -- ====================================================================
        -- 磨合章节（第 4-7 天）— 通用兜底
        -- ====================================================================

        {
            id = "mid_amb_bo_01",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_bo_01",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_amb_bo_01" },
            }},
            dialogue = {
                { speaker = "旁白", text = "苏柚在便利店门口犹豫了一下，买了两杯奶茶。" },
                { speaker = "旁白", text = "走到路边才意识到白夜不能喝。" },
                { speaker = "白夜", text = "……给我拿着。" },
                { speaker = "苏柚", text = "你拿不住——" },
                { speaker = "旁白", text = "白夜的手指拢住了杯子的外壁，杯子托在了它的手心上。某种特殊的努力。" },
                { speaker = "白夜", text = "我可以。" },
                { speaker = "苏柚", text = "……行吧。" },
                { speaker = "旁白", text = "白夜一路端着那杯奶茶，没有喝，就是端着。" },
            },
        },

        {
            id = "mid_amb_bo_02",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_bo_02",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_amb_bo_02" },
            }},
            dialogue = {
                { speaker = "旁白", text = "商场门口有人拦住苏柚，递来一张传单。" },
                { speaker = "传单员", text = "您好，我们这里——" },
                { speaker = "旁白", text = "那人的视线忽然移开了，走向了别处。白夜飘在苏柚肩膀旁边，什么都没做，只是看着那个人。" },
                { speaker = "白夜", text = "好了。这下他不感兴趣了。" },
                { speaker = "苏柚", text = "……究竟怎么做到的？" },
            },
        },

        {
            id = "mid_amb_bo_03",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_bo_03",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_amb_bo_03" },
            }},
            dialogue = {
                { speaker = "旁白", text = "走到路口，苏柚往左边看了一眼，然后往右边看了一眼。" },
                { speaker = "苏柚", text = "白夜？" },
                { speaker = "白夜", text = "（从右边飘过来）在。" },
                { speaker = "旁白", text = "苏柚发现自己最近过马路前会习惯性地确认白夜在哪一边。" },
                { speaker = "旁白", text = "不是为了找它，只是……习惯了。" },
            },
        },

        {
            id = "mid_amb_bo_04",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_bo_04",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_amb_bo_04" },
            }},
            dialogue = {
                { speaker = "旁白", text = "苏柚在超市里挑了半天，拿起一包零食，又放下。" },
                { speaker = "白夜", text = "左边那个。" },
                { speaker = "苏柚", text = "你怎么知道我喜欢哪个？" },
                { speaker = "白夜", text = "你上次买的就是那个。" },
            },
        },

        {
            id = "mid_amb_bo_05",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_bo_05",
            condition = { all = {
                { chapter = "bonding" },
                { not_flag = "mid_amb_bo_05" },
            }},
            dialogue = {
                { speaker = "旁白", text = "排队的时候太无聊，苏柚低声跟白夜说了一件公司的事。" },
                { speaker = "旁白", text = "说完才发现，这是她今天说话最多的一段。" },
                { speaker = "苏柚", text = "你都听了吗？" },
                { speaker = "白夜", text = "听了。" },
                { speaker = "苏柚", text = "那你觉得——" },
                { speaker = "白夜", text = "你同事说错了，但你没说。" },
                { speaker = "苏柚", text = "……你真的在听。" },
                { speaker = "白夜", text = "一直在。" },
            },
        },

        -- ====================================================================
        -- 真相章节（第 8-11 天）— 地点专属
        -- ====================================================================

        {
            id = "mid_library_tr",
            hookId = "daily_goal_library",
            priority = 10,
            onceFlag = "mid_library_tr",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_library_tr" },
            }},
            dialogue = {
                { speaker = "旁白", text = "图书馆三楼的角落，白夜在书架之间穿行，在某一格前停了下来。" },
                { speaker = "白夜", text = "……这里的书摆法变了。" },
                { speaker = "苏柚", text = "你居然还会来这里学习？" },
                { speaker = "白夜", text = "很久以前。" },
                { speaker = "白夜", text = "我喜欢的漫画被借走了。" },
            },
        },

        {
            id = "mid_cemetery_tr",
            hookId = "daily_goal_cemetery",
            priority = 10,
            onceFlag = "mid_cemetery_tr",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_cemetery_tr" },
            }},
            dialogue = {
                { speaker = "旁白", text = "墓地的角落有什么东西在看苏柚，她回头，什么都没有。" },
                { speaker = "苏柚", text = "……有东西。我感觉到了。" },
                { speaker = "白夜", text = "是暗面的余波。不是实体，进不来。" },
                { speaker = "白夜", text = "别怕，我在。" },
            },
        },

        {
            id = "mid_station_tr",
            hookId = "daily_goal_station",
            priority = 10,
            onceFlag = "mid_station_tr",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_station_tr" },
            }},
            dialogue = {
                { speaker = "旁白", text = "车站的人群里，苏柚看见了一个红色电话亭。" },
                { speaker = "旁白", text = "白夜飘过去，在电话亭外停了一下，然后回来了。" },
                { speaker = "苏柚", text = "怎么了？" },
                { speaker = "白夜", text = "没什么。以前在这里打过电话。" },
                { speaker = "苏柚", text = "说了些什么？" },
                { speaker = "白夜", text = "已经忘了。走吧，这里人太多了。" },
            },
        },

        -- 真相章节，若已触发废弃电话事件，车站另有一版（flag版本）
        {
            id = "mid_station_tr_phonevariant",
            hookId = "daily_goal_station",
            priority = 5,    -- 更高优先级，有 flag 时覆盖普通版本
            onceFlag = "mid_station_tr",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_station_tr" },
                { flag = "plot_phone_call" },  -- 已触发废弃电话事件
            }},
            dialogue = {
                { speaker = "旁白", text = "车站的人群里，苏柚看见了那个红色电话亭。" },
                { speaker = "旁白", text = "白夜望着电话亭，没有说话。很久没有说话。" },
                { speaker = "苏柚", text = "白夜？" },
                { speaker = "白夜", text = "没什么。那个声音不会再打来了。" },
                { speaker = "旁白", text = "它的语气很平静，平静得像在陈述一件很久远的事情。" },
            },
        },

        -- ====================================================================
        -- 真相章节（第 8-11 天）— 通用兜底
        -- ====================================================================

        {
            id = "mid_amb_tr_01",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_tr_01",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_amb_tr_01" },
            }},
            dialogue = {
                { speaker = "旁白", text = "路过五金店的橱窗，苏柚的倒影定格了一秒。" },
                { speaker = "旁白", text = "她握着包带的手势不对——那是白夜教她握刀的方式。" },
                { speaker = "旁白", text = "她松开，重新握，正常了。" },
                { speaker = "苏柚", text = "（低声）没事的。" },
                { speaker = "旁白", text = "白夜没听见，或者没在意，继续飘在她旁边。" },
            },
        },

        {
            id = "mid_amb_tr_02",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_tr_02",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_amb_tr_02" },
            }},
            dialogue = {
                { speaker = "旁白", text = "出门走了很长一段路，白夜一直没说话。" },
                { speaker = "苏柚", text = "怎么了？" },
                { speaker = "白夜", text = "没事。" },
                { speaker = "苏柚", text = "以前你不说「没事」。" },
                { speaker = "白夜", text = "……以前说什么？" },
                { speaker = "苏柚", text = "哼，我就是不说。" },
            },
        },

        {
            id = "mid_amb_tr_03",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_tr_03",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_amb_tr_03" },
            }},
            dialogue = {
                { speaker = "旁白", text = "路过一段很安静的街区，脑子里冒出了一个不像自己的念头。" },
                { speaker = "旁白", text = "声音很轻，像是自己的内心独白——又不完全像。" },
                { speaker = "苏柚", text = "……" },
                { speaker = "白夜", text = "（察觉到什么）怎么了？" },
                { speaker = "苏柚", text = "没事，走神了。" },
                { speaker = "旁白", text = "白夜看了她一眼，没说话，但之后一直飘得离她近一点。" },
            },
        },

        {
            id = "mid_amb_tr_04",
            hookId = "daily_goal_any",
            priority = 20,
            onceFlag = "mid_amb_tr_04",
            condition = { all = {
                { chapter = "truth" },
                { not_flag = "mid_amb_tr_04" },
            }},
            dialogue = {
                { speaker = "旁白", text = "早上苏柚对着镜子刷牙，忽然发现自己的站姿变了。" },
                { speaker = "旁白", text = "脊背挺得很直，肩膀微微后收。" },
                { speaker = "旁白", text = "她盯着镜子里的自己，牙刷停在嘴边。" },
                { speaker = "苏柚", text = "牙刷好像收在鞘里的刀啊。" },
                { speaker = "苏柚", text = "啊，不对。" },
                { speaker = "旁白", text = "换了一个姿势，刷完，漱口，出门。没有告诉白夜。" },
            },
        },

        -- ====================================================================
        -- 幕间日常（可复用，条件更严格）
        -- ====================================================================

        {
            id = "mid_jiuhun",
            hookId = "daily_goal_any",
            priority = 25,
            onceFlag = "mid_jiuhun",
            condition = { all = {
                { chapter = "truth" },
                { min_day = 7 },
                { not_flag = "mid_jiuhun" },
            }},
            dialogue = {
                { speaker = "苏柚", text = "我和棠谁好看？" },
                { speaker = "旁白", text = "（白夜沉默了整整一分钟）" },
                { speaker = "白夜", text = "你好看……但她气质好。" },
                { speaker = "苏柚", text = "那我和她谁做饭好吃？" },
                { speaker = "白夜", text = "你做的好吃……但她切的菜整齐。" },
                { speaker = "苏柚", text = "你就是忘不了她。" },
                { speaker = "白夜", text = "我没有，我只是……记性太好了。" },
            },
        },

        {
            id = "mid_linzhong",
            hookId = "daily_goal_any",
            priority = 25,
            onceFlag = "mid_linzhong",
            condition = { all = {
                { chapter = "truth" },
                { min_day = 9 },
                { not_flag = "mid_linzhong" },
            }},
            dialogue = {
                { speaker = "白夜", text = "不管你想起了什么，都不要恨我。" },
                { speaker = "苏柚", text = "好。" },
                { speaker = "白夜", text = "……如果我在暗面里突然变丑了，你也要假装没看见。" },
                { speaker = "苏柚", text = "你担心的就是这个？" },
            },
        },

        {
            id = "mid_erosion",
            hookId = "daily_goal_any",
            priority = 22,
            onceFlag = "mid_erosion",
            condition = { all = {
                { chapter = "truth" },
                { min_day = 8 },
                { flag = "mid_amb_tr_01" },   -- 先触发了橱窗版本
                { not_flag = "mid_erosion" },
            }},
            dialogue = {
                { speaker = "旁白", text = "早上苏柚对着镜子刷牙，发现自己的站姿又变了。" },
                { speaker = "旁白", text = "这次不只是站姿——连眼神都不对了。" },
                { speaker = "旁白", text = "锐利，戒备，扫视出入口的方向。" },
                { speaker = "旁白", text = "她盯着镜子里的自己，久了，说了句什么。" },
                { speaker = "苏柚", text = "我是苏柚。" },
                { speaker = "旁白", text = "像是在确认，又像是在提醒。" },
            },
        },

    },
}
