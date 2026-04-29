## WeatherSystem - 天气系统
## 管理暗面世界的天气效果
class_name WeatherSystem
extends RefCounted

# ============================================================================
# 天气类型
# ============================================================================

enum WeatherType {
	CLEAR = 0,      # 晴朗
	FOG = 1,        # 迷雾
	RAIN = 2,       # 暴雨
	STORM = 3,      # 风暴
	GHOST_WIND = 4, # 幽风
}

# ============================================================================
# 天气效果参数
# ============================================================================

## 天气对游戏的影响系数
static func get_weather_effect(type: WeatherType) -> Dictionary:
	match type:
		WeatherType.CLEAR:
			return {
				"ghost_speed_mod": 1.0,
				"visibility_mod": 1.0,
				"energy_cost_mod": 1.0,
				"description": "晴朗的天空"
			}
		WeatherType.FOG:
			return {
				"ghost_speed_mod": 0.7,
				"visibility_mod": 0.6,
				"energy_cost_mod": 1.2,
				"description": "浓雾弥漫，能见度降低"
			}
		WeatherType.RAIN:
			return {
				"ghost_speed_mod": 0.8,
				"visibility_mod": 0.7,
				"energy_cost_mod": 1.5,
				"description": "暴雨倾盆，行动困难"
			}
		WeatherType.STORM:
			return {
				"ghost_speed_mod": 1.3,
				"visibility_mod": 0.4,
				"energy_cost_mod": 2.0,
				"description": "狂风骤雨，危险加剧"
			}
		WeatherType.GHOST_WIND:
			return {
				"ghost_speed_mod": 1.5,
				"visibility_mod": 0.5,
				"energy_cost_mod": 1.0,
				"description": "幽风阵阵，灵体躁动"
			}
	return {
		"ghost_speed_mod": 1.0,
		"visibility_mod": 1.0,
		"energy_cost_mod": 1.0,
		"description": "未知天气"
	}

# ============================================================================
# 天气状态
# ============================================================================

var current_weather: WeatherType = WeatherType.CLEAR
var weather_duration: float = 0.0
var weather_transition_progress: float = 0.0

# ============================================================================
# 天气更新
# ============================================================================

## 每帧更新天气状态
func update(dt: float) -> void:
	if weather_duration > 0.0:
		weather_duration -= dt
		weather_transition_progress = clampf(weather_duration / 10.0, 0.0, 1.0)

## 切换天气
func change_weather(new_weather: WeatherType, duration: float = 30.0) -> void:
	current_weather = new_weather
	weather_duration = duration
	weather_transition_progress = 1.0

## 获取当前天气效果
func get_current_effect() -> Dictionary:
	return get_weather_effect(current_weather)

## 获取幽灵速度修正
func get_ghost_speed_mod() -> float:
	return get_current_effect().get("ghost_speed_mod", 1.0)

## 获取能量消耗修正
func get_energy_cost_mod() -> float:
	return get_current_effect().get("energy_cost_mod", 1.0)
