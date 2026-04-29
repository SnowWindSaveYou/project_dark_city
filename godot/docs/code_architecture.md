# Dark City - Godot 卡牌桌游项目

## 项目概述

**Dark City** 是一个基于 Godot 4.x 开发的卡牌桌游项目，采用 2D 俯视角棋盘 + 卡牌战斗机制。游戏融合了 Roguelike 探索（暗世界 Dark World）与卡牌战斗系统。

---

## 项目架构

```
scripts/
├── autoload/          # 自动加载的单例 (全局状态)
│   ├── card_config.gd     # 卡牌配置管理
│   ├── game_data.gd       # 游戏存档/运行时数据
│   ├── story_manager.gd   # 故事/剧情管理
│   └── theme.gd           # 主题/配色管理
├── controllers/       # 游戏控制器 (逻辑层)
│   ├── board_visual.gd    # 棋盘视觉渲染
│   ├── card_interaction.gd # 卡牌交互逻辑
│   ├── game_flow.gd       # 游戏主流程
│   └── dark_world_flow.gd # 暗世界探索流程
├── core/             # 核心数据模型
│   ├── board.gd          # 棋盘逻辑
│   ├── board_items.gd    # 棋盘物品
│   ├── card.gd           # 卡牌数据
│   ├── card_manager.gd   # 卡牌管理
│   ├── dark_world.gd     # 暗世界核心 (主状态机)
│   ├── npc_manager.gd    # NPC管理
│   ├── shop_data.gd      # 商店数据
│   ├── token.gd          # 资源代币
│   └── weather.gd        # 天气系统
├── lib/              # 工具库
│   ├── item_icons.gd     # 物品图标
│   └── vfx_manager.gd    # 特效管理
├── ui/               # UI组件
│   ├── bubble_dialogue.gd   # 气泡对话框
│   ├── camera_button.gd     # 相机按钮
│   ├── clue_log.gd          # 线索日志
│   ├── dialogue_system.gd   # 对话系统
│   ├── event_popup.gd       # 事件弹窗
│   ├── hand_panel.gd        # 手牌面板
│   ├── resource_bar.gd      # 资源条
│   └── shop_popup.gd        # 商店弹窗
└── main.gd           # 主入口脚本
```

---

## 核心模块详解

### 1. 自动加载层 (Autoload)

| 文件 | 职责 | 关键数据 |
|------|------|----------|
| `game_data.gd` | 全局游戏状态、存档管理 | 玩家数据、资源、背包 |
| `card_config.gd` | 卡牌配置读取、卡牌实例化 | `CardConfig` 注册表 |
| `story_manager.gd` | 剧情/事件触发管理 | `StoryEvent` 队列 |
| `theme.gd` | 暗色调主题管理 | 颜色、字体、样式 |

### 2. 核心层 (Core)

**Dark World (`dark_world.gd`)** - 672行，核心状态机
- 管理游戏全局状态：`day`、`phase`、`turn`
- 控制游戏流程：探索→战斗→结算
- 管理地图数据与事件触发

**Board (`board.gd`)** - 604行，棋盘逻辑
- 网格系统：`8x6` 棋盘
- 路径生成与寻路
- 棋盘物品放置与交互

**Card System**
- `card.gd` (148行) - 卡牌数据模型
- `card_manager.gd` (275行) - 卡牌组管理、抽卡逻辑

**Token System (`token.gd`)** - 210行
- 资源代币管理（光/暗）
- 代币消耗与获取

### 3. 控制层 (Controllers)

**Game Flow (`game_flow.gd`)** - 274行
- 回合制流程控制
- 阶段切换：行动→战斗→结束

**Dark World Flow (`dark_world_flow.gd`)** - 527行
- 暗世界探索流程
- 事件决策树

**Board Visual (`board_visual.gd`)** - 1555行
- 棋盘渲染与动画
- 相机控制
- 点击/拖拽交互

**Card Interaction (`card_interaction.gd`)** - 567行
- 卡牌拖拽到棋盘
- 目标选择逻辑
- 攻击/技能释放

### 4. UI层 (UI)

| 组件 | 功能 |
|------|------|
| `hand_panel.gd` | 手牌展示、拖拽、排序 |
| `event_popup.gd` | 随机事件弹窗（973行，最复杂UI） |
| `shop_popup.gd` | 商店系统 |
| `clue_log.gd` | 线索/日志系统 |
| `dialogue_system.gd` | NPC对话系统 |
| `bubble_dialogue.gd` | 气泡对话框 |
| `resource_bar.gd` | 资源UI条 |

---

## 设计问题分析

### 🔴 严重问题

