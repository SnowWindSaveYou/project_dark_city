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

## 规则 8: 俯视角 3D 卡牌翻转用 `scale` 压扁，不用 `rotation`

**问题**: 棋盘类游戏中卡牌平铺在 XZ 平面上，相机从正上方俯视。此时绕 Y 轴旋转 180° 看起来是卡牌原地自转，而不是"翻面"效果。

**规则**: 使用 `scale.z`（或 `scale.x`）从 1→0→1 模拟翻牌，中间回调更换正反面内容：

```gdscript
# ❌ 错误: Y 轴旋转在俯视角下看起来像自转
tw.tween_property(card_node, "rotation:y", PI, 0.2)

# ✅ 正确: scale 压扁 → 换面 → 展开
tw.tween_property(card_node, "scale:z", 0.0, 0.12)  # 压扁
tw.tween_callback(func(): update_card_visual(row, col))  # 换面
tw.tween_property(card_node, "scale:z", 1.0, 0.12)  # 展开
```

**适用场景**: 任何俯视/等距视角的卡牌/瓦片翻转效果。侧视角游戏可以正常用旋转。

---

## 规则 9: GPUParticles3D 程序化创建要点

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
- [ ] **俯视翻转** 使用 scale 压扁而非 rotation (规则8)
