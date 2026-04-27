# Godot 迁移计划 - 暗面都市 v2 更新

> main 分支 7 次提交，+6,607 行 / 20 文件变更 → godot_dev 同步

---

## 基线状态

| 维度 | Lua (最新 main) | Godot (当前 godot_dev) |
|------|----------------|----------------------|
| 总模块数 | 24 个 .lua | 18 个 .gd |
| 总代码量 | ~15,656 行 | ~4,563 行 |
| 缺失模块 | - | 7 个新增模块未移植 |
| 已有模块落后 | - | 13 个模块需更新 |

### Godot 已有 vs Lua 行数对比（落后幅度）

| 模块 | Lua 行数 | Godot 行数 | 差距 | 说明 |
|------|---------|-----------|------|------|
| main | 2345 | 888 | +1457 | 暗面世界集成、NPC、裂隙、道具 |
| EventPopup | 1634 | 187 | +1447 | Toast 系统、裂隙弹窗、陷阱子类型 |
| Board | 857 | 260 | +597 | 暗面地图生成、BFS墙壁、陷阱子类型 |
| Card | 928 | 220 | +708 | 安全光晕、暗面卡牌、材质优化 |
| ResourceBar | 693 | 148 | +545 | 暗面模式 UI |
| HandPanel | 1016 | 274 | +742 | 传闻翻页、便签堆叠 |
| ShopPopup | 1083 | 284 | +799 | 道具图标 |
| Theme | 264 | 95 | +169 | 暗面颜色、暗面卡牌类型 |
| CardManager | 424 | 187 | +237 | 地标安全、惩罚调整 |
| CameraButton | 540 | 172 | +368 | 胶卷纹理图标 |

---

## 迁移阶段划分

### Phase 0: 数据层扩展（无 UI，纯逻辑）
> 目标：让 Board/Card/Theme/GameData 的数据结构完整，后续模块可编译

| # | 任务 | 涉及文件 | 预计行数 |
|---|------|---------|---------|
| 0.1 | Theme 新增暗面颜色 + 裂隙/暗面卡牌类型 | `theme.gd` | +50 |
| 0.2 | Card 新增暗面字段 (isDark, darkType, darkName, trapSubtype, hasRift) | `card.gd` | +40 |
| 0.3 | Board 新增暗面地图生成 + 陷阱子类型 + 裂隙卡 + BFS 墙壁 | `board.gd` | +200 |
| 0.4 | CardManager 修正地标安全判定 + 惩罚 -3 | `card_manager.gd` | +5 |
| 0.5 | GameData 确认道具/资源字段完备 | `game_data.gd` | +10 |

**验收**：Board.generate_dark_cards() 可调用，Card 暗面字段可读写。

---

### Phase 1: 新增独立模块（不依赖 main 状态机）
> 目标：7 个新模块各自可实例化，接口齐全

| # | 任务 | 新建文件 | 依赖 | 预计行数 |
|---|------|---------|------|---------|
| 1.1 | ItemIcons - 道具图标资源字典 | `scripts/lib/item_icons.gd` | 无 | ~60 |
| 1.2 | BoardItems - 棋盘可拾取道具 | `scripts/core/board_items.gd` | ItemIcons, Board | ~150 |
| 1.3 | MonsterGhost - 怪物精灵弹出 | `scripts/visual/monster_ghost.gd` | Board | ~180 |
| 1.4 | BubbleDialogue - 气泡对话 | `scripts/ui/bubble_dialogue.gd` | 无 | ~160 |
| 1.5 | NPCManager - NPC 管理 | `scripts/core/npc_manager.gd` | Board | ~140 |
| 1.6 | DialogueSystem - 打字机对话 | `scripts/ui/dialogue_system.gd` | 无 | ~200 |
| 1.7 | DarkWorld - 暗面世界状态机 | `scripts/core/dark_world.gd` | Board, Card, Token | ~350 |

