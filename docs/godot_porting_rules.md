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

## 自查清单

翻译每个文件后执行:

- [ ] **无 `:=`** — 所有声明都使用 `var x: Type = expr` 显式标注 (规则1)
- [ ] **autoload 名** 没有与 Godot 内置类重名 (规则2)
- [ ] **可空变量** 使用 `var x = expr`（无类型标注），不会导致运行时类型错误 (规则1)
- [ ] **Variant 链** 结果已在使用处用显式类型接收 (规则3)
- [ ] **资源文件** 已存在于 `godot/` 目录内 (规则4)
