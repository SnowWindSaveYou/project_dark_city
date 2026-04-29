# GDScript 移植规则 - 踩坑记录

> 从 UrhoX/Lua 移植到 Godot 4.x (GDScript) 过程中遇到的问题和约束。
> 持续维护，作为后续翻译代码时的检查清单。

---

## 规则 1: 禁用 `:=`，一律使用显式类型标注 🔴

**问题**: GDScript 的 `:=` 类型推断在多种场景下会失败（Variant 链、Autoload 局部变量、Dictionary 下标、无类型迭代等），排查成本远大于直接写类型。

**规则**: 所有 `var`/`const` 声明一律用 `var x: Type = expr`，禁止 `:=`。

```gdscript
# ❌ 禁止
var x := 0
var color := h("#FF0000")
var card := get_card(r, c)
const ROWS := 5

# ✅ 正确
var x: int = 0
var color: Color = h("#FF0000")
var card: Card = get_card(r, c)
const ROWS: int = 5
```

**常用类型速查**:

| 右侧表达式 | 标注类型 |
|-----------|---------|
| `0`, `1`, `-1`, `randi()` | `int` |
| `0.0`, `1.5`, `sin()`, `randf()` | `float` |
| `""`, `"hello"`, `str()` | `String` |
| `true`, `false`, `x == y`, `x in [...]` | `bool` |
| `Color(...)`, `h("...")`, `c(...)`, `Color.WHITE` | `Color` |
| `Vector2(...)`, `Vector2.ZERO` | `Vector2` |
| `Vector2i(...)` | `Vector2i` |
| `Rect2(...)` | `Rect2` |
| `[]`, `[1, 2, 3]` | `Array` |
| `{}`, `{"key": val}` | `Dictionary` |
| `create_tween()` | `Tween` |
| `ThemeDB.fallback_font` | `Font` |
| `load(...) as Texture2D` | `Texture2D` |
| `ClassName.new()` | `ClassName` |
| `int(...)`, `mini(...)`, `absi(...)` | `int` |
| `float(...)`, `minf(...)`, `clampf(...)` | `float` |

**可空值特殊处理** — 返回值可能是 null 时，不标注类型:
```gdscript
# 可能返回 null → 用 Variant（不标注类型）
var ghost = find_ghost()
if ghost:
    do_something(ghost)
```

---

## 规则 2: 禁止用 Godot 内置类名作 autoload 名

**问题**: `Theme` 是 Godot 内置类名，用作 autoload 会导致整个项目无法解析。

**规则**:
```
❌ autoload 名: Theme / Input / Time / Animation
✅ autoload 名: GameTheme / GameInput / GameTime / GameAnimation
```

**注意**: `var t = Theme` 这种局部简写也需要一并替换为 `var t = GameTheme`。

---

## 规则 3: Variant 传播链 — 知道在哪里断

即使不用 `:=`，仍需理解 Variant 传播机制，避免运行时类型错误。

**Variant 的来源**:

| 来源 | 示例 | 说明 |
|------|------|------|
| `var x = null` | 控制器模式避免循环依赖 | 整条 `x.method()` 链返回 Variant |
| `var t = Autoload` | `var t = GameTheme` | 局部变量丢失 class_name 类型 |
| `dict["key"]` | `slot["pos_x"]` | 下标访问返回 Variant |
| `dict.get(k, d)` | `info.get("key", {})` | 返回 Variant |
| `for x in array` | 无类型 Array 的迭代变量 | `x` 是 Variant |

**安全的断链点** — 这些构造器/函数始终返回确定类型:
```gdscript
Color(r, g, b, a)     # 参数是 Variant 也返回 Color
Vector2(x, y)          # 同上
Rect2(x, y, w, h)     # 同上
int(x)  float(x)      # 显式转换
str(x)                 # 始终返回 String
```

---

## 规则 4: 资源路径必须在 `project.godot` 目录内

**问题**: Godot 的 `res://` 只解析到 `project.godot` 所在目录内。

**规则**: 所有引用的图片/音频/字体必须在 `godot/` 目录下:

```
godot/
├── project.godot
├── assets/
│   ├── image/      # 怪物、道具、幽灵图片
│   ├── images/     # 日期过渡背景等
│   └── textures/
│       └── token/  # 角色表情 token
└── scripts/        # GDScript 代码
```

---

## 规则 5: Array 元素不能用 `tween_property` 路径访问 🔴

