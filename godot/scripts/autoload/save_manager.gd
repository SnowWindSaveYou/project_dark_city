## SaveManager — 本地存档管理 (autoload)
##
## 职责:
## - 保存 / 加载玩家进度 (结局解锁、最佳成绩)
## - 数据写入 user://save_data.cfg
## - 提供简洁 API 供 GameOver 和 Gallery 调用
extends Node

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const SAVE_PATH: String = "user://save_data.cfg"

# ---------------------------------------------------------------------------
# 内存数据 (启动时从磁盘加载)
# ---------------------------------------------------------------------------

## 已解锁的结局 id 列表，如 ["companion", "default"]
var unlocked_endings: Array[String] = []

## 最佳统计 (最高存活天数、最多翻牌等)
var best_stats: Dictionary = {
	"days_survived": 0,
	"cards_revealed": 0,
	"monsters_slain": 0,
	"photos_used": 0,
}

## 总游戏次数
var total_runs: int = 0

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	load_data()


# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 游戏结束时调用：解锁结局、更新最佳成绩、保存
func record_run(ending_id: String, stats: Dictionary) -> void:
	total_runs += 1

	# 解锁结局
	if ending_id != "" and not unlocked_endings.has(ending_id):
		unlocked_endings.append(ending_id)

	# 更新最佳成绩 (各项取最大值)
	for key in best_stats.keys():
		var val: int = stats.get(key, 0)
		if val > best_stats[key]:
			best_stats[key] = val

	save_data()


## 返回是否已解锁某结局
func is_ending_unlocked(ending_id: String) -> bool:
	return unlocked_endings.has(ending_id)


## 重置所有存档数据 (调试用)
func reset_save() -> void:
	unlocked_endings.clear()
	best_stats = {
		"days_survived": 0,
		"cards_revealed": 0,
		"monsters_slain": 0,
		"photos_used": 0,
	}
	total_runs = 0
	save_data()


# ---------------------------------------------------------------------------
# 读写
# ---------------------------------------------------------------------------

func save_data() -> void:
	var cfg: ConfigFile = ConfigFile.new()

	cfg.set_value("progress", "unlocked_endings", unlocked_endings)
	cfg.set_value("progress", "total_runs", total_runs)

	for key in best_stats.keys():
		cfg.set_value("best_stats", key, best_stats[key])

	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("SaveManager: 写入失败 (%d)" % err)


func load_data() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(SAVE_PATH)
	if err != OK:
		return  # 首次运行，保持默认值

	var saved_endings = cfg.get_value("progress", "unlocked_endings", [])
	unlocked_endings.clear()
	for e in saved_endings:
		if e is String:
			unlocked_endings.append(e)

	total_runs = cfg.get_value("progress", "total_runs", 0)

	for key in best_stats.keys():
		best_stats[key] = cfg.get_value("best_stats", key, 0)
