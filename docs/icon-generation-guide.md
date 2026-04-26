# 道具图标生成指南

本文档记录「暗面都市」项目中道具图标的美术规范、生成流程和代码集成步骤，供后续新增道具时参考。

---

## 美术规范

### 风格定义

**日系可爱手绘插画风**，与游戏内场景素材（自动贩卖机、便利店等）保持一致。

关键特征：
- 清晰黑色描边（线条感强）
- 柔和粉彩填色（不要高饱和、不要写实）
- 暖色调为主
- 纸质感 / 手绘质感
- 透明背景

### 禁忌

- 不要写实风格（金属光泽、照片质感）
- 不要暗色系水彩（之前 v1 的错误方向）
- 不要在图标上加英文文字或 logo
- 不要过于复杂的细节（图标最终显示尺寸约 22~28px）

### 技术参数

| 参数 | 值 |
|------|-----|
| 尺寸 | 256×256 px |
| 比例 | 1:1 |
| 格式 | PNG |
| 透明背景 | 是 |
| 命名规则 | `道具_{道具名}v{版本}_{时间戳}.png` |
| 存放目录 | `assets/image/` |

---

## 生成流程

### 1. 准备参考图

从 `assets/image/` 中选取 2 张已有的同风格图标作为 reference_images，确保风格一致：

```
assets/image/道具_咖啡v2_20260426153856.png
assets/image/道具_护身符v2_20260426153859.png
```

也可以使用场景素材作为风格参考：

```
assets/image/自动贩卖机_20260426032218.png
assets/image/便利店正面_20260426034157.png
```

### 2. 编写 Prompt

模板：

```
{道具的具体视觉描述}，日系可爱手绘插画风格，清晰黑色描边，柔和粉彩填色，暖色调，纸质感，透明背景
```

示例：

| 道具 | Prompt |
|------|--------|
| 咖啡 | 一杯外带咖啡纸杯，杯身有简约图案，日系可爱手绘插画风格，清晰黑色描边，柔和粉彩填色，暖色调，纸质感，透明背景 |
| 胶卷 | 一卷胶片胶卷，经典35mm胶片造型，日系可爱手绘插画风格，清晰黑色描边，柔和粉彩填色，暖色调，纸质感，透明背景 |
| 护身符 | 一枚日式御守护身符，系着红色绳结，日系可爱手绘插画风格，清晰黑色描边，柔和粉彩填色，暖色调，纸质感，透明背景 |
| 镇定剂 | 一瓶镇定剂药片，蓝白色小药瓶，瓶身有十字标志，日系可爱手绘插画风格，清晰黑色描边，柔和粉彩填色，暖色调，纸质感，透明背景 |

### 3. 调用生成工具

单个生成：

```
generate_image(
    prompt = "...",
    name = "道具_{名称}v2",
    target_size = "256x256",
    transparent = true,
    reference_images = [
        "assets/image/道具_咖啡v2_20260426153856.png",
        "assets/image/道具_护身符v2_20260426153859.png"
    ]
)
```

批量生成（推荐）：

```
batch_generate_images(images = [ ... ])
```

### 4. 检查生成结果

- 确认描边清晰、颜色柔和
- 确认主体物件居中、留有适当边距
- 确认背景透明
- 如不满意，可调整 prompt 中的具体描述词重新生成

---

## 代码集成步骤

### 步骤 1：注册图标路径

在 `scripts/ItemIcons.lua` 的 `ICON_PATHS` 表中添加新条目：

```lua
local ICON_PATHS = {
    -- 已有图标 ...
    newItem = "image/道具_{名称}v2_{时间戳}.png",
}
```

key 命名规则：与道具的 `inventoryKey` 保持一致（驼峰命名）。

### 步骤 2：绑定 iconKey

在 `scripts/ShopPopup.lua` 中找到对应道具数据，添加 `iconKey` 字段：

**`ALL_GOODS` 表**（商店卡牌）：

```lua
{ icon = "🆕", name = "新道具", price = 10, effects = { ... },
  desc = "描述文字", inventoryKey = "newItem", iconKey = "newItem" },
```

**`CONSUMABLE_ITEMS` 表**（背包工具栏，仅可消耗道具需要）：

```lua
newItem = { icon = "🆕", label = "新道具", effects = { ... }, order = 5, iconKey = "newItem" },
```

### 步骤 3：构建测试

修改完成后必须调用 build 工具重新构建。

---

## 当前已有图标清单

| key | 道具名 | 文件 |
|-----|--------|------|
| coffee | 咖啡 | `道具_咖啡v2_20260426153856.png` |
| film | 胶卷 | `道具_胶卷v2_20260426153757.png` |
| shield | 护身符 | `道具_护身符v2_20260426153859.png` |
| exorcism | 驱魔香 | `道具_驱魔香v2_20260426153756.png` |
| mapReveal | 地图碎片 | `道具_地图碎片v2_20260426153808.png` |
| sedative | 镇定剂 | `道具_镇定剂v2_20260426155757.png` |
| orderManual | 秩序手册 | `道具_秩序手册v2_20260426155707.png` |

---

## ItemIcons API 速查

```lua
local ItemIcons = require "ItemIcons"

-- 初始化（main.lua 中 NanoVG 就绪后调用一次）
ItemIcons.init(vg)

-- 矩形绘制（商店卡牌、CameraButton 等）
-- 返回 boolean，false 时需 fallback 到 emoji
ItemIcons.draw(vg, "coffee", cx, cy, size, alpha)

-- 圆形裁剪绘制（HandPanel 工具栏）
ItemIcons.drawCircle(vg, "coffee", cx, cy, radius, alpha)

-- 查询是否有某个图标
ItemIcons.has("coffee")  --> true

-- 获取 Texture2D（用于 3D 场景中的 Billboard 等）
ItemIcons.getTexture("coffee")
```

渲染后必须重置 NanoVG 文本状态：

```lua
if item.iconKey and ItemIcons.draw(vg, item.iconKey, 0, y, 22, alpha) then
    -- 纹理绘制成功，fillPaint 已被修改
else
    -- emoji fallback
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, ...)
    nvgText(vg, 0, y, item.icon, nil)
end

-- 后续文本必须无条件重置状态（不论走哪个分支）
nvgFontFace(vg, "sans")
nvgFontSize(vg, 11)
nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
nvgFillColor(vg, ...)
nvgText(vg, 0, nameY, item.name, nil)
```
