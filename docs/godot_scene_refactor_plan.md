# Godot UI Scene 化重构计划

> **目标**: 将 `_draw()` 手绘 UI 迁移至 Godot 原生 Control 节点 + .tscn 场景文件架构
> **原则**: 核心流程场景和常规 UI 必须有实际 .tscn 文件方便手动调整；特效类保留 `_draw()`

---

## 一、现状诊断

### 1.1 当前架构问题

| 层级 | 现状 | 问题 |
|------|------|------|
| **3D 渲染层** | `board_visual.gd` 使用 MeshInstance3D / Sprite3D | ✅ 已正确 Scene 化 |
| **UI 层** (10 个模块) | 全部使用 `_draw()` 手绘 | ❌ 反模式，无法在编辑器中调整 |
| **特效层** (2 个模块) | `vfx_manager.gd`, `date_transition.gd` 使用 `_draw()` | ✅ 保留，特效适合 `_draw()` |

### 1.2 需要重构的模块清单

| # | 模块 | 文件 | 行数 | 复杂度 | 优先级 |
|---|------|------|------|--------|--------|
| 1 | 事件弹窗 | `ui/event_popup.gd` | ~580 | 🔴 高 | P0 |
| 2 | 资源栏 | `ui/resource_bar.gd` | ~400 | 🔴 高 | P0 |
| 3 | 商店弹窗 | `ui/shop_popup.gd` | ~480 | 🔴 高 | P0 |
| 4 | 标题画面 | `visual/title_screen.gd` | ~175 | 🟡 中 | P1 |
| 5 | 游戏结束 | `visual/game_over.gd` | ~190 | 🟡 中 | P1 |
| 6 | 手牌面板 | `ui/hand_panel.gd` | ~560 | 🔴 高 | P1 |
| 7 | 相机按钮 | `ui/camera_button.gd` | ~250 | 🟡 中 | P2 |
| 8 | 对话覆盖层 | `visual/dialogue_overlay.gd` | ~135 | 🟢 低 | P2 |
| 9 | 气泡覆盖层 | `visual/bubble_overlay.gd` | ~115 | 🟢 低 | P2 |
| 10 | 线索日志 | `ui/clue_log.gd` | ~290 | 🟡 中 | P2 |

### 1.3 不需要重构的模块

| 模块 | 文件 | 原因 |
|------|------|------|
| VFX 管理器 | `lib/vfx_manager.gd` | 纯粒子/特效，适合 `_draw()` |
| 日期过渡 | `visual/date_transition.gd` | 全屏过渡动画，适合 `_draw()` |
| 3D 棋盘 | `controllers/board_visual.gd` | 已正确使用 Scene 节点 |

---

## 二、目标架构

### 2.1 目录结构

```
godot/
├── scenes/
│   ├── main.tscn                    # 主场景（重构，包含完整节点树）
│   ├── ui/
│   │   ├── event_popup.tscn         # 事件弹窗
│   │   ├── resource_bar.tscn        # 资源栏
│   │   ├── shop_popup.tscn          # 商店弹窗
│   │   ├── hand_panel.tscn          # 手牌面板
│   │   ├── camera_button.tscn       # 相机按钮
│   │   ├── clue_log.tscn            # 线索日志
│   │   └── components/              # 可复用子组件
│   │       ├── resource_item.tscn   # 单个资源显示条
│   │       ├── shop_card.tscn       # 商店商品卡
│   │       ├── schedule_item.tscn   # 日程条目
│   │       ├── clue_item.tscn       # 线索条目
│   │       └── toast_item.tscn      # Toast 通知条
│   └── screens/
│       ├── title_screen.tscn        # 标题画面
│       ├── game_over.tscn           # 游戏结束画面
│       ├── dialogue_overlay.tscn    # 对话覆盖层
│       └── bubble_overlay.tscn      # 气泡覆盖层
├── scripts/
│   ├── ui/                          # UI 脚本（重构）
│   └── visual/                      # 视觉脚本（重构）
└── themes/
    └── game_theme.tres              # Godot Theme 资源（统一样式）
```

### 2.2 核心改造思路

