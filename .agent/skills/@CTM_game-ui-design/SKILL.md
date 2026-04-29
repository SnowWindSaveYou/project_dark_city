---
name: game-ui-design
description: |
  《全村最好的剑》项目 UI 设计规范与排版系统。竖屏塔防 RPG 游戏，基于 NanoVG 绘制全部 UI。
  Use when: (1) 新增 UI 面板/弹窗/HUD 组件, (2) 修改现有 UI 布局或样式, (3) 设计新功能界面（符文、背包、商店等）, (4) 需要保持视觉一致性的任何 UI 工作。
  触发关键词：UI、界面、面板、弹窗、按钮、HUD、菜单、排版、布局、样式。
---

# 游戏 UI 设计规范

## 基础参数

- **设计分辨率**：`1080x2400`（竖屏），坐标原点左上角
- **坐标系**：所有 UI 坐标基于设计分辨率，通过 `ScreenToDesign()` 转换输入
- **字体**：统一使用 `"sans"` face
- **渲染**：全部使用 NanoVG，在 `NanoVGRender` 事件中绘制

## 颜色体系

### 品质色（6 级）

| 品质 | 名称 | RGB |
|------|------|-----|
| 1 | 普通 | `181,181,181` |
| 2 | 优质 | `162,255,148` |
| 3 | 稀有 | `114,242,245` |
| 4 | 史诗 | `239,121,255` |
| 5 | 传说 | `255,237,0` |
| 6 | 至臻 | `255,0,0` |

### 主题色

> **注意**：以下主题色从当前项目（《全村最好的剑》）的 Render.lua 中提取。
> 若用于其他项目，应根据该项目实际使用的 UI 配色替换此表，保持 Skill 与项目视觉一致。

| 用途 | RGB(A) | 说明 |
|------|--------|------|
| 面板深棕 | `113,74,58` | 标题栏背景、属性条、标签背景 |
| 标题深棕 | `117,79,62` | 面板标题文字填充色 |
| 属性文字棕红 | `88,46,45` | 属性名称、正文内容 |
| 属性条米黄 | `207,166,119` | 属性条背景、分隔线 |
| 描边深棕 | `68,45,25` | 文字描边、面板外边框 |
| 描边纯黑 | `0,0,0` | HUD 文字描边 |
| 面板内底米黄 | `245,228,200` | 面板内层背景填充 |
| 金币金黄 | `255,234,0` | 金币数值 |
| 法力青 | `112,230,255` | 法力条、技能发光 |
| 遮罩黑 | `0,0,0,160` | 弹窗背景遮罩 |

## 字号层级

| 层级 | 字号 | 用途 | 描边宽度 |
|------|------|------|----------|
| 超大标题 | 120 | "暂停"等全屏标题 | 6 |
| 大标题 | 80 | 章节名 | 5 |
| 中标题 | 55-60 | 面板标题、按钮文字 | 6 |
| 正文 | 48-52 | 武器名、波次、品质文字 | 5 |
| 小正文 | 38-40 | 属性值、描述、速度按钮 | 3-4 |
| 小字 | 32-36 | 商店描述、标签 | 3 |

**描边函数**：`DrawStrokedText(nvg, text, x, y, fontSize, fontColor, strokeColor, strokeWidth, align)` — 16 方向圆形偏移。

## 弹窗标准模板

所有弹窗遵循统一结构：

```
1. 黑色遮罩 rgba(0,0,0,160)
2. 面板背景图（居中 x=540）
3. 标题文字（面板顶部偏下）
4. 内容区域（列表/网格/表单）
5. 底部按钮组
```

### 开关动画

```lua
-- 打开：0.25秒
local t = easeOutCubic(elapsed / 0.25)
local scale = 0.85 + 0.15 * t    -- 从 85% 缩放到 100%
nvgGlobalAlpha(nvg, t)            -- 淡入

-- 关闭：反向
local t = 1 - easeOutCubic(elapsed / 0.25)
```

