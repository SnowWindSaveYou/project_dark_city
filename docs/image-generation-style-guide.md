# 卡面图片生成风格指南

## 确定风格：物语系列 / 新房昭之 × SHAFT

---

## 一、通用规范

### 核心画风要素（所有卡通用，必须）

- `Monogatari series anime background art` / `Monogatari series anime CG illustration`
- `SHAFT studio style`
- `graphic design sensibility`
- `flat color planes` — 区域内无纹理渐变
- `precise shadow geometry` / `hard-edged shadow blocks` — 阴影为硬边几何色块
- `no text, no border`

### 氛围关键词（按需选用）

| 关键词 | 效果 |
|--------|------|
| `eerie stillness` | 诡异静止感 |
| `overwhelming silence` | 压迫性的寂静 |
| `one specific thing is wrong but hard to say what` | 暗示"不对劲"但说不清 |
| `uncanny quality of ordinary space` | 日常场景的超自然感 |
| `oversaturated [color]` | 某颜色刻意过饱和 |

### 构图关键词（按需选用）

| 关键词 | 效果 |
|--------|------|
| `strong one-point perspective` | 强烈一点透视 |
| `strong centered composition` | 中轴对称 |
| `[element] pressing in from both sides` | 两侧压迫感，适合"被困"构图 |
| `extreme close-up` | 物体/面部极特写 |

### 图片尺寸规格

- 比例：`2:3`
- 目标尺寸：`515x768`

---

## 二、地点卡（翻开前）

### Prompt 结构

```
Monogatari series anime background art, SHAFT studio style, daytime, no people.
[地点]: [核心视觉锚点], [氛围细节], flat color planes, precise shadow geometry, [饱和度描述], eerie stillness, graphic design sensibility
```

### 地点卡专属规则

- **白天、无人** — `daytime` + `no people`，空无一人强化"不对劲"感
- **不用入口/外观**，要用**进入后的体验感**作为构图核心
- **每个地点只突出一个主视觉锚点**，其他元素极简

### 地点锚点参考

| 地点 | 锚点元素 | 备注 |
|------|---------|------|
| 公园 | 铺装路径 + 路边长椅 + 行道树 + 远景城市轮廓 | 不要用铁门入口 |
| 医院 | 红十字标志 + 空轮椅 + 冷白灯光 | 红十字图形感强可用 |
| 小巷 | 自动贩卖机 + 极度压缩走廊 + 稀疏电线 | "不该在这里"的发光物体 |
| 图书馆 | 落地玻璃橱窗透出整排书架 + 暖黄灯光 | 透窗策略 |

### 地点卡经验教训

- **不要垫图**：参考图会把画风拉回原始风格，约束力过强
- **不要改时间**：黄昏/夜间只是换了光照，不是画风变化
- **不要堆砌图形元素**：多个强元素互相干扰，丢失留白克制感
- **氛围靠"缺失"**：一把空椅子比复杂背景更有物语感

---

## 三、事件卡（翻开后）

### 与地点卡的核心差异

| | 地点卡 | 事件卡 |
|--|--------|--------|
| 时间 | 白天 | 自由（按事件调性） |
| 人物 | 无人 | **可以有角色** |
| 视觉核心 | 场景/建筑 | 角色反应 / 物体特写 / 怪物主体 |
| 地点感 | 强（需一眼认出地点） | **弱**（通用卡不绑定地点） |

### 事件卡使用场景

玩家触发事件后，卡面**放大占左半屏**，右侧显示事件文本（苏柚和白夜的反应、发生了什么）。因此：

- 卡面要有**情绪锚点**，配合右侧文字
- 构图要在中等尺寸下清晰可读
- 角色表情/姿态可以与右侧文本呼应

### Prompt 结构

```
Monogatari series anime CG illustration, SHAFT studio style, no text, no border.
[构图/主体描述], [角色状态], [光线/氛围], flat color planes, precise shadow geometry, [饱和度], graphic design sensibility
```

### 事件类型设计原则

| 事件类型 | 视觉核心 | 角色使用 | 参考图 |
|---------|---------|---------|--------|
| safe（安全） | 苏柚+白夜的短暂喘息 | 苏柚为主，白夜陪伴 | 苏柚×2 + 白夜 |
| monster（怪物） | **怪物为主体**，占据画面 | 用对应怪物参考，**不用白夜** | 对应怪物图 |
| trap（陷阱） | 苏柚被困瞬间，从后方视角 | 苏柚背对观众 | 苏柚×2 |
| reward（奖励） | 苏柚手部入镜发现物品 | 手部特写，暗示人物 | 苏柚×2 |
| clue（线索） | 苏柚+白夜共同发现，反应>物体 | 两人同框，表情是重点 | 苏柚×2 + 白夜 |
| plot（剧情） | 视具体内容定 | 视需要 | 视需要 |

### 角色参考图规范 🔴

**只要画面中有角色，必须加参考图，且多张优于单张：**

| 角色 | 推荐参考图（本地路径） |
|------|----------------------|
| 苏柚（标准） | `assets/image/主角_京アニv3_20260425162420.png` |
| 苏柚（悲伤/惊恐） | `assets/image/主角_伤心_20260425144628.png` |
| 苏柚（双图保证发型） | 上两张**同时**使用 |
| 白夜 | `assets/image/白夜_chibi_20260506003802.png` |
| 小幽灵怪物 | `assets/image/怪物_小幽灵_20260426072511.png` |
| 长发女鬼 | `assets/image/怪物_长发女鬼v2_20260426072646.png` |
| 幽灵娘 | `assets/image/怪物_幽灵娘v3_20260426072315.png` |
| 面具使 | `assets/image/怪物_面具使v2_20260426072832.png` |

> ⚠️ **发型一致性**：苏柚参考图必须同时使用 `主角_京アニv3` + `主角_伤心` 两张，单张容易导致发型偏差。

> ⚠️ **路径注意**：含日文/特殊字符的文件名（如 `主角chibi恐怖风v5`）在路径传递时需确认编码正确，建议用 `ls` 先确认。

### 已验证的事件卡构图

| 事件 | 构图描述 | 文件（最终版） |
|------|---------|--------------|
| evt_safe_rest | 苏柚坐路边，白夜蜷伏守护，金眼是唯一暖色光源 | evt_safe_rest_v3 |
| evt_monster_shadow | 小幽灵居中悬浮，空洞黑眼，冷白发光，直视玩家 | evt_monster_shadow_v3 |
| evt_trap_generic | 苏柚背对观众贴墙，走廊两侧压迫，前方黑暗封死 | evt_trap_generic_v5 |
| evt_reward_supply | 苏柚手部入镜捡取发光物，单束光柱硬边 | evt_reward_supply_v2 |
| evt_clue_diary | 苏柚+白夜同框看日记，表情凝固，内容留白 | evt_clue_diary_v5 |

### 事件卡经验教训

- **白夜不是怪物**：白夜是苏柚的灵体伴侣，不能出现在通用怪物遭遇卡
- **通用卡不绑定地点**：构图避免强烈的地点特征，削弱"在某个地点"的感觉
- **反应>物体**：线索卡用角色发现反应比直接展示物体更有张力，配合右侧文本
- **陷阱留悬念**：通用陷阱不指定类型，用"已中招"的瞬间感代替具体危险
- **参考图多张**：发型/造型不一致时增加参考图数量，单张容易偏差