| `_draw()` 手绘代码 | 替换为 Godot 节点 |
|---|---|
| `draw_rect()` 背景/面板 | `PanelContainer` / `Panel` + `StyleBoxFlat` |
| `draw_string()` 文字 | `Label` / `RichTextLabel` |
| `draw_rect()` 按钮 + 手动点击测试 | `Button` / `TextureButton` + 信号 |
| `draw_texture()` 图标 | `TextureRect` |
| `draw_circle()` 圆形元素 | `TextureRect` (圆形纹理) 或保留局部 `_draw()` |
| 手动 `_has_point()` 点击区域 | 节点自身输入处理 |
| 手动文字换行计算 | `Label.autowrap_mode = WORD` |
| `draw_set_transform()` 变换 | `Control.pivot_offset` + `scale` / `rotation` |
| 手动布局计算 (位置/间距) | `HBoxContainer` / `VBoxContainer` / `MarginContainer` |

### 2.3 动画迁移策略

现有动画使用 `create_tween()` 操控自定义浮点属性（如 `_panel_scale`, `_overlay_alpha`），然后在 `_draw()` 中读取。

**新方案**: Tween 直接操控节点属性：

```gdscript
# 旧方式
_panel_scale = 0.3
var tw = create_tween()
tw.tween_property(self, "_panel_scale", 1.0, 0.3)
# 然后在 _draw() 中用 _panel_scale 手动变换

# 新方式
$Panel.scale = Vector2(0.3, 0.3)
var tw = create_tween()
tw.tween_property($Panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
# 节点自动按 scale 渲染，无需 _draw()
```

**关键映射**：

| 旧属性 | 新方式 |
|--------|--------|
| `_overlay_alpha` | `$Overlay.modulate.a` 或 `$Overlay.color.a` |
| `_panel_scale` | `$Panel.scale` + `pivot_offset` |
| `_panel_alpha` | `$Panel.modulate.a` |
| `_content_alpha` | `$Panel/Content.modulate.a` |
| `_slide_offset` | `$Panel.position.y` |
| `_hover_t` (插值) | `_process()` 中 lerp `modulate` 或用 Tween |

---

## 三、game_theme.tres 统一样式资源

在开始各模块重构前，先创建一个全局 `Theme` 资源，将 `theme.gd` 中的颜色/字号映射为 Godot StyleBox：

```
themes/game_theme.tres
├── StyleBoxFlat "PanelNormal"     → notebook_paper 色 + notebook_border 边框
├── StyleBoxFlat "PanelModal"      → panel_bg 色 + 圆角 + 阴影
├── StyleBoxFlat "ButtonPrimary"   → accent 色填充
├── StyleBoxFlat "ButtonSecondary" → 透明 + accent 边框
├── StyleBoxFlat "Toast"           → panel_bg + 左侧色条
├── Font "FontRegular"             → 默认字体
├── Font "FontBold"                → 粗体字体
└── 各种字号常量                    → 对应 FONT_SIZE_* 常量
```

这样各 .tscn 场景可直接引用 Theme 资源，修改一处全局生效。

---

## 四、各模块详细设计

### 4.1 [P0] EventPopup — 事件弹窗

**现有功能**: 4 个子系统 — 模态事件弹窗、拍照预览弹窗、裂隙确认弹窗、Toast 通知栈

**建议**: 拆分为 **3 个独立场景** + 1 个子组件：

#### 4.1.1 `event_popup.tscn` — 模态事件弹窗

```
EventPopup (Control) [PRESET_FULL_RECT]
├── Overlay (ColorRect)                    # 半透明遮罩
│   └── color: Color(0,0,0, 0.5)
└── PanelAnchor (CenterContainer)          # 居中容器
    └── Panel (PanelContainer)             # 弹窗主体
        ├── pivot_offset: 居中
        ├── ColorBar (ColorRect)           # 顶部类型色条
        │   └── custom_minimum_size.y = 4
        ├── Content (VBoxContainer)
        │   ├── IconLabel (Label)          # 图标 emoji
        │   │   └── horizontal_alignment = CENTER
        │   ├── TitleLabel (Label)         # 事件标题
        │   ├── DescLabel (Label)          # 描述文字
        │   │   └── autowrap_mode = WORD
        │   └── EffectsRow (HBoxContainer) # 资源效果徽章
        │       ├── EffectBadge1 (PanelContainer)
        │       │   └── Label
        │       ├── EffectBadge2 ...
        │       └── ...
        └── HintLabel (Label)              # "点击关闭"
```

