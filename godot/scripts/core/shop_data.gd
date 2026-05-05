## ShopData - 商店数据定义
## 对应原版 ShopPopup.lua 的数据部分
## 数据表从 CardConfig autoload 读取 (shop_items, consumable_order, shop_variants, shop_refresh_cost)
class_name ShopData
extends RefCounted

# ---------------------------------------------------------------------------
# 方法
# ---------------------------------------------------------------------------

## 随机生成 3 件商品 (不重复)
static func generate_shop_goods() -> Array:
	var all_keys: Array = CardConfig.shop_items.keys()
	all_keys.shuffle()
	var result: Array = []
	for i in range(mini(3, all_keys.size())):
		result.append(all_keys[i])
	return result

## 随机生成 3 件暗面商品 (不重复, 从 dark_items 池)
static func generate_dark_shop_goods() -> Array:
	var all_keys: Array = CardConfig.dark_items.keys()
	all_keys.shuffle()
	var result: Array = []
	for i in range(mini(3, all_keys.size())):
		result.append(all_keys[i])
	return result

## 随机商店变体 (现实世界)
static func random_variant() -> Dictionary:
	var variants: Array = CardConfig.shop_variants
	return variants[randi() % variants.size()]

## 随机暗面商店变体
static func random_dark_variant() -> Dictionary:
	var variants: Array = CardConfig.dark_variants
	if variants.is_empty():
		return { "name": "暗面商店", "greeting": "...", "icon": "🌑" }
	return variants[randi() % variants.size()]

## 获取商品信息 (优先查普通商品, 再查暗面商品)
static func get_item_info(key: String) -> Dictionary:
	var info: Dictionary = CardConfig.shop_items.get(key, {})
	if info.is_empty():
		info = CardConfig.dark_items.get(key, {})
	return info