**问题**: GDScript 的 `tween_property` 不支持 `"my_array:0"` 这样的属性路径来访问 Array 元素。这与 Node 属性路径（如 `"position:x"`）不同，Array 下标不是属性。

**报错**: `The tweened property "_card_alphas:0" does not exist`

**规则**: 改用 `tween_method` + lambda 闭包：

```gdscript
# ❌ 错误: Array 不支持属性路径
var arr: Array = [0.0, 0.0, 0.0]
tw.tween_property(self, "_card_alphas:0", 1.0, 0.3)

# ✅ 正确: tween_method + 闭包捕获索引
tw.tween_method(func(v: float): arr[idx] = v, arr[idx], target, 0.3)
```

**封装建议** — 如果有大量 Array 元素需要 tween，提取辅助函数：
```gdscript
func _tween_array(tw: Tween, arr: Array, idx: int, target: float,
        dur: float, delay: float = 0.0,
        trans: Tween.TransitionType = Tween.TRANS_LINEAR,
        ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
    var tweener = tw.tween_method(
        func(v: float): arr[idx] = v,
        arr[idx], target, dur
    )
    if delay > 0.0:
        tweener.set_delay(delay)
    tweener.set_trans(trans).set_ease(ease_type)
```

---

## 规则 6: 静态方法不能与 `Object` 内置方法同名 🔴

**问题**: 所有 GDScript 类最终继承自 `Object`，其内置方法（`get_name()`、`get_class()` 等）签名固定。如果自定义静态方法同名，调用时会解析到内置版本，参数不匹配就报错。

**报错**: `Invalid call to function 'get_name'. Expected 0 argument(s)`

**规则**: 自定义方法避免与 `Object` 内置方法重名：

```gdscript
# ❌ 错误: Object.get_name() 是 0 参数的内置方法
class_name Weather
static func get_name(weather_type: Type) -> String:
    return NAMES.get(weather_type, "未知")

# ✅ 正确: 换一个不冲突的名字
static func get_weather_name(weather_type: Type) -> String:
    return NAMES.get(weather_type, "未知")
```

**常见冲突方法名**（Object/RefCounted/Node 继承链）:

| 内置方法 | 安全替代名 |
|---------|-----------|
| `get_name()` | `get_xxx_name()` |
| `get_class()` | `get_xxx_class()` |
| `get_type()` | `get_xxx_type()` |
| `set_name()` | `set_xxx_name()` |
| `get_meta()` | `get_xxx_meta()` |
| `get_script()` | `get_xxx_script()` |
| `to_string()` | `format_xxx()` |

---

## 规则 7: `_draw()` 中不能调用产生随机结果的函数

**问题**: `_draw()` 每帧调用。如果在其中调用返回随机结果的函数（如 `texts[randi() % texts.size()]`），每帧文本都不同，产生持续闪烁/滚动的视觉 Bug。

**规则**: 随机内容在触发时（`show()`/`open()`）缓存，`_draw()` 只读缓存值：

```gdscript
# ❌ 错误: 每帧产生不同随机文本
func _draw() -> void:
    var desc: String = _card.get_event_text()  # 内部有 randi()
    draw_string(font, pos, desc, ...)

# ✅ 正确: 展示时缓存, 绘制时使用缓存
var _cached_desc: String = ""

func show_event(card: Card) -> void:
    _cached_desc = card.get_event_text()  # 只随机一次
    visible = true

func _draw() -> void:
    draw_string(font, pos, _cached_desc, ...)  # 稳定输出
```

**泛化原则**: `_draw()` / `_process()` 中的所有数据源都应该是确定性的。任何 `randi()`、`randf()`、`shuffle()` 都应移到事件触发点。

---

## 规则 8: GPUParticles3D 程序化创建要点

**问题**: Godot 的 `GPUParticles3D` 全程序化创建时，容易遗漏关键属性导致粒子不显示或效果异常。

**必需组件清单**:

```gdscript
var particles: GPUParticles3D = GPUParticles3D.new()
particles.emitting = true
particles.amount = 12
particles.lifetime = 1.8

# 1. 必须设置 draw_pass (否则无可见物)
particles.draw_pass_1 = QuadMesh.new()  # 最简单的粒子形状

# 2. 必须设置 process_material (否则粒子堆在原点不动)
var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
proc.direction = Vector3(0, 1, 0)
proc.initial_velocity_min = 0.05
proc.initial_velocity_max = 0.15
particles.process_material = proc

# 3. 材质需要开启透明 + billboard (否则粒子不面向相机/不透明)
var mat: StandardMaterial3D = StandardMaterial3D.new()
mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
mat.vertex_color_use_as_albedo = true  # 让 color_ramp 生效
particles.material_override = mat
```