**脚本职责**:
- `show_event(card: Card)` — 填充内容 + 播放入场动画
- 点击 Overlay 或任意位置 → 出场动画 → emit `popup_closed`
- 动画: Tween 操控 `Overlay.color.a`, `Panel.scale`, `Panel.modulate.a`, Content 子节点的 `modulate.a` 逐个淡入

#### 4.1.2 `photo_popup.tscn` — 拍照预览弹窗 (新增独立场景)

```
PhotoPopup (Control) [PRESET_FULL_RECT]
├── Overlay (ColorRect)
└── CenterContainer
    └── PhotoCard (Control)                # 用局部 _draw() 绘制胶片风格
        ├── pivot_offset: 居中
        ├── rotation: 随机微旋转
        ├── TapeStrip (ColorRect)          # 顶部胶带装饰
        ├── PhotoArea (TextureRect)        # 照片区域
        ├── IconLabel (Label)
        ├── TitleLabel (Label)
        ├── DescLabel (Label)
        ├── LocationLabel (Label)
        └── ScoutTag (Label)               # "已侦察" 标签
```

> **注意**: 拍立得风格的倾斜白色卡片效果可通过 `Control.rotation` + `PanelContainer` 配合 `StyleBoxFlat`(白色圆角) 实现，不需要 `_draw()`。

#### 4.1.3 `rift_popup.tscn` — 裂隙确认弹窗 (新增独立场景)

```
RiftPopup (Control) [PRESET_FULL_RECT]
├── Overlay (ColorRect)
└── CenterContainer
    └── Panel (PanelContainer)
        ├── ColorBar (ColorRect)           # 暗紫色条
        ├── Content (VBoxContainer)
        │   ├── IconLabel (Label)          # 漩涡 emoji
        │   ├── TitleLabel (Label)
        │   └── DescLabel (Label)
        └── ButtonRow (HBoxContainer)
            ├── EnterButton (Button)       # "进入暗面"
            └── StayButton (Button)        # "留在此处"
```

**脚本职责**:
- `EnterButton.pressed` → emit `rift_confirmed`
- `StayButton.pressed` 或点击 Overlay → emit `rift_cancelled`

#### 4.1.4 `components/toast_item.tscn` — Toast 通知条 (子组件)

```
ToastItem (PanelContainer)
├── custom_minimum_size: Vector2(280, 0)
├── HBoxContainer
│   ├── TypeBar (ColorRect)                # 左侧类型色条
│   │   └── custom_minimum_size.x = 4
│   └── VBoxContainer
│       ├── HeaderRow (HBoxContainer)
│       │   ├── IconLabel (Label)
│       │   └── TitleLabel (Label)
│       ├── DescLabel (Label)
│       └── EffectsRow (HBoxContainer)
└── ProgressBar (ProgressBar)              # 底部倒计时条
    └── custom_minimum_size.y = 3
```

**Toast 栈管理**: 在 `event_popup.gd` 中维护一个 `VBoxContainer` (锚定右上角)，动态实例化 `toast_item.tscn`。Toast 的入场/出场动画通过 Tween 操控 `position.x` + `modulate.a`。

**信号** (保持不变):
- `popup_closed(card)`
- `photo_popup_closed(card_type)`
- `rift_confirmed()` / `rift_cancelled()`
- `toast_dismissed(card_type)`

---

### 4.2 [P0] ResourceBar — 资源栏

**现有功能**: 双模式 (普通/暗面)，笔记本纸条风格，资源值显示+动画，浮动增减文字

**建议**: 资源栏的视觉风格较为独特（笔记本纸条撕裂边缘、胶带装饰），完全用 Control 节点模拟会丢失风格。**采用混合方案**：

#### 方案: 混合架构

