# GDScript 移植规则 - 踩坑记录

> 从 UrhoX/Lua 移植到 Godot 4.x (GDScript) 过程中遇到的问题和约束。
> 持续维护，作为后续翻译代码时的检查清单。

---

## 规则 1: 禁止用 `Theme` 作为 autoload 名

**问题**: `Theme` 是 Godot 内置类名，用作 autoload 会导致整个项目无法解析。

**症状**: 所有使用 `Theme.xxx` 的文件报 `Cannot find member "xxx" in base "Theme"`，因为解析器把它当成了 Godot 的 `Theme` 类而非你的 autoload。

**规则**:
```
❌ autoload 名: Theme
✅ autoload 名: GameTheme
```

**检查范围**: 所有 autoload 名都不能与 Godot 内置类重名。常见冲突:
- `Theme` → 用 `GameTheme`
- `Input` → 用 `GameInput`
- `Time` → 用 `GameTime`
- `Animation` → 用 `GameAnimation`

---

## 规则 2: `:=` 不能用于 Variant 链式调用

**问题**: GDScript 的 `:=` 需要编译器能推断出确切类型。当变量来自 `Variant` 类型（如 `var m = null`），整条链路的返回值都是 `Variant`，`:=` 会报 `Cannot infer the type` 错误。

**典型场景**: 控制器模式中 `var m = null`（避免循环依赖），所有 `m.xxx()` 返回 Variant。

**规则**:
```gdscript
# ❌ 错误 - m 是 Variant, m.board.xxx() 返回 Variant, := 无法推断
var center := m.board_visual.get_card_center(row, col)
var film := m.game_data.get_resource("film")

# ✅ 正确 - 显式标注类型
var center: Vector2 = m.board_visual.get_card_center(row, col)
var film: int = m.game_data.get_resource("film")
```

**常用类型映射**:

| 返回内容 | 标注类型 |
|---------|---------|
| 坐标/位置 | `Vector2` |
| 颜色 | `Color` |
| 整数(行/列/数量) | `int` |
| 布尔判断 | `bool` |
| 字典数据 | `Dictionary` |
| 数组/列表 | `Array` |
| 补间动画 | `Tween` |
| 可能为 null | 去掉 `:=`，用 `var x = ...` |

**可空值特殊处理**:
```gdscript
# 返回值可能是 null 的情况，不要用 := 也不要标注类型
# ❌
var ghost: Dictionary = find_ghost()  # 如果返回 null 会类型错误

# ✅
var ghost = find_ghost()  # Variant 可以是 null
if ghost:
    do_something(ghost)
```

---

## 规则 3: `var t = Theme` 简写也会被影响

**问题**: 不只是 `Theme.xxx` 直接调用，把 `Theme` 赋值给局部变量同样会出错。

**规则**:
```gdscript
# ❌ 如果 autoload 叫 Theme，这些全部出错
var t = Theme
t.bg_color  # → 访问的是 Godot 内置 Theme 类

# ✅ autoload 改名为 GameTheme 后
var t = GameTheme
t.bg_color  # → 正确访问你的 autoload
```

**全局替换时注意**: `Theme.` → `GameTheme.` 只覆盖直接调用，`var t = Theme` 这种简写需要单独搜索替换。

---

## 规则 4: `Dictionary.get()` 返回 Variant

**问题**: `Dictionary.get(key, default)` 的返回类型是 `Variant`，即使 default 是 `{}`（Dictionary），`:=` 也无法推断。

**规则**:
```gdscript
# ❌
var info := some_dict.get("key", {})

# ✅
var info: Dictionary = some_dict.get("key", {})
```

---

## 规则 5: `var t = Autoload` 局部变量也会丢失类型

**问题**: 把 autoload 赋给局部变量后，局部变量类型变为 Variant，后续通过它访问的属性/方法返回值也是 Variant。

**规则**:
```gdscript
# ⚠️ t 是 Variant（即使 GameTheme 自身有 class_name）
var t = GameTheme

# ❌ t.card_type_color() 返回 Variant
var type_color := t.card_type_color("plot")
var da := t.dark_accent

# ✅ 显式标注
var type_color: Color = t.card_type_color("plot")
var da: Color = t.dark_accent
```

**安全的情况**: `Color(t.xxx.r, t.xxx.g, t.xxx.b, alpha)` 中的 `:=` 是安全的，因为 `Color()` 构造器返回类型确定。

---

## 规则 6: `Dictionary["key"]` 下标访问返回 Variant

**问题**: Dictionary 下标访问 `dict["key"]` 返回 Variant，用它参与算术后结果仍是 Variant。

**规则**:
```gdscript
# ❌ dict["pos_x"] 是 Variant, 算术结果也是 Variant
var lx := dict["pos_x"] - cos_val * extend
var font_size := int(h * 0.15 * slot["pop_t"])

# ✅ 显式标注
var lx: float = dict["pos_x"] - cos_val * extend
var font_size: int = int(h * 0.15 * slot["pop_t"])
```

---

## 规则 7: `in` 表达式和比较表达式

**问题**: `x in [...]` 表达式和涉及 Variant 操作数的比较表达式，结果可能无法被 `:=` 推断为 `bool`。

**规则**:
```gdscript
# ❌
var is_safe := card.type in ["safe", "reward"]
var is_hovered := (_hover_index == entry["key"])

# ✅
var is_safe: bool = card.type in ["safe", "reward"]
var is_hovered: bool = (_hover_index == entry["key"])
```

---

## 规则 8: 静态方法中的无类型迭代变量

**问题**: `for item in array` 中的 `item` 是 Variant（除非 array 有类型标注），对 `item` 的成员访问结果也是 Variant。

**规则**:
```gdscript
# ❌ pos 是 Variant，pos.x 也是 Variant
for pos in untyped_array:
    var r := pos.x    # Cannot infer

# ✅ 显式标注
for pos in untyped_array:
    var r: int = pos.x
```

---

## 规则 9: 资源路径必须在 `project.godot` 目录内

**问题**: Godot 的 `res://` 只能解析到 `project.godot` 所在目录内的文件。外部文件引擎无法加载。

**规则**: 所有代码引用的图片、音频、字体等资源必须复制到 `godot/` 目录下对应位置。

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

- [ ] autoload 名没有与 Godot 内置类重名 (规则1)
- [ ] `var m = null` 的 Variant 链没有用 `:=` (规则2)
- [ ] `var t = GameTheme` 简写的属性/方法访问没有用 `:=` (规则3, 5)
- [ ] `Dictionary.get()` 返回值已标注类型 (规则4)
- [ ] `dict["key"]` 下标参与运算后没有用 `:=` (规则6)
- [ ] `x in [...]` 和涉及 Variant 的比较表达式标注了 `bool` (规则7)
- [ ] 无类型数组迭代变量的成员访问已标注类型 (规则8)
- [ ] 可能返回 null 的变量没有用 `:=`，也没有标注具体类型 (规则2)
- [ ] 所有 `res://` 引用的资源文件已存在于 godot/ 目录内 (规则9)