**验收**：每个模块可独立实例化，公开方法签名与 Lua 版本一致。

---

### Phase 2: 已有模块更新（UI / 交互层）
> 目标：补齐已有 .gd 文件缺失的功能

| # | 任务 | 涉及文件 | 核心新增内容 |
|---|------|---------|-------------|
| 2.1 | EventPopup 大扩展 | `event_popup.gd` | Toast 通知系统 + 裂隙确认弹窗 + 陷阱子类型模板 |
| 2.2 | ResourceBar 暗面模式 | `resource_bar.gd` | 暗面 UI 切换 + 能量条 + 返回按钮 |
| 2.3 | HandPanel 传闻翻页 | `hand_panel.gd` | 传闻分页 + 便签堆叠 + 道具纹理 |
| 2.4 | ShopPopup 图标升级 | `shop_popup.gd` | 商品 iconKey + 纹理图标渲染 |
| 2.5 | CameraButton 图标 | `camera_button.gd` | 胶卷纹理图标 |
| 2.6 | Card 光晕系统 | `card.gd` (追加) | 安全区光环绘制 |

**验收**：EventPopup.show_toast() / show_rift_confirm() 可调用，ResourceBar 可切换暗面模式。

---

### Phase 3: 主入口集成（状态机扩展）
> 目标：main.gd 整合所有新模块，完成暗面世界游戏循环

| # | 任务 | 涉及文件 | 核心新增内容 |
|---|------|---------|-------------|
| 3.1 | main.gd 新模块初始化 | `main.gd` | 初始化 7 个新模块 + 连接信号 |
| 3.2 | 暗面世界进出流程 | `main.gd` | enter_dark_world / exit_dark_world / change_layer |
| 3.3 | NPC 对话集成 | `main.gd` | 琴馨对话脚本 + 同格检测 + 气泡投影 |
| 3.4 | 裂隙确认流程 | `main.gd` | pending_rift → 弹窗 → 进入暗面 |
| 3.5 | 道具拾取 + 日程惩罚 | `main.gd` | BoardItems.try_collect + settle_day 反馈 |
| 3.6 | 安全光晕激活 | `main.gd` | 发牌完成后显示 home/landmark 光环 |
| 3.7 | 输入路由扩展 | `main.gd` | DialogueSystem/RiftConfirm/Toast/DarkWorld 优先级 |
| 3.8 | 渲染层整合 | `main.gd` | 暗面 HUD + 气泡投影 + Toast + 对话系统 |

**验收**：可从现实棋盘 → 踩裂隙 → 确认 → 进入暗面 → 探索 → 返回现实。

---

## 依赖拓扑（执行顺序约束）

```
Phase 0 (数据层)
  ├── 0.1 Theme           ← 无依赖
  ├── 0.2 Card            ← 0.1
  ├── 0.3 Board           ← 0.2
  ├── 0.4 CardManager     ← 无依赖
  └── 0.5 GameData        ← 无依赖

Phase 1 (新模块)
  ├── 1.1 ItemIcons       ← 无依赖
  ├── 1.2 BoardItems      ← 1.1, 0.3
  ├── 1.3 MonsterGhost    ← 0.3
  ├── 1.4 BubbleDialogue  ← 无依赖
  ├── 1.5 NPCManager      ← 0.3
  ├── 1.6 DialogueSystem  ← 无依赖
  └── 1.7 DarkWorld       ← 0.1, 0.2, 0.3

Phase 2 (更新模块)  ← 全部依赖 Phase 0
  ├── 2.1 EventPopup      ← 0.2
  ├── 2.2 ResourceBar     ← 0.1
  ├── 2.3 HandPanel       ← 1.1
  ├── 2.4 ShopPopup       ← 1.1
  ├── 2.5 CameraButton    ← 1.1
  └── 2.6 Card 光晕       ← 0.2

Phase 3 (集成)      ← 依赖 Phase 1 + 2 全部完成
  └── 3.1~3.8 main.gd    ← 全部
```

