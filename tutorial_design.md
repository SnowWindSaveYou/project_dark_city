# 教程与机制说明设计文档

> 记录所有向玩家传达机制说明的触发方式、对话内容与代码位置。

---

## 设计原则

- **按需触发**：在玩家第一次遭遇相关机制时说明，不在开场集中塞满
- **白夜作为主要引导者**：作为全程陪同角色，叙事上自然引出大多数提示
- **一次性**：每条提示只触发一次，通过 `G.tutorialFlags` 防止重复
- **气泡锁定模式**：使用 `BubbleDialogue.showTutorial(bubble, text, duration)` 显示固定文本，持续到玩家点击或时间到期

---

## 教程清单

### 1. Day 1 开场 · 棋盘与日程

| 项目 | 内容 |
|------|------|
| **触发时机** | 第一天发牌完成后（`GameFlow.startDeal` deal-complete 回调） |
| **交付方式** | `DialogueSystem.start` 模态对话框 |
| **实现文件** | `scripts/GameFlow.lua` · `DAY1_TUTORIAL_DIALOGUE` |

**对话内容（完整）**：

```
白夜：这是……你住的地方？
苏柚：嗯。不太平，但没办法。
白夜：那些背面朝上的牌……翻开后会有麻烦吗？
苏柚：有些是正常的地方，有些……自从你来了以后，就不太一样了。
白夜：……对不起。
苏柚：不是怪你。（翻开笔记本）不管怎样，我今天有些事要做。
苏柚：左边这本是日程，完成了有好处。尽量别一直拖着。
白夜：……我知道了。我不会拖累你的。
苏柚：对了，我每天能走多少，跟身体状态有关。健康低了，腿就软，走不远。
白夜：……别乱挨打。
苏柚：我知道。
```

**后续动作**：对话结束后高亮 HandPanel 日程 Tab（`HandPanel.highlightOnce()`）

---

### 2. 健康 = 每日步数上限

| 项目 | 内容 |
|------|------|
| **触发时机** | Day 1 开场对话末尾（即上方第 9–11 行台词） |
| **交付方式** | `DialogueSystem` 对话，内嵌在 `DAY1_TUTORIAL_DIALOGUE` |
| **实现文件** | `scripts/GameFlow.lua` · `DAY1_TUTORIAL_DIALOGUE` 末三行 |

**说明要点**：健康值决定当天步数上限，受伤会减少活动范围。

---

### 3. 灵感影响怪物伤害

| 项目 | 内容 |
|------|------|
| **触发时机** | 玩家**首次翻到怪物卡**时（`MonsterGhost.spawnAroundPlayer` 调用后） |
| **交付方式** | `BubbleDialogue.showTutorial`，持续 7 秒 |
| **实现文件** | `scripts/CardInteraction.lua`，`G.tutorialFlags.monsterSeen` |
| **标记键** | `monsterSeen` |

**气泡文本**：
> 白夜：灵感强了，它们感知得到你。
> 感知得到……就咬得重。

---

### 4. 灵感解锁裂隙与更多感知

| 项目 | 内容 |
|------|------|
| **触发时机** | 玩家**首次翻到含裂隙的格子**（`EventPopup.showRiftConfirm` 调用前） |
| **交付方式** | `BubbleDialogue.showTutorial`，持续 7 秒 |
| **实现文件** | `scripts/CardInteraction.lua`，`G.tutorialFlags.riftSeen` |
| **标记键** | `riftSeen` |

**气泡文本**：
> 白夜：灵感不够的时候……这里什么都没有。
> 不是看不见。是感觉不到。

---

### 5. 理智 = 暗面世界步数

| 项目 | 内容 |
|------|------|
| **触发时机** | **首次进入暗面世界**，进场动画后延迟 1.8 秒 |
| **交付方式** | `BubbleDialogue.showTutorial`，持续 8 秒 |
| **实现文件** | `scripts/DarkWorldFlow.lua`，`G.tutorialFlags.darkWorldEntered` |
| **标记键** | `darkWorldEntered` |

