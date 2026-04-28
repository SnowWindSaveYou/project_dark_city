# 暗面都市 — Lua→Godot 移植审计报告

> **审计日期**: 2026-04-28  
> **审计范围**: UrhoX/Lua 全部游戏模块 vs Godot 4.x/GDScript 对应实现  
> **审计方法**: 逐文件对比，按功能点逐项核实代码实现

---

## 执行摘要

| 指标 | 数值 |
|------|------|
| **审计功能点总数** | 78 |
| **完全实现** | 49 (63%) |
| **部分实现** | 16 (20%) |
| **完全缺失** | 13 (17%) |
| **总体移植完成度** | ~75% |

**核心发现**: 游戏流程、卡牌系统、棋盘生成、暗面世界逻辑层全部完整移植。**主要缺失集中在 3D 视觉渲染层** — 暗面 NPC/幽灵/怪物 chibi 的 3D 节点从未创建，地图道具无 3D 可视化，Token 阴影缺失。

---

## 1. 关键缺失（必须修复）

### 1.1 暗面幽灵 3D 渲染 — 完全缺失

| 项目 | 说明 |
|------|------|
| **Lua** | `DarkWorld.lua:335-373` — `createGhostNodes()` 为每个幽灵创建 BillboardSet 节点，尺寸 0.30×0.30m，位置 Y=0.25m，DiffAlpha 材质，透明度动画 |
| **Godot** | `dark_world.gd` 仅有 `GhostData` 数据类（row, col, alive, tex_index, alpha, float_phase），**无任何 3D 节点创建代码** |
| **影响** | 玩家进入暗面后看不到幽灵，但幽灵碰撞逻辑正常执行 → 隐形伤害 |

**缺失细项**:
- [ ] 幽灵 Sprite3D/Billboard 节点创建
- [ ] 幽灵移动平滑动画（Tween 位置插值）
- [ ] 幽灵浮动呼吸动画（sin 波 Y 偏移）
- [ ] 幽灵被消灭时淡出动画（alpha 1→0, 0.5s）
- [ ] 幽灵节点销毁

### 1.2 暗面 NPC 3D 渲染 — 完全缺失

| 项目 | 说明 |
|------|------|
| **Lua** | `DarkWorld.lua:375-410` — `createNPCNodes()` 为每个 NPC 创建 BillboardSet，尺寸 0.35×0.35m，偏移 X+0.15m，Y=0.25m |
| **Godot** | `dark_world.gd` 有 `DarkNPCData` 数据类（id, npc_name, row, col, tex_path, dialogue），`npc_manager.gd` 有 `spawn_npc()/remove_npc()` 但**仅管理数据，无 3D 节点** |
| **影响** | 暗面 NPC 不可见，但对话触发逻辑正常 → 玩家踩到空格子触发对话，体验割裂 |

**缺失细项**:
- [ ] NPC Sprite3D/Billboard 节点创建
- [ ] NPC 呼吸动画（scale = 1.0 + sin(time*2.0) * 0.02）
- [ ] NPC 对话时表情切换

### 1.3 怪物 Chibi（MonsterGhost）— 类存在但从未实例化

| 项目 | 说明 |
|------|------|
| **Lua** | `MonsterGhost.lua` — 完整的怪物 chibi 系统：踩怪时环绕玩家（5 个位置布局），拍照后显示在卡牌上，侦察卡显示踪迹箭头 |
| **Godot** | `visual/monster_ghost.gd` — 完整的 `MonsterGhost` 类已移植（GhostSprite 数据、spawn_around_player、show_on_scouted_cards、calculate_trail），但 **main.gd 从未实例化此类，也从未调用任何方法** |
| **影响** | 踩到怪物卡没有 chibi 环绕特效，侦察卡没有踪迹提示，拍照后卡牌上没有怪物图标 |

**缺失细项**:
- [ ] main.gd 中实例化 MonsterGhost
- [ ] 翻牌为怪物时调用 `spawn_around_player()`
- [ ] 侦察时调用 `show_on_scouted_cards()`
- [ ] 拍照时调用 `show_on_card()`
- [ ] 每帧调用 `update()` + 渲染（_draw 或 Sprite3D）
- [ ] 浮动/摇摆动画（sin 波 X/Y 偏移）
- [ ] 淡入/淡出 Tween 动画