```
ResourceBar (Control) [PRESET_TOP_WIDE]
├── Script: resource_bar.gd
├── custom_minimum_size.y = 52
│
├── Background (Control)                   # 保留 _draw() 绘制纸条背景
│   └── 绘制: 纸条阴影、填充、撕裂边缘、胶带、笔记本线
│
├── ContentCenter (HBoxContainer)          # 居中资源显示，用 Control 节点
│   ├── anchor: CENTER_TOP
│   ├── ResourceSan (HBoxContainer)
│   │   ├── Icon (Label)                   # emoji
│   │   ├── Name (Label)                   # "理智"
│   │   └── Value (Label)                  # 数值 (动画用 Tween)
│   ├── Sep1 (VSeparator)
│   ├── ResourceOrder (HBoxContainer)
│   │   └── ...同上
│   ├── Sep2 (VSeparator)
│   ├── ResourceMoney (HBoxContainer)
│   │   └── ...同上
│   ├── Sep3 (VSeparator)
│   └── DayWeather (HBoxContainer)
│       ├── DayLabel (Label)               # "Day 3"
│       ├── WeatherIcon (Label)            # 天气 emoji
│       └── WeatherName (Label)
│
├── DarkModeContent (HBoxContainer)        # 暗面模式内容（默认隐藏）
│   ├── LayerLabel (Label)
│   ├── EnergyBar (ProgressBar)
│   ├── EnergyLabel (Label)
│   └── ExitButton (Button)               # 圆形返回按钮
│
└── DeltaTexts (Control)                   # 浮动增减文字 (保留 _draw())
    └── 绘制: "+2" / "-1" 浮动文字动画
```

**关键决策**:
- **背景装饰** (撕裂边缘、胶带) → 保留 `_draw()`，这些是纯装饰性绘制
- **资源数值显示** → 改用 Label 节点，方便调整布局
- **浮动增减文字** → 保留 `_draw()`，属于短暂动画特效
- **暗面模式** → 用 `visible` 切换两套内容

---

### 4.3 [P0] ShopPopup — 商店弹窗

**现有功能**: 全屏模态，3 张商品卡片（浮动/旋转/抖动动画），购买逻辑，刷新按钮

#### `shop_popup.tscn`

```
ShopPopup (Control) [PRESET_FULL_RECT]
├── Overlay (ColorRect)
└── CenterContainer
    └── Panel (PanelContainer)
        ├── pivot_offset: 居中
        ├── ColorBar (ColorRect)
        ├── Content (VBoxContainer)
        │   ├── Header (VBoxContainer)
        │   │   ├── TitleRow (HBoxContainer)
        │   │   │   ├── CartIcon (Label)   # 🛒
        │   │   │   └── ShopName (Label)
        │   │   └── Greeting (Label)
        │   ├── HSeparator
        │   ├── CardsRow (HBoxContainer)   # 3 张商品卡
        │   │   ├── ShopCard1 (实例化 shop_card.tscn)
        │   │   ├── ShopCard2
        │   │   └── ShopCard3
        │   └── ButtonRow (HBoxContainer)
        │       ├── RefreshButton (Button)
        │       │   └── text: "刷新 (💰3)"
        │       └── LeaveButton (Button)
        │           └── text: "离开"
        └── MoneyDisplay (Label)           # 左上角金币余额
```

#### `components/shop_card.tscn` — 商品卡子组件

```
ShopCard (PanelContainer)
├── pivot_offset: 居中
├── custom_minimum_size: Vector2(140, 200)
├── VBoxContainer
│   ├── ItemIcon (TextureRect / Label)     # 物品图标
│   ├── ItemName (Label)
│   ├── EffectDesc (Label)
│   │   └── autowrap_mode = WORD
│   └── PriceRow (HBoxContainer)
│       ├── CoinIcon (Label)              # 💰
│       └── PriceLabel (Label)
├── SoldOverlay (ColorRect)                # 已售遮罩 (默认隐藏)
│   └── SoldLabel (Label)                 # ✓ 已购买
└── HoverHint (Label)                      # "点击购买" (默认隐藏)
```

**动画处理**:
- 卡片的**呼吸浮动** (`sin(time)` 上下浮动) → 在 `_process()` 中微调 `position.y`
- 卡片的**入场旋转** → Tween 操控 `rotation`
- **购买闪光** → 叠加一个 `ColorRect` (白绿色)，Tween `modulate.a` 1→0
- **抖动** → Tween 操控 `position.x` (sine 波形可用 `tween_method`)
- **刷新动画** → 旧卡片旋转+淡出，新卡片淡入+旋转归零

---

### 4.4 [P1] TitleScreen — 标题画面

#### `screens/title_screen.tscn`