### 缓动函数

- `easeOutBack`：弹性回弹，用于入场动画
- `easeOutCubic`：平滑减速，用于弹窗、滑入
- `easeOutBounce`：落地弹跳，用于角色入场

## 按钮规范

| 类型 | 典型尺寸 | 文字字号 | 描边 |
|------|----------|----------|------|
| 主按钮 | 290x195 | 55 | 6px 深棕 |
| 长按钮 | 386x195 | 55 | 6px 深棕 |
| 圆形按钮 | 98x98 或 134x134 | 40 | 5px |
| 关闭按钮 | 134x134 | - | - |

按钮浮动动画：振幅 8px，频率 3Hz。
入场动画：0.3s easeOutBack 缩放。

## 常用组件模式

### 进度条（血条/经验条/法力条）

```lua
nvgSave(nvg)
nvgScissor(nvg, barX, barY, barW * percent, barH)
DrawUIImage(nvg, "填充图", cx, cy, w, h)
nvgRestore(nvg)
```

血条附带残影效果：红色半透明层延迟跟随。

### 网格布局

```lua
local col = (i - 1) % cols
local row = math.floor((i - 1) / cols)
local x = gridLeft + col * cellSpacingX + cellSpacingX / 2
local y = gridTop + row * cellSpacingY + cellSpacingY / 2
```

典型配置：5 列，格子 124-180px，间距 12-20px。

### 滚动列表

```lua
-- 1. scissor 裁剪可见区域
nvgScissor(nvg, clipX, clipY, clipW, clipH)
-- 2. 所有内容 Y 坐标减去 scrollY
local drawY = baseY - scrollY
-- 3. 跳过屏幕外项目
if drawY + itemH < clipY or drawY > clipY + clipH then goto continue end
-- 4. 惯性滚动：0.92 衰减，dt*20 速度系数，0.5 阈值停止
```

### 属性双列布局

- 属性条背景：`448x54`，圆角 9，颜色 `207,166,119`
- 左列 X=285，右列 X=747
- 属性名：字号 38，棕红 `88,46,45`，居中
- 属性值：字号 38，白色，右对齐

### 品质着色

```lua
local paint = nvgImagePattern(nvg, x, y, w, h, 0, img.handle, 1.0)
paint.innerColor = nvgRGBA(qualityR, qualityG, qualityB, alpha)
nvgFillPaint(nvg, paint)
```

## 图片资源约定

- 全局 `images_` 表，由 `EnsureImages(nvg)` 初始化
- `DrawUIImage(nvg, key, cx, cy, w, h, alpha)` — cx/cy 为中心坐标
- 精灵图用 `DrawSpriteFrame()` — 支持多行多列、翻转、着色
- 预乘 Alpha：`NVG_IMAGE_PREMULTIPLIED`（消除白边）
- Mipmap：`NVG_IMAGE_GENERATE_MIPMAPS`（缩放抗锯齿）

## HUD 入场时序

| 延迟 | 持续 | 缓动 | 元素 |
|------|------|------|------|
| 0s | 1s | easeOutBounce | 角色 |
| 0.7s | 0.5s | easeOutBack | 顶部 UI |
| 0.75s | 0.5s | easeOutBack | 底部背包+血条 |
| 0.85s | 0.45s | easeOutCubic | 左侧按钮 |
| 0.95s | 0.45s | easeOutCubic | 右侧按钮 |

## 新 UI 检查清单

新增 UI 时确认：

- [ ] 坐标基于 1080x2400 设计分辨率
- [ ] 弹窗有黑色遮罩 + 缩放淡入动画
- [ ] 字号和描边符合层级规范
- [ ] 品质颜色使用 6 级标准色
- [ ] 面板主题色使用棕色系
- [ ] 进度条使用 scissor 裁剪
- [ ] 滚动列表有惯性和裁剪
- [ ] 图片通过 DrawUIImage 绘制（中心坐标）