### 1.4 地图道具 3D 可视化 — 完全缺失

| 项目 | 说明 |
|------|------|
| **Lua** | `BoardItems.lua:77-115` — `createItemBillboard()` 为每个道具创建 BillboardSet 节点，尺寸 0.22m，基础高度 Y=0.35m，金色光晕底座（Cylinder），DiffAlpha 材质 |
| **Godot** | `board_items.gd` 有完整数据逻辑（ITEM_POOL, spawn_daily, try_collect），`game_flow.gd` 正确触发拾取效果，但**无任何 3D 节点渲染代码** |
| **影响** | 道具在地图上不可见，玩家无法主动发现道具 → 只在踩到时弹出拾取提示 |

**缺失细项**:
- [ ] 道具 Sprite3D/Billboard 节点创建（带纹理）
- [ ] 道具浮动动画（sin(time*2.2 + phase) * 0.025m）
- [ ] 金色光晕底座（Cylinder + 呼吸 alpha）
- [ ] 道具出现动画（scale 0→1, easeOutBack, 0.4s）
- [ ] 道具拾取动画（光晕脉冲 → 图标上浮 + 旋转 + 缩放曲线 → 淡出）
- [ ] 道具已拾取后节点清除

### 1.5 Token 阴影 — 完全缺失

| 项目 | 说明 |
|------|------|
| **Lua** | `Token.lua:107-122` — Cylinder 网格作为 blob shadow，Y=0.015m，缩放 `(W*1.1, 0.001, W*0.5)`，黑色 alpha=0.3 |
| **Godot** | main.gd / board_visual.gd — **无阴影节点** |
| **影响** | Token 缺少地面参照，空间感减弱 |

---

## 2. 部分实现（需要补全）

### 2.1 Token 系统

| 功能 | Lua 实现 | Godot 状态 | 差异 |
|------|---------|-----------|------|
| **死亡精灵尺寸** | `DEAD_3D_W=0.57m, DEAD_3D_H=0.38m`（横向倒地） | 常量存在(`DEAD_W=96, DEAD_H=64`)但**未在渲染时切换尺寸** | `board_visual.gd:update_token_visual()` 未根据 emotion=="dead" 切换 sprite 比例 |
| **呼吸缩放** | `breatheScale = 1.0 + sin(time*2.5) * 0.02`，应用于 billboard.size | Y 偏移已实现，但 **scale 缩放未应用到 Sprite3D.scale** | 只有 Y 浮动，没有「呼吸」视觉效果 |
| **情绪翻转动画** | `squashX 1→0`时切换纹理，`0→1`展开 | squash_x 属性存在，但**纹理切换不在 squashX=0 时机执行** | 情绪切换无翻转动画，纹理直接替换 |
| **hop()** | 小幅弹跳（h=0.05m, 100ms+150ms） | `token.gd` 有 `hop(h)` 方法定义，但**调用点不完整** | 部分场景（如幽灵碰撞）缺少 hop 调用 |

### 2.2 卡牌系统

| 功能 | Lua 实现 | Godot 状态 | 差异 |
|------|---------|-----------|------|
| **悬停高亮** | `hoverT` 0→1 插值，scale 增大 1.08 倍 | **无 hover 视觉反馈** | 鼠标悬停卡牌无视觉提示 |
| **侦察/揭示图标** | `scoutedNode`/`revealedNode` — 卡牌右上角小图标 | `card.scouted=true` 数据存在，**无 3D 图标渲染** | 侦察状态无视觉标记 |
| **无效操作震动** | 0.35s, 6Hz 正弦震动衰减 | **完全缺失** | 无法操作时无反馈 |
| **驱魔变形动画** | 70° 旋转 + 震动 + 光晕脉冲 | 仅 scale 缩放动画（simpler） | 视觉冲击力不足 |
| **安全光晕开关** | `showSafeGlow()/hideSafeGlow()` 显式控制 | 自动挂载，**无关闭逻辑** | 某些场景光晕应消失但不会 |

### 2.3 暗面世界

| 功能 | Lua 实现 | Godot 状态 | 差异 |
|------|---------|-----------|------|
| **进出过渡动画** | 屏幕淡入淡出 + 状态机切换 | 状态机存在，**无视觉过渡 Tween** | 切换过于突兀 |
| **棋盘节点显隐** | `hideAllNodes()/showAllNodes()` | **无显式 API** | 可能通过 main.gd visibility 间接处理 |