```
TitleScreen (Control) [PRESET_FULL_RECT]
├── Overlay (ColorRect)                    # 深色背景
│   └── color: Color(0.05, 0.05, 0.15, 1.0)
├── FloatingCards (Control)                # 保留 _draw() 绘制浮动卡片剪影
│   └── mouse_filter: IGNORE
├── CenterContent (VBoxContainer)
│   ├── anchor: CENTER
│   ├── GlowCircle (Control)              # 可用 _draw() 或 TextureRect 绘制光晕
│   ├── TitleLabel (Label)
│   │   ├── text: "暗面都市"
│   │   ├── 字号: 48
│   │   └── horizontal_alignment: CENTER
│   ├── SubtitleLabel (Label)
│   │   ├── text: 副标题
│   │   └── horizontal_alignment: CENTER
│   └── PromptLabel (Label)
│       ├── text: "点击或按回车开始"
│       └── horizontal_alignment: CENTER
└── (无按钮，全屏点击触发)
```

**混合策略**:
- **浮动卡片剪影** → 保留 `_draw()`，12 个小矩形的随机运动用节点太冗余
- **标题/副标题/提示** → 改用 Label 节点
- **提示呼吸动画** → `_process()` 中周期性修改 `PromptLabel.modulate.a`
- **光晕脉动** → 小型 `_draw()` 区域或 `TextureRect` + shader

---

### 4.5 [P1] GameOver — 游戏结束画面

#### `screens/game_over.tscn`

```
GameOver (Control) [PRESET_FULL_RECT]
├── visible: false
├── Overlay (ColorRect)
└── CenterContent (VBoxContainer)
    ├── anchor: CENTER
    ├── GlowCircle (Control)              # _draw() 光晕
    ├── TitleLabel (Label)                 # "任务完成" / "意识崩溃"
    ├── SubtitleLabel (Label)
    ├── StatsGrid (GridContainer)          # 统计数据
    │   ├── columns = 2
    │   ├── DaysIcon (Label) + DaysValue (Label)
    │   ├── CardsIcon (Label) + CardsValue (Label)
    │   ├── MonstersIcon (Label) + MonstersValue (Label)
    │   └── FilmIcon (Label) + FilmValue (Label)
    └── RestartButton (Button)
        └── text: "重新开始"
```

**改动要点**:
- 统计数据改用 `GridContainer`，布局自动处理
- `RestartButton` 使用标准 `Button` 节点 + `pressed` 信号，取消手动点击检测
- 胜利/失败的颜色切换 → 脚本中动态修改 `Overlay.color`, `TitleLabel.add_theme_color_override()`

---

### 4.6 [P1] HandPanel — 手牌面板

这是最复杂的模块 (~560 行)，包含日程表、谣言便签、道具工具栏、结束回合按钮。

**建议**: 拆分为**主面板 + 3 个子场景**

#### `hand_panel.tscn` — 主面板

```
HandPanel (Control) [PRESET_FULL_RECT]
├── PanelBody (PanelContainer)             # 底部滑出面板
│   ├── anchor: BOTTOM_WIDE
│   ├── StyleBox: 笔记本纸张风格 (或保留 _draw() 绘制纸张背景)
│   │
│   ├── SpineDecor (Control)               # 左侧装订装饰，保留 _draw()
│   │
│   ├── MainContent (VBoxContainer)
│   │   ├── TabBar (HBoxContainer)
│   │   │   ├── ScheduleCount (Label)      # "日程 2/4"
│   │   │   ├── Spacer (Control, h_expand)
│   │   │   ├── ClueLogButton (Button)     # "线索本" 按钮
│   │   │   ├── Spacer2 (Control, h_expand)
│   │   │   └── RumorCount (Label)         # "谣言 1/3"
│   │   │
│   │   ├── ContentArea (HBoxContainer)
│   │   │   ├── ScheduleList (VBoxContainer)
│   │   │   │   ├── ScheduleItem1 (实例化 schedule_item.tscn)
│   │   │   │   ├── ScheduleItem2
│   │   │   │   └── ...
│   │   │   └── RumorArea (Control)        # 谣言便签 — 保留 _draw()
│   │   │       └── 绘制: 旋转便签、胶带、图标
│   │   │
│   │   ├── HSeparator (虚线)
│   │   │
│   │   ├── ItemToolbar (HBoxContainer)    # 道具工具栏
│   │   │   ├── ItemSlot1 (TextureButton / Button)
│   │   │   ├── ItemSlot2
│   │   │   └── ...
│   │   │
│   │   ├── HSeparator
│   │   │
│   │   └── EndDayButton (Button)          # "结束今天"
│   │       └── text: "🌙 结束今天"
```

#### `components/schedule_item.tscn` — 日程条目子组件

