## ConsumableController - 消耗品控制器
## 封装: 消耗品列表查询、使用效果、驱魔操作
## 目的: 解耦 UI 层 (hand_panel) 与核心数据层 (GameData)
extends RefCounted

# ---------------------------------------------------------------------------
# 引用 (由 main.gd 注入)
# ---------------------------------------------------------------------------
var m: Node = null

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func setup(main_ref) -> void:
	m = main_ref

# =========================================================================
# 消耗品查询
# =========================================================================

## 获取可消耗品条目列表 (用于 UI 展示)
func get_consumable_entries() -> Array:
	var result: Array = []
	for key in CardConfig.consumable_order:
		var count: int = GameData.get_item_count(key)
		if count > 0:
			result.append({
				"key": key,
				"count": count,
				"info": ShopData.get_item_info(key),
			})
	return result

## 检查是否有指定消耗品
func has_consumable(key: String) -> bool:
	return GameData.get_item_count(key) > 0

## 获取指定消耗品的数量
func get_consumable_count(key: String) -> int:
	return GameData.get_item_count(key)

# =========================================================================
# 消耗品使用
# =========================================================================

## 使用消耗品 (返回是否成功)
func use_consumable(key: String) -> bool:
	var info: Dictionary = ShopData.get_item_info(key)
	if info.is_empty():
		return false
	if not GameData.remove_item(key):
		return false
	# 应用效果
	var effects: Dictionary = info.get("effect", {})
	GameData.apply_effects(effects)
	return true

## 使用驱魔香 (特殊处理)
func use_exorcism() -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"card": null,
		"message": "",
	}
	if not GameData.remove_item("exorcism"):
		result["message"] = "没有驱魔香!"
		return result

	result["success"] = true
	result["message"] = "🪔 驱魔香驱除!"
	return result

## 使用护身符 (检查是否抵消伤害)
func try_use_shield() -> bool:
	if GameData.has_item("shield"):
		GameData.remove_item("shield")
		return true
	return false

# =========================================================================
# 特殊道具效果查询 (用于 UI 提示)
# =========================================================================

## 获取消耗品的效果描述 (用于 UI tooltip)
func get_consumable_tooltip(key: String) -> String:
	var info: Dictionary = ShopData.get_item_info(key)
	if info.is_empty():
		return ""
	var label: String = info.get("name", "")
	var effect: Dictionary = info.get("effect", {})
	var parts: Array = []
	var res_names: Dictionary = { "san": "理智", "order": "秩序", "film": "胶卷" }
	if key == "exorcism":
		parts.append("驱除当前怪物")
	elif key == "shield":
		parts.append("抵挡一次伤害")
	elif key == "mapReveal":
		parts.append("揭示周围")
	else:
		for ek in effect:
			var rn: String = res_names.get(ek, ek)
			var ev: int = effect[ek]
			var sign: String = "+" if ev > 0 else ""
			parts.append(rn + sign + str(ev))
	return label + ": " + ", ".join(parts)