**可并行**：Phase 1 和 Phase 2 大部分任务互不依赖，可交叉执行。

---

## 技术映射规则

### Lua → GDScript 模式对照

| Lua 模式 | Godot 等价 |
|----------|-----------|
| `NanoVG nvgXxx()` 绘制 | `_draw()` + `draw_xxx()` API |
| `lib.Tween` 动画 | `create_tween()` 内置 Tween |
| `lib.VFX.screenFlash/shake` | VFXManager (已有) |
| `Billboard + BillboardSet` | `Sprite2D` (2D 项目) |
| `nvgCreateImage()` 纹理 | `preload()` / `load()` Texture2D |
| `Module.init(scene)` | `_ready()` 或 `func setup()` |
| `Module.update(dt)` | `_process(delta)` 或由 main 调用 |
| `Module.draw(vg, w, h)` | `_draw()` + `queue_redraw()` |
| `SubscribeToEvent("MouseButtonDown")` | `_unhandled_input(event)` |
| `cache:GetResource("Texture2D", path)` | `load("res://..." )` |

### 命名约定

| Lua | GDScript |
|-----|----------|
| `M.spawnDaily(board, Board)` | `func spawn_daily(board: Board) -> void` |
| `M.tryCollect(row, col)` | `func try_collect(row: int, col: int) -> Dictionary` |
| `M.isActive()` | `func is_active() -> bool` |
| `darkCardTypes` | `DARK_CARD_TYPES` (常量) |
| `darkBgTop` | `dark_bg_top` (变量) |

---

## 文件清单（最终目标）

```
godot/scripts/
├── autoload/
│   ├── theme.gd              # 更新 (Phase 0.1)
│   └── game_data.gd          # 更新 (Phase 0.5)
├── core/
│   ├── board.gd              # 更新 (Phase 0.3)
│   ├── board_items.gd        # 新建 (Phase 1.2)
│   ├── card.gd               # 更新 (Phase 0.2 + 2.6)
│   ├── card_manager.gd       # 更新 (Phase 0.4)
│   ├── dark_world.gd         # 新建 (Phase 1.7)
│   ├── npc_manager.gd        # 新建 (Phase 1.5)
│   ├── shop_data.gd          # 不变
│   ├── token.gd              # 不变
│   └── weather.gd            # 不变
├── lib/
│   ├── item_icons.gd         # 新建 (Phase 1.1)
│   └── vfx_manager.gd        # 不变
├── ui/
│   ├── bubble_dialogue.gd    # 新建 (Phase 1.4)
│   ├── camera_button.gd      # 更新 (Phase 2.5)
│   ├── dialogue_system.gd    # 新建 (Phase 1.6)
│   ├── event_popup.gd        # 更新 (Phase 2.1)
│   ├── hand_panel.gd         # 更新 (Phase 2.3)
│   ├── resource_bar.gd       # 更新 (Phase 2.2)
│   └── shop_popup.gd         # 更新 (Phase 2.4)
├── visual/
│   ├── date_transition.gd    # 不变
│   ├── game_over.gd          # 不变
│   ├── monster_ghost.gd      # 新建 (Phase 1.3)
│   └── title_screen.gd       # 不变
└── main.gd                   # 更新 (Phase 3)
```

新建 7 文件 + 更新 11 文件 = 18 个文件变更

---

## 执行检查清单

- [ ] **Phase 0**: Theme → Card → Board → CardManager → GameData
- [ ] **Phase 1**: ItemIcons → BoardItems → MonsterGhost → BubbleDialogue → NPCManager → DialogueSystem → DarkWorld
- [ ] **Phase 2**: EventPopup → ResourceBar → HandPanel → ShopPopup → CameraButton → Card 光晕
- [ ] **Phase 3**: main.gd 集成全部新模块
- [ ] **验收**: 完整游戏循环可运行（现实 → 裂隙 → 暗面 → 返回）