**气泡文本**：
> 白夜：这里的规则不一样。
> 理智剩多少，就能走多少。撑不住就会被送回去。

---

### 6. 相机模式 · 侦察与幽灵轨迹

| 项目 | 内容 |
|------|------|
| **触发时机** | **首次点击相机按钮进入相机模式**（`CameraButton.setOnEnterCallback` 钩子） |
| **交付方式** | `BubbleDialogue.showTutorial`，持续 8 秒 |
| **实现文件** | `scripts/main.lua`，`G.tutorialFlags.cameraModeSeen` |
| **标记键** | `cameraModeSeen` |

**气泡文本**：
> 白夜：翻开之前，先拍一下。
> 镜头里有时会浮现方向——妖魔在哪边。
> 胶卷不多。

---

### 7. 相机消灭已翻开的怪物

| 项目 | 内容 |
|------|------|
| **触发时机** | **首次对已翻开怪物卡成功拍照驱除**（`Card.transformTo` 成功回调内） |
| **交付方式** | `BubbleDialogue.showTutorial`，持续 7 秒 |
| **实现文件** | `scripts/CardInteraction.lua`，`G.tutorialFlags.cameraExorciseSeen` |
| **标记键** | `cameraExorciseSeen` |

**气泡文本**：
> 白夜：已经现身的，照样能拍走。
> 比正面撞上安全一点。要胶卷。

---

### 8. 安全区光晕

| 项目 | 内容 |
|------|------|
| **触发时机** | **首次踏入安全区光晕格**（`Board.isInLandmarkAura` 为真，home 除外） |
| **交付方式** | `BubbleDialogue.showTutorial`，持续 8 秒 |
| **实现文件** | `scripts/CardInteraction.lua` · `onCardFlipped`，`G.tutorialFlags.safeZoneSeen` |
| **标记键** | `safeZoneSeen` |

**说明要点**：教堂和警察局不可翻开，但其相邻四格会有光晕特效，且妖魔在该范围内不会出现（monster/trap 翻开后自动降级为 safe）。

**气泡文本**：
> 白夜：发光的格子有结界——妖魔近不了身。
> 教堂和警察局周围四格，都是这样。

---

## 触发标记总表

所有标记存放于 `G.tutorialFlags`（`scripts/main.lua` G 表初始化处）：

| 标记键 | 对应教程 | 触发文件 |
|--------|---------|---------|
| *(无独立标记)* | Day 1 开场对话 | `GameFlow.lua` |
| *(无独立标记)* | 健康=步数（内嵌 Day 1 对话） | `GameFlow.lua` |
| `monsterSeen` | 灵感影响怪物伤害 | `CardInteraction.lua` |
| `riftSeen` | 灵感解锁裂隙感知 | `CardInteraction.lua` |
| `darkWorldEntered` | 理智=暗面步数 | `DarkWorldFlow.lua` |
| `cameraModeSeen` | 相机模式侦察+轨迹 | `main.lua` |
| `cameraExorciseSeen` | 相机消灭怪物 | `CardInteraction.lua` |
| `safeZoneSeen` | 安全区光晕机制 | `CardInteraction.lua` |

---

## 实现进度

| # | 机制 | 状态 |
|---|------|------|
| 1 | Day 1 开场 · 棋盘与日程 | ✅ |
| 2 | 健康 = 每日步数上限 | ✅ |
| 3 | 灵感影响怪物伤害 | ✅ |
| 4 | 灵感解锁裂隙与感知 | ✅ |
| 5 | 理智 = 暗面世界步数 | ✅ |
| 6 | 相机模式侦察与幽灵轨迹 | ✅ |
| 7 | 相机消灭已翻开怪物 | ✅ |
| 8 | 安全区光晕机制 | ✅ |