```
ScheduleItem (PanelContainer)
├── HBoxContainer
│   ├── Checkbox (TextureRect / Label)     # ☐ / ☑ / ↩ emoji
│   ├── LocationIcon (Label)               # 📍 emoji
│   ├── VerbText (Label)                   # "调查 XX"
│   └── RewardBadge (Label)                # "+3 💰"
```

**混合策略**:
- **谣言便签** → 保留 `_draw()`，旋转便签+胶带装饰效果很视觉化
- **笔记本纸张背景** → 可保留 `_draw()` 绘制纸张质感 (横线、撕裂边缘)
- **日程条目、道具栏、按钮** → 改用 Control 节点
- **滑入/滑出动画** → Tween 操控 `PanelBody.position.y`

---

### 4.7 [P2] CameraButton — 相机按钮

#### `camera_button.tscn`

```
CameraButton (Control) [PRESET_FULL_RECT]
├── ViewfinderOverlay (Control)            # 取景框覆盖层，保留 _draw()
│   └── mouse_filter: IGNORE
│   └── 绘制: 四角暗角、L 形括号、扫描线、REC 指示
│
└── ButtonAnchor (Control)                 # 按钮锚定右下角
    ├── anchor: BOTTOM_RIGHT
    ├── FilmCount (Label)                  # 胶卷数量
    └── CamButton (TextureButton / Button) # 圆形相机按钮
        ├── pivot_offset: 居中
        └── CamIcon (Label)                # 📷 emoji
```

**混合策略**:
- **取景框覆盖层** → 保留 `_draw()`（扫描线、REC 指示灯等动态特效）
- **按钮本身** → 改用 Button/TextureButton，使用 `pressed` 信号
- **脉动光晕** → 可用 `_draw()` 绘制在按钮后方

---

### 4.8 [P2] DialogueOverlay — 对话覆盖层

#### `screens/dialogue_overlay.tscn`

```
DialogueOverlay (Control) [PRESET_FULL_RECT]
├── mouse_filter: IGNORE
├── Overlay (ColorRect)                    # 半透明黑色遮罩
├── PortraitArea (TextureRect)             # 角色立绘
│   ├── anchor: LEFT + VCENTER
│   └── stretch_mode: KEEP_ASPECT
└── DialogueBox (PanelContainer)           # 底部对话框
    ├── anchor: BOTTOM_WIDE
    ├── StyleBox: 笔记本纸张风格
    ├── NameTag (PanelContainer)           # 说话人名字标签
    │   ├── anchor: TOP_LEFT (超出父容器上方)
    │   └── NameLabel (Label)
    ├── DialogueText (RichTextLabel)       # 对话文字，支持打字机效果
    │   └── bbcode_enabled: true
    └── AdvanceIndicator (Label)           # ▼ 闪烁三角
```

**打字机效果**: `RichTextLabel` 有 `visible_characters` 属性，可用 Tween 逐帧增加实现打字机效果，无需手动计算字符索引。

---

### 4.9 [P2] BubbleOverlay — 气泡覆盖层

#### `screens/bubble_overlay.tscn`

```
BubbleOverlay (Control) [PRESET_FULL_RECT]
├── mouse_filter: IGNORE
└── BubbleContainer (PanelContainer)       # 气泡主体
    ├── pivot_offset: 底部中心
    ├── StyleBox: 白色圆角 + 灰色边框
    ├── BubbleText (Label)                 # 对话文字
    │   └── autowrap_mode: WORD
    └── Arrow (Control)                    # 下方三角箭头，_draw() 或用 Polygon2D
```

**位置计算**: 脚本中用 `Camera3D.unproject_position()` 将 3D 位置投影到屏幕坐标，设置 `BubbleContainer.position`。这一逻辑保持不变。

---

### 4.10 [P2] ClueLog — 线索日志

#### `clue_log.tscn`

```
ClueLog (Control) [PRESET_FULL_RECT]
├── Overlay (ColorRect)                    # 暗色遮罩
└── CenterContainer
    └── Panel (PanelContainer)
        ├── pivot_offset: 居中
        ├── VBoxContainer
        │   ├── TitleBar (HBoxContainer)
        │   │   ├── TitleLabel (Label)     # "线索本 (5/12)"
        │   │   └── CloseButton (Button)   # "✕"
        │   ├── HSeparator
        │   ├── TabBar (HBoxContainer)     # 分类标签
        │   │   ├── Tab1 (Button)
        │   │   ├── Tab2 (Button)
        │   │   └── ...
        │   ├── HSeparator
        │   └── ScrollContainer             # 可滚动区域
        │       └── ClueList (VBoxContainer)
        │           ├── ClueItem1 (实例化 clue_item.tscn)
        │           ├── ClueItem2
        │           └── ...
        └── EmptyState (VBoxContainer)     # 空状态 (默认隐藏)
            ├── EmptyIcon (Label)           # 📭
            └── EmptyText (Label)
```