**缩放/颜色动画**: 通过 `CurveTexture` 和 `GradientTexture1D` 设置：
```gdscript
# 缩放曲线 (0→1→0.8→0 淡出)
var scale_curve: CurveTexture = CurveTexture.new()
var curve: Curve = Curve.new()
curve.add_point(Vector2(0.0, 0.0))
curve.add_point(Vector2(0.15, 1.0))
curve.add_point(Vector2(0.7, 0.8))
curve.add_point(Vector2(1.0, 0.0))
scale_curve.curve = curve
proc.scale_curve = scale_curve

# 颜色渐变 (亮色 → 透明)
var color_ramp: GradientTexture1D = GradientTexture1D.new()
var gradient: Gradient = Gradient.new()
gradient.set_color(0, Color(1.0, 0.88, 0.4, 0.9))
gradient.set_color(1, Color(1.0, 0.7, 0.2, 0.0))
color_ramp.gradient = gradient
proc.color_ramp = color_ramp
```

---

## 规则 9: Lua 的 `0` 是 truthy，GDScript 的 `0` 是 falsy 🔴

**问题**: Lua 中只有 `nil` 和 `false` 是 falsy，数字 `0` 和 `0.0` 都是 **truthy**。GDScript 中 `0`/`0.0` 是 **falsy**。移植时如果把 Lua 的 `if x then`（检查字段是否存在）翻译成 GDScript 的 `if x != 0.0`（检查值是否非零），语义就变了。

**典型踩坑**: 怪物方向指示 `trail_dir_x/trail_dir_y`，当怪物和被拍卡在同一行（`dir_y==0`）或同一列（`dir_x==0`）时，Lua 的 `if cd.trailDirX and cd.trailDirZ` 通过（0 是 truthy），GDScript 的 `if card.trail_dir_x != 0.0 and card.trail_dir_y != 0.0` 被过滤掉。

**规则**: 翻译 Lua 的"字段存在性检查"时，使用独立的布尔标记，不要用值是否为零判断：

```gdscript
# ❌ 错误: 从 Lua 的 `if cd.trailDirX and cd.trailDirZ` 直译
if card.trail_dir_x != 0.0 and card.trail_dir_y != 0.0:
    show_trail(card)  # 同行/同列时不显示!

# ✅ 正确: 用布尔标记记录"是否有数据"
card.has_trail = true  # 在 calculate_trail() 找到怪物时设置
if card.has_trail:
    show_trail(card)   # 方向分量为 0 也能正确显示
```

**速查表**:

| Lua 模式 | 含义 | GDScript 翻译 |
|---------|------|--------------|
| `if x then` (x 是数字) | x 不是 nil | 用布尔标记，或 `if x != null` |
| `if x then` (x 是字符串) | x 不是 nil | `if x != ""` 或布尔标记 |
| `if not x then` (x 是数字) | x 是 nil | `if not has_x` |
| `x = nil` (清除字段) | 删除字段 | 设布尔标记为 false |

---

## 规则 10: Sprite3D.render_priority 范围是 -128 ~ 127

**问题**: Godot 的 `Sprite3D.render_priority` 内部用 `int8`，有效范围 `-128 ~ 127`。超出范围会触发 C++ 断言错误。

**规则**: 渲染优先级使用小数值即可区分层级：

```gdscript
# ❌ 错误: 超出范围
sprite.render_priority = 200

# ✅ 正确: 用小值区分层级
sprite.render_priority = 5   # 普通图标
sprite.render_priority = 10  # 高优先级图标
```

---

## 规则 11: MeshInstance3D 没有 `modulate` 属性

**问题**: `modulate` 是 `CanvasItem`（2D）的属性。`MeshInstance3D` 是 3D 节点，透明度需要通过材质控制。

**规则**: 3D 节点的透明度通过 `material_override.albedo_color.a` 控制：

```gdscript
# ❌ 错误: MeshInstance3D 没有 modulate
mesh_instance.modulate.a = 0.5

# ✅ 正确: 通过材质控制透明度
var mat: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
if mat:
    mat.albedo_color.a = 0.5
```

---

