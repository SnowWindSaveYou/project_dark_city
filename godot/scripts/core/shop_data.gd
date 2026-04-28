## ShopData - 商店数据定义
## 对应原版 ShopPopup.lua 的数据部分
class_name ShopData
extends RefCounted

# ---------------------------------------------------------------------------
# 商品定义
# ---------------------------------------------------------------------------
const ITEMS: Dictionary = {
	"coffee": {
		"name": "咖啡", "icon": "☕", "price": 8,
		"type": "consumable",
		"effect": { "san": 2 },
		"desc": "热腾腾的咖啡，恢复些许理智",
	},
	"film": {
		"name": "胶卷补充", "icon": "🎞️", "price": 10,
		"type": "consumable",
		"effect": { "film": 1 },
		"desc": "额外的胶卷，多一次拍摄机会",
	},
	"shield": {
		"name": "护身符", "icon": "🛡️", "price": 15,
		"type": "persistent",
		"effect": {},
		"desc": "神秘的护身符，或许能保护你",
	},
	"exorcism": {
		"name": "退魔香", "icon": "🔮", "price": 12,
		"type": "consumable",
		"effect": {},
		"desc": "燃烧时能驱散附近的邪气",
	},
	"map": {
		"name": "都市地图", "icon": "🗺️", "price": 10,
		"type": "consumable",
		"effect": {},
		"desc": "标注了一些安全路线的地图",
	},
	"sedative": {
		"name": "镇定剂", "icon": "💊", "price": 12,
		"type": "consumable",
		"effect": { "san": 3 },
		"desc": "强效镇定剂，大幅恢复理智",
	},
	"orderManual": {
		"name": "秩序手册", "icon": "📘", "price": 10,
		"type": "consumable",
		"effect": { "order": 2 },
		"desc": "阅读可以恢复对秩序的信心",
	},
}

## 消耗品的显示排序
const CONSUMABLE_ORDER: Array = ["shield", "exorcism", "coffee", "sedative", "orderManual"]

## 商店刷新价格
const REFRESH_COST: int = 5

# ---------------------------------------------------------------------------
# 商店变体
# ---------------------------------------------------------------------------
const SHOP_VARIANTS: Array = [
	{ "name": "午夜便利店", "greeting": "深夜好，有什么需要的吗？" },
	{ "name": "黄昏杂货铺", "greeting": "嘿，看看有什么中意的？" },
	{ "name": "巷口自贩机", "greeting": "请投币选择商品。" },
]

# ---------------------------------------------------------------------------
# 方法
# ---------------------------------------------------------------------------

## 随机生成 3 件商品 (不重复)
static func generate_shop_goods() -> Array:
	var all_keys: Array = ITEMS.keys()
	all_keys.shuffle()
	var result: Array = []
	for i in range(mini(3, all_keys.size())):
		result.append(all_keys[i])
	return result

## 随机商店变体
static func random_variant() -> Dictionary:
	return SHOP_VARIANTS[randi() % SHOP_VARIANTS.size()]

## 获取商品信息
static func get_item_info(key: String) -> Dictionary:
	return ITEMS.get(key, {})