#### `components/clue_item.tscn`

```
ClueItem (PanelContainer)
├── HBoxContainer
│   ├── ClueIcon (Label)                   # emoji
│   ├── VBoxContainer
│   │   ├── ClueName (Label)
│   │   └── ClueDesc (Label)
│   │       └── autowrap_mode: WORD
```

**改动要点**:
- 滚动改用 Godot 原生 `ScrollContainer`，取消手动 `_gui_input` 滚轮处理
- 分类标签用 `Button` 组（或 `TabBar`），取消手动点击测试
- 关闭按钮用 `Button.pressed` 信号

---

## 五、main.tscn 重构

### 5.1 现状

`main.tscn` 只有一个空 Node3D + 脚本引用。所有节点在 `_setup_scene_tree()` 中代码创建。

### 5.2 目标

将 `main.tscn` 扩展为完整的场景树，各 UI 子场景通过实例化 (instance) 引入：

```
Main (Node3D)
├── Script: main.gd
│
├── CameraPivot (Node3D)
│   └── MainCamera (Camera3D)
│       └── fov: 50, 45 度俯视
├── SunLight (DirectionalLight3D)
├── WorldEnv (WorldEnvironment)
├── BoardLayer (Node3D)
├── BoardVisual (Node3D, board_visual.gd)
├── TableSurface (MeshInstance3D)
├── TokenSprite (Sprite3D)
├── TokenShadow (MeshInstance3D)
│
├── UILayer (CanvasLayer, layer=10)
│   ├── ResourceBar     ← 实例化 ui/resource_bar.tscn
│   ├── HandPanel        ← 实例化 ui/hand_panel.tscn
│   ├── ClueLog          ← 实例化 ui/clue_log.tscn
│   ├── CameraButton     ← 实例化 ui/camera_button.tscn
│   ├── EventPopup       ← 实例化 ui/event_popup.tscn
│   ├── PhotoPopup       ← 实例化 ui/photo_popup.tscn    [新增]
│   ├── RiftPopup        ← 实例化 ui/rift_popup.tscn     [新增]
│   ├── ShopPopup        ← 实例化 ui/shop_popup.tscn
│   ├── GameOver         ← 实例化 screens/game_over.tscn
│   ├── DateTransition   (保留代码创建，不改)
│   ├── BubbleOverlay    ← 实例化 screens/bubble_overlay.tscn
│   ├── DialogueOverlay  ← 实例化 screens/dialogue_overlay.tscn
│   └── TitleScreen      ← 实例化 screens/title_screen.tscn
│
└── VFXLayer (CanvasLayer, layer=100)
    └── VFX (保留代码创建，不改)
```

### 5.3 main.gd 改造

`_setup_scene_tree()` 大幅简化：

```gdscript
# 旧方式 (~200 行代码创建所有节点)
func _setup_scene_tree():
    var ui_layer = CanvasLayer.new()
    ui_layer.layer = 10
    add_child(ui_layer)
    
    _event_popup = load("res://scripts/ui/event_popup.gd").new()
    _event_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
    ui_layer.add_child(_event_popup)
    # ... 重复 12 次

# 新方式 (~30 行，获取已存在的场景实例引用)
func _ready():
    _event_popup = $UILayer/EventPopup
    _photo_popup = $UILayer/PhotoPopup
    _rift_popup = $UILayer/RiftPopup
    _resource_bar = $UILayer/ResourceBar
    _hand_panel = $UILayer/HandPanel
    # ...
    _connect_signals()
    _start_game()
```

**信号连接** `_connect_signals()` 保持不变，只是引用方式从局部变量改为 `$` 路径。

---

## 六、实施路线

### Phase 0: 基础设施 (前置)