## 规则 12: `draw_string` 居中/右对齐必须指定 `width` 🔴

**问题**: NanoVG 的 `NVG_ALIGN_CENTER` 将 x 视为文本**中心点**，直接居中。Godot 的 `draw_string` 使用 `HORIZONTAL_ALIGNMENT_CENTER` 时，如果 `width = -1`（默认值），**对齐参数被忽略**，x 始终作为文本左边缘。必须提供正数 `width`，文本才会在 `[x, x+width]` 范围内居中。

**典型表现**: 所有文字都偏向右侧，因为"中心点"被当成了"左边缘"。

**规则**:

```gdscript
# ━━━ CENTER 对齐 ━━━

# ❌ 错误: width=-1 → 对齐无效, cx 成了文字左边缘
draw_string(font, Vector2(cx, y), text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, color)

# ✅ 正确: x=容器左边缘, width=容器宽度 → 文字在容器内居中
draw_string(font, Vector2(left_edge, y), text, HORIZONTAL_ALIGNMENT_CENTER, container_width, size, color)

# ━━━ RIGHT 对齐 ━━━

# ❌ 错误: width=-1 → 对齐无效, right_x 成了文字左边缘
draw_string(font, Vector2(right_x, y), text, HORIZONTAL_ALIGNMENT_RIGHT, -1, size, color)

# ✅ 正确: x=左边界, width=右边界位置 → 文字右对齐到 x+width 处
draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, right_x, size, color)
```

**从 NanoVG 翻译的转换公式**:

| NanoVG 原版 | Godot 翻译 |
|------------|-----------|
| `nvgTextAlign(vg, NVG_ALIGN_CENTER)` + `nvgText(vg, cx, y, text)` | `draw_string(font, Vector2(container_left, y), text, HORIZONTAL_ALIGNMENT_CENTER, container_width, ...)` |
| `nvgTextAlign(vg, NVG_ALIGN_RIGHT)` + `nvgText(vg, rx, y, text)` | `draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, rx, ...)` |

**常见变体**:

```gdscript
# 全屏宽度居中 (标题、副标题等)
var w: float = get_viewport_rect().size.x
draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, color)

# 在面板内居中 (弹窗标题、按钮文字)
draw_string(font, Vector2(panel_x, y), text, HORIZONTAL_ALIGNMENT_CENTER, panel_width, size, color)

# 阴影 + 主体文字 (阴影偏移 2px)
draw_string(font, Vector2(2, y + 2), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, shadow_color)
draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, main_color)
```

**图标/Emoji 居中**: 手动偏移 (如 `cx - 20`) 同样不可靠，应使用 width 居中：
```gdscript
# ❌ 错误: 手动偏移近似居中
draw_string(font, Vector2(cx - 20, y), "📷", HORIZONTAL_ALIGNMENT_CENTER, -1, ...)

# ✅ 正确: 在容器内居中
draw_string(font, Vector2(container_x, y), "📷", HORIZONTAL_ALIGNMENT_CENTER, container_w, ...)
```

---

## 自查清单

翻译每个文件后执行:

- [ ] **无 `:=`** — 所有声明都使用 `var x: Type = expr` 显式标注 (规则1)
- [ ] **autoload 名** 没有与 Godot 内置类重名 (规则2)
- [ ] **可空变量** 使用 `var x = expr`（无类型标注），不会导致运行时类型错误 (规则1)
- [ ] **Variant 链** 结果已在使用处用显式类型接收 (规则3)
- [ ] **资源文件** 已存在于 `godot/` 目录内 (规则4)
- [ ] **Array tween** 未使用 `tween_property` 路径访问数组元素，改用 `tween_method` (规则5)
- [ ] **方法名** 自定义方法未与 Object/Node 内置方法同名 (规则6)
- [ ] **`_draw()` 纯净** — 无 `randi()`/`randf()`/随机函数调用，随机内容已缓存 (规则7)
- [ ] **Lua truthy/falsy** — `if x then` 翻译为布尔标记而非 `!= 0` 检查 (规则9)
- [ ] **render_priority** — Sprite3D 优先级在 -128~127 范围内 (规则10)
- [ ] **3D 透明度** — MeshInstance3D 用 `material_override.albedo_color.a`，不用 `modulate` (规则11)
- [ ] **draw_string 对齐** — `HORIZONTAL_ALIGNMENT_CENTER/RIGHT` 都指定了正数 `width`，未使用 `-1` (规则12)

