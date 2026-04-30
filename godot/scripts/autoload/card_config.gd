## CardConfig - 卡牌 & 商店 & 日程配置加载器 (Autoload)
## 从 data/card_config.json 加载所有卡牌相关数据表
extends Node

# ---------------------------------------------------------------------------
# 卡牌数据表 (原 Card.gd 常量)
# ---------------------------------------------------------------------------
var location_info: Dictionary = {}
var event_weights: Dictionary = {}
var trap_subtype_info: Dictionary = {}
var darkside_info: Dictionary = {}
var card_effects: Dictionary = {}
var event_texts: Dictionary = {}
var trap_subtype_texts: Dictionary = {}

# ---------------------------------------------------------------------------
# 卡牌类型显示 (原 Theme.gd 常量)
# ---------------------------------------------------------------------------
var card_types: Dictionary = {}
var dark_card_types: Dictionary = {}

# ---------------------------------------------------------------------------
# 日程 & 传闻 (原 CardManager.gd 常量)
# ---------------------------------------------------------------------------
var schedule_templates: Dictionary = {}
var rumor_safe_texts: Array = []
var rumor_danger_texts: Array = []

# ---------------------------------------------------------------------------
# 商店 (原 ShopData.gd 常量)
# ---------------------------------------------------------------------------
var shop_items: Dictionary = {}
var consumable_order: Array = []
var shop_variants: Array = []
var shop_refresh_cost: int = 5

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_card_config()

func _load_card_config() -> void:
	var file := FileAccess.open("res://data/card_config.json", FileAccess.READ)
	if file == null:
		push_error("CardConfig: 无法打开 data/card_config.json")
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("CardConfig: JSON 解析失败: %s (行 %d)" % [json.get_error_message(), json.get_error_line()])
		return

	var data: Dictionary = json.data
	if not data is Dictionary:
		push_error("CardConfig: JSON 根节点必须是 Dictionary")
		return

	# 卡牌数据表
	location_info      = data.get("location_info", {})
	event_weights      = data.get("event_weights", {})
	trap_subtype_info  = data.get("trap_subtype_info", {})
	darkside_info      = data.get("darkside_info", {})
	card_effects       = data.get("card_effects", {})
	event_texts        = data.get("event_texts", {})
	trap_subtype_texts = data.get("trap_subtype_texts", {})

	# 卡牌类型显示
	card_types         = data.get("card_types", {})
	dark_card_types    = data.get("dark_card_types", {})

	# 日程 & 传闻
	schedule_templates = data.get("schedule_templates", {})
	rumor_safe_texts   = data.get("rumor_safe_texts", [])
	rumor_danger_texts = data.get("rumor_danger_texts", [])

	# 商店
	shop_items         = data.get("shop_items", {})
	consumable_order   = data.get("consumable_order", [])
	shop_variants      = data.get("shop_variants", [])
	shop_refresh_cost  = data.get("shop_refresh_cost", 5)

	# 将 trap_subtype_info 中的 effect 值转为 int (JSON 解析为 float)
	for key in trap_subtype_info:
		var info: Dictionary = trap_subtype_info[key]
		if info.has("effect"):
			info["effect"] = _convert_to_int_dict(info["effect"])

	# 将 card_effects 中的值转为 int
	for key in card_effects:
		card_effects[key] = _convert_to_int_dict(card_effects[key])

	# 将 shop_items 中的 effect/price 转为 int
	for key in shop_items:
		var item: Dictionary = shop_items[key]
		if item.has("price"):
			item["price"] = int(item["price"])
		if item.has("effect"):
			item["effect"] = _convert_to_int_dict(item["effect"])

	# 将 event_weights 转为 int
	for key in event_weights:
		event_weights[key] = int(event_weights[key])

	# 将 schedule_templates 的 reward[1] 转为 int
	for key in schedule_templates:
		var tmpl: Dictionary = schedule_templates[key]
		if tmpl.has("reward"):
			var reward: Array = tmpl["reward"]
			if reward.size() >= 2:
				reward[1] = int(reward[1])

	shop_refresh_cost = int(shop_refresh_cost)

## JSON float → int 转换辅助
func _convert_to_int_dict(d: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for k in d:
		result[k] = int(d[k])
	return result