1. **创建 `themes/game_theme.tres`** — 将 `theme.gd` 中的颜色/字号转为 Godot Theme 资源
2. **创建目录结构** — `scenes/ui/`, `scenes/screens/`, `scenes/ui/components/`
3. **建立公共 StyleBox** — PanelModal, PanelNotebook, ButtonPrimary 等

### Phase 1: P0 模块 (核心交互)

> 这些模块使用频率最高，影响核心游戏循环。

1. **EventPopup** → 拆分为 3 个独立场景 + Toast 子组件
   - 建议先做 rift_popup (最简单，有 2 个按钮)
   - 再做 event_popup (模态弹窗)
   - 最后做 photo_popup (拍立得风格)
   - Toast 系统可后置

2. **ResourceBar** → 混合架构，背景保留 `_draw()`，数值改用 Label
3. **ShopPopup** → 完整 Scene 化 + shop_card 子组件

### Phase 2: P1 模块 (核心流程)

4. **TitleScreen** → Scene 化，浮动卡片保留 `_draw()`
5. **GameOver** → 完整 Scene 化
6. **HandPanel** → 拆分为主面板 + schedule_item 子组件，谣言保留 `_draw()`

### Phase 3: P2 模块 (辅助 UI)

7. **DialogueOverlay** → Scene 化，利用 RichTextLabel 打字机效果
8. **BubbleOverlay** → Scene 化
9. **ClueLog** → Scene 化 + clue_item 子组件 + ScrollContainer
10. **CameraButton** → 混合架构，取景框保留 `_draw()`

### Phase 4: 整合

11. **重构 main.tscn** — 将所有 UI 场景实例化到主场景树中
12. **简化 main.gd** — 删除 `_setup_scene_tree()` 中的代码创建逻辑
13. **全面测试** — 确保信号连接、动画、输入处理全部正常
14. **清理** — 删除废弃的 `_draw()` 代码和手动布局计算

---

## 七、迁移注意事项

### 7.1 每个模块的迁移步骤

```
1. 创建 .tscn 场景文件，搭建节点树
2. 重写 .gd 脚本：
   a. 删除 _draw() 函数
   b. 删除手动布局计算 (位置、尺寸)
   c. 删除手动 _has_point() 点击测试
   d. 将动画改为 Tween 操控节点属性
   e. 将手动文字渲染改为 Label 节点赋值
   f. 保留业务逻辑和信号定义
3. 更新 main.gd 中的引用方式
4. 测试该模块的所有交互路径
```

### 7.2 保留 `_draw()` 的合理场景

以下情况**允许在 Scene 化模块中保留局部 `_draw()`**：

| 场景 | 例子 | 原因 |
|------|------|------|
| 装饰性纹理 | 笔记本横线、撕裂边缘、胶带 | 纯视觉装饰，用 Control 节点过于冗余 |
| 动态粒子/特效 | 浮动文字、扫描线、光晕脉动 | 短暂、动态、无交互 |
| 大量随机元素 | 12 个浮动卡片剪影 | 用 12 个节点管理反而更复杂 |

**规则**: `_draw()` 只用于**非交互的视觉装饰**，所有**可交互元素必须是节点**。

### 7.3 信号兼容性

所有模块的**对外信号接口保持不变**，确保 `main.gd` 中 `_connect_signals()` 不受影响。新增的子场景 (如 `rift_popup.tscn`) 需要把信号冒泡到父级。

### 7.4 输入处理迁移

| 旧方式 | 新方式 |
|--------|--------|
| `_gui_input()` + 手动矩形检测 | `Button.pressed` 信号 |
| `_has_point()` 覆盖 | 依赖节点层级的自然点击穿透 |
| `_input()` 追踪鼠标位置 | `mouse_entered` / `mouse_exited` 信号 |
| 手动 hover 状态 + 插值 | `Button` 主题的 hover StyleBox，或 `mouse_entered` + Tween |

---

## 八、验收标准

每个模块完成后的检查清单：

- [ ] 有独立的 .tscn 场景文件
- [ ] 在 Godot 编辑器中可以打开并看到正确的节点树
- [ ] 所有可交互元素（按钮、列表项）是 Control 节点，不是 `_draw()` 绘制
- [ ] 动画效果与旧版视觉一致
- [ ] 信号接口与旧版兼容，main.gd 无需修改信号连接
- [ ] 保留的 `_draw()` 仅用于非交互装饰
- [ ] 在不同窗口尺寸下布局正确（锚点和容器设置正确）
