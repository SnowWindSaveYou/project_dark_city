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

## 随机商店变体
static func random_variant() -> Dictionary:
	var variants: Array = CardConfig.shop_variants
	return variants[randi() % variants.size()]

## 获取商品信息
static func get_item_info(key: String) -> Dictionary:
	return CardConfig.shop_items.get(key, {})
