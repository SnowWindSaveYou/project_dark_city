## ItemIcons - 道具图标纹理索引
## 对应原版 ItemIcons.lua
## 统一管理所有道具的手绘风图标纹理，供 ShopPopup / HandPanel / EventPopup 等使用
class_name ItemIcons
extends RefCounted

# ---------------------------------------------------------------------------
# 图标路径映射 (key → 资源路径)
# ---------------------------------------------------------------------------
const ICON_PATHS: Dictionary = {
	"film":        "res://assets/image/道具_胶卷v2_20260426153757.png",
	"shield":      "res://assets/image/道具_护身符v2_20260426153859.png",
	"exorcism":    "res://assets/image/道具_驱魔香v2_20260426153756.png",
	"coffee":      "res://assets/image/道具_咖啡v2_20260426153856.png",
	"mapReveal":   "res://assets/image/道具_地图碎片v2_20260426153808.png",
	"sedative":    "res://assets/image/道具_镇定剂v2_20260426155757.png",
	"orderManual": "res://assets/image/道具_秩序手册v2_20260426155707.png",
}

# 纹理缓存: key → Texture2D
static var _textures: Dictionary = {}

# ---------------------------------------------------------------------------
# 查询 API
# ---------------------------------------------------------------------------

## 获取道具纹理 (首次访问时加载并缓存)
static func get_texture(key: String) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	var path: String = ICON_PATHS.get(key, "")
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		if tex:
			_textures[key] = tex
			return tex
	return null

## 检查是否有指定道具的图标
static func has_icon(key: String) -> bool:
	return ICON_PATHS.has(key)

## 获取所有已注册的道具 key 列表
static func keys() -> Array[String]:
	var result: Array[String] = []
	for k in ICON_PATHS:
		result.append(k)
	return result