#### 1. **耦合严重 - `dark_world.gd` 过于臃肿**
- 672行文件承担了太多职责：状态机 + 地图 + 事件 + 天气 + 流程控制
- 建议：拆分出 `map_manager.gd`、`event_dispatcher.gd`、`weather_controller.gd`

#### 2. **UI层直接操作核心数据**
- `hand_panel.gd` (907行) 包含大量卡牌操作逻辑
- `board_visual.gd` (1555行) 混合了渲染与业务逻辑
- 建议：UI只负责展示，通过信号/控制器与核心层通信

#### 3. **枚举与常量分散**
- 信号、状态、类型枚举分散在各个文件中
- 建议：建立 `enums.gd` 统一管理

```gdscript
# 当前：各文件重复定义
enum GamePhase { EXPLORE, BATTLE, SHOP }
enum TurnState { PLAYER, ENEMY }

# 建议：统一枚举文件
class_name Enums
enum GamePhase { ... }
enum TurnState { ... }
```

---

### 🟡 中等问题

#### 4. **缺乏统一的资源管理**
- 图片资源通过 `.import` 文件引用，但没有统一的加载管理
- 建议：建立 `resource_loader.gd` 资源预加载管理

#### 5. **`_ready()` 初始化逻辑分散**
- 各模块在 `_ready()` 中自行初始化，顺序依赖不明确
- 建议：使用 `bootstrap.gd` 统一初始化顺序

#### 6. **注释缺失**
- 大量函数缺少文档注释
- 建议：添加 GDScript 文档注释风格

```gdscript
## 描述功能
## @param param_name: 参数说明
## @return 返回值说明
func some_function(param) -> int:
    pass
```

#### 7. **硬编码数值**
- 棋盘大小、伤害数值等硬编码
- 建议：移至 `game_config.json` 或 `balance_config.json`

```gdscript
# 当前
const BOARD_WIDTH = 8
const BOARD_HEIGHT = 6

# 建议
const BOARD_SIZE = Vector2i(
    Config.get_int("board.width", 8),
    Config.get_int("board.height", 6)
)
```

---

### 🟢 建议改进

#### 8. **信号使用不规范**
- 部分地方用 `emit_signal()` 而非 `signal_name.emit()`
- 建议：统一使用 Godot 4 的新信号语法

#### 9. **缺乏错误处理**
- 大量假设数据存在，没有 null 检查
- 建议：添加防御性编程

#### 10. **测试覆盖缺失**
- 没有单元测试
- 建议：使用 GUT 框架添加测试

---

## 数据流架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      Autoload Layer                          │
│  ┌──────────┐  ┌──────────────┐  ┌────────────┐  ┌────────┐ │
│  │game_data │  │card_config   │  │story_mgr   │  │ theme  │ │
│  └────┬─────┘  └──────┬───────┘  └─────┬──────┘  └────────┘ │
└───────┼───────────────┼───────────────┼────────────────────┘
        │               │               │
        ▼               ▼               ▼
┌───────────────────────────────────────────────────────────────┐
│                       Core Layer                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │dark_world│  │  board   │  │card_mngr │  │ npc_manager  │   │
│  │ (State)  │  │ (Grid)   │  │ (Deck)   │  │              │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────────┘   │
└───────┼─────────────┼────────────┼───────────────────────────┘
        │             │            │
        ▼             ▼            ▼
┌───────────────────────────────────────────────────────────────┐
│                    Controller Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐     │
│  │game_flow     │  │board_visual  │  │card_interaction  │     │
│  │(Turn Ctrl)   │  │(Rendering)   │  │(Drag & Drop)     │     │
│  └──────────────┘  └──────┬───────┘  └──────────────────┘     │
└───────────────────────────┼───────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────┐
│                        UI Layer                                │
│  ┌────────┐  ┌─────────┐  ┌───────────┐  ┌────────────────┐  │
│  │hand    │  │event    │  │shop       │  │clue_log        │  │
│  │panel   │  │popup    │  │popup      │  │                │  │
│  └────────┘  └─────────┘  └───────────┘  └────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

---

## 总结

| 维度 | 评分 | 说明 |
|------|------|------|
| 架构设计 | 6/10 | MVC结构清晰，但模块职责划分不均 |
| 代码质量 | 5/10 | 功能可运行，但缺乏文档和测试 |
| 可扩展性 | 5/10 | 卡牌/事件配置外置较好，但核心耦合重 |
| 命名规范 | 6/10 | 基本遵循Godot风格，少量命名不一致 |

**优先改进建议**：
1. 重构 `dark_world.gd`，拆分状态机与业务逻辑
2. 建立统一枚举管理文件
3. 提取 UI 中的业务逻辑到控制器层
4. 添加文档注释和单元测试
