## GameConfig - 游戏配置管理器
## 统一管理所有硬编码数值，提供可配置的默认值
class_name GameConfig

# ============================================================================
# 棋盘配置
# ============================================================================

static func get_board_rows() -> int:
	return ProjectSettings.get_setting("game/board/rows", 5)

static func get_board_cols() -> int:
	return ProjectSettings.get_setting("game/board/cols", 5)

static func get_board_gap() -> float:
	return ProjectSettings.get_setting("game/board/gap", 0.12)

# ============================================================================
# 卡牌配置
# ============================================================================

static func get_card_width() -> float:
	return ProjectSettings.get_setting("game/card/width", 0.6)

static func get_card_height() -> float:
	return ProjectSettings.get_setting("game/card/height", 0.85)

static func get_card_thickness() -> float:
	return ProjectSettings.get_setting("game/card/thickness", 0.02)

# ============================================================================
# 动画时长配置
# ============================================================================

static func get_deal_animation_duration() -> float:
	return ProjectSettings.get_setting("game/animation/deal_duration", 0.35)

static func get_flip_animation_duration() -> float:
	return ProjectSettings.get_setting("game/animation/flip_duration", 0.5)

static func get_move_animation_duration() -> float:
	return ProjectSettings.get_setting("game/animation/move_duration", 0.4)

# ============================================================================
# 暗世界配置
# ============================================================================

static func get_dark_world_max_energy() -> int:
	return ProjectSettings.get_setting("game/dark_world/max_energy", 10)

static func get_dark_world_ghost_count(layer_idx: int) -> int:
	var counts: Array = ProjectSettings.get_setting("game/dark_world/ghost_counts", [2, 3, 2])
	if layer_idx >= 0 and layer_idx < counts.size():
		return counts[layer_idx]
	return 2

static func get_dark_world_ghost_chase_distance() -> int:
	return ProjectSettings.get_setting("game/dark_world/ghost_chase_distance", 2)

# ============================================================================
# 战斗配置
# ============================================================================

static func get_base_damage() -> int:
	return ProjectSettings.get_setting("game/battle/base_damage", 1)

static func get_critical_multiplier() -> float:
	return ProjectSettings.get_setting("game/battle/critical_multiplier", 1.5)

# ============================================================================
# 资源初始值
# ============================================================================

static func get_initial_sanity() -> int:
	return ProjectSettings.get_setting("game/resources/initial_sanity", 100)

static func get_initial_money() -> int:
	return ProjectSettings.get_setting("game/resources/initial_money", 50)

static func get_initial_film() -> int:
	return ProjectSettings.get_setting("game/resources/initial_film", 3)