### 2.4 相机

| 功能 | Lua 实现 | Godot 状态 | 差异 |
|------|---------|-----------|------|
| **FOV** | 45° | 50° | 视野宽度差异约 5% |
| **滚轮缩放** | 推测实现 | **未确认** | 需要验证 |

---

## 3. 完全实现（无需修改）

以下功能已完整移植，逻辑和参数均匹配：

### 3.1 棋盘系统
- 5×5 网格布局 + 世界坐标映射
- 卡牌类型分布权重（safe:30, monster:20, trap:15, reward:15, plot:10, clue:10）
- 地标放置 + 光环净化（4 方向相邻 monster/trap → safe）
- 家卡放置 + 排斥规则
- 螺旋序遍历（发牌/收牌动画顺序）
- 暗面墙壁生成 + BFS 连通性验证
- 暗面卡牌类型分配
- 射线-平面碰撞检测（3D 拾取）
- 陷阱子类型权重（sanity:30, money:30, film:20, teleport:20）

### 3.2 卡牌动画
- 发牌动画（4 阶段：alpha 淡入 + 位置飞入 + 缩放展开 + 弹跳落地）
- 收牌动画（弹起 + 飞回牌堆 + 缩小 + 旋转 + 淡出）
- 翻牌动画（下压蓄力 → 弹起 → 旋转 90° → 换面 → 翻回 → 落地）
- 翻回动画（反向翻牌）
- 卡牌类型颜色/图标（8 普通位置 + 3 地标 + 6 事件类型）
- 地标/家光晕粒子（GPUParticles3D，功能等价）

### 3.3 Token 系统
- Sprite3D Billboard 创建（pixel_size=0.00065）
- 移动弹跳动画（抛物线弧 + easing）
- 位置同步（grid→world + Y 偏移）
- 15 种情绪纹理映射
- squash_x/y 压扁拉伸属性

### 3.4 游戏流程
- 完整状态机（setup → deal → play → undeal → next_day）
- 日程推进（settle → check_defeat → undeal → date_transition → deal）
- 胜利条件（day_count ≥ 24 + SAN > 0 + Order > 0）
- 失败条件（SAN ≤ 0 或 Order ≤ 0）
- 道具拾取效果应用（coffee/film/shield/exorcism/mapReveal）

### 3.5 暗面世界逻辑
- 3 层系统（L0/L1/L2）+ 解锁日期
- 幽灵数据生成（GHOST_COUNT = [2, 3, 2]）
- 幽灵 AI 移动（Manhattan 距离 ≤ 2 追逐, > 2 随机）
- 幽灵碰撞检测 + SAN 伤害
- NPC 数据生成 + 对话触发
- 能量消耗系统
- 拍照驱魔逻辑

### 3.6 事件系统
- 陷阱处理（护盾检查 → 子类型效果 → Toast 通知）
- 资源变化（SAN/Order/Money/Film）
- 传送陷阱
- 事件弹窗

### 3.7 视觉效果
- 氛围过渡（明→暗：背景色、环境光、雾气密度插值）
- 屏幕闪烁（screen_flash）
- 屏幕震动（screen_shake）
- 横幅提示（action_banner）
- VFX 爆发粒子

### 3.8 UI 系统
- 资源条（SAN/Order/Money/Film）
- 对话系统（状态机 + 打字机效果）
- 结束画面（胜利/失败 + 统计数据）

---

## 4. 待确认项目

以下功能因审计覆盖范围限制，未能完全确认：

| 功能 | Lua 文件 | Godot 文件 | 状态 |
|------|---------|-----------|------|
| 音效/BGM | 未定位 | 未定位 | 需补充审查 |
| 存档系统 | 未定位 | `game_data.gd` 推测 | 需确认 |
| 教程系统 | 未定位 | 未定位 | 可能为可选功能 |
| 暂停菜单 | 推测存在 | 推测存在 | 需确认 |
| 手牌面板 | `HandPanel.lua` | `ui/hand_panel.gd` | 文件存在未审查 |
| 商店界面 | `ShopPopup.lua` | `ui/shop_popup.gd` | 文件存在未审查 |
| 气泡对话 | `BubbleDialogue.lua` | `ui/bubble_overlay.gd` | 文件存在未审查 |
| 日期过渡 | `DateTransition.lua` | `ui/date_transition.gd` | 文件存在未审查 |

---

## 5. 修复优先级

### P0 — 功能性缺失（游戏体验严重受损）

| 编号 | 缺失项 | 预估工作量 | 依赖 |
|------|--------|-----------|------|
| P0-1 | 暗面幽灵 3D 渲染 + 动画 | 中 | dark_world.gd GhostData |
| P0-2 | 暗面 NPC 3D 渲染 + 呼吸 | 小 | dark_world.gd DarkNPCData |
| P0-3 | 地图道具 3D 可视化 + 浮动 + 拾取动画 | 中 | board_items.gd |
| P0-4 | MonsterGhost 集成（实例化 + 调用） | 中 | monster_ghost.gd |

### P1 — 视觉完整性

| 编号 | 缺失项 | 预估工作量 | 依赖 |
|------|--------|-----------|------|
| P1-1 | Token blob shadow | 小 | main.gd |
| P1-2 | Token 死亡精灵横向尺寸切换 | 小 | board_visual.gd |
| P1-3 | Token 呼吸缩放 | 小 | board_visual.gd |
| P1-4 | Token 情绪翻转动画（squashX=0 时换纹理） | 小 | board_visual.gd |
| P1-5 | 卡牌侦察/揭示图标 | 小 | board_visual.gd |
| P1-6 | 暗面进出过渡动画 | 小 | dark_world_flow.gd |

### P2 — 体验优化

| 编号 | 缺失项 | 预估工作量 | 依赖 |
|------|--------|-----------|------|
| P2-1 | 卡牌悬停高亮 | 小 | board_visual.gd |
| P2-2 | 无效操作震动反馈 | 小 | board_visual.gd |
| P2-3 | 驱魔变形旋转增强 | 小 | board_visual.gd |
| P2-4 | FOV 修正（50° → 45°） | 极小 | main.gd |
| P2-5 | 安全光晕显式开关 | 极小 | board_visual.gd |

---

## 6. 技术栈对比

| 维度 | Lua/UrhoX | Godot/GDScript |
|------|-----------|----------------|
| 3D 精灵 | BillboardSet + Billboard | Sprite3D (billboard mode) |
| 粒子 | CPU 自定义环形动画 | GPUParticles3D (更高效) |
| UI | NanoVG 矢量绘制 | CanvasLayer + Control 节点 |
| 动画 | 自定义 lib.Tween | Godot 内置 Tween |
| 材质 | DiffAlpha / PBRNoTexture | StandardMaterial3D |
| 碰撞检测 | 射线-平面手算 | Camera3D.project_ray + 手算 |
| 2D 覆盖 | NanoVG 直接绘制 | CanvasLayer + _draw() |

---

## 附录 A: 文件对应关系

| Lua 模块 | Godot 文件 | 移植状态 |
|---------|-----------|---------|
| `main.lua` | `main.gd` | 完成（场景/相机/循环） |
| `Token.lua` | `core/token.gd` + `controllers/board_visual.gd` | 部分（缺阴影/死亡尺寸/呼吸缩放） |
| `Card.lua` | `core/card.gd` + `controllers/board_visual.gd` | 大部分（缺 hover/scout 图标） |
| `Board.lua` | `core/board.gd` | 完成 |
| `GameFlow.lua` | `controllers/game_flow.gd` | 完成 |
| `DarkWorld.lua` | `core/dark_world.gd` + `controllers/dark_world_flow.gd` | 逻辑完成，**渲染缺失** |
| `MonsterGhost.lua` | `visual/monster_ghost.gd` | 类已移植，**未集成** |
| `BoardItems.lua` | `core/board_items.gd` + `controllers/game_flow.gd` | 逻辑完成，**渲染缺失** |
| `Camera.lua` | `main.gd` (内嵌) | 完成 |
| `ResourceBar.lua` | `ui/resource_bar.gd` | 完成 |
| `DialogueSystem.lua` | `dialogue_system.gd` | 完成 |
| `EventPopup.lua` | `ui/event_popup.gd` | 推测完成 |
| `CardTextures.lua` | `card_textures.gd` | 推测完成 |
| `GameOver.lua` | `ui/game_over.gd` | 完成 |

---

*报告结束*
