## WeatherParticles - 天气粒子特效
## 对应原版 Weather.lua FX 部分
## 使用 Control._draw() 每帧绘制降水粒子，挂在独立 CanvasLayer 上
class_name WeatherParticles
extends Control

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
const MAX_RAIN:  int = 80
const MAX_STORM: int = 120

# ---------------------------------------------------------------------------
# 运行时状态
# ---------------------------------------------------------------------------
var _particles:      Array   = []
var _thunder_timer:  float   = 0.0
var _light_flash:    float   = 0.0
var _last_type:      int     = -1  # -1 = 未初始化
var _current_type:   int     = -1  # Weather.Type 当前天气

# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_thunder_timer = 6.0 + randf() * 12.0

# ---------------------------------------------------------------------------
# 外部接口
# ---------------------------------------------------------------------------

## 设置当前天气类型 (Weather.Type int)
func set_weather(weather_type: int) -> void:
	_current_type = weather_type

## 重置所有粒子状态 (游戏重启时调用)
func reset() -> void:
	_particles.clear()
	_light_flash    = 0.0
	_thunder_timer  = 6.0 + randf() * 12.0
	_last_type      = -1
	_current_type   = -1
	queue_redraw()

# ---------------------------------------------------------------------------
# 每帧更新
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var is_rain: bool = (
		_current_type == Weather.Type.RAINY or
		_current_type == Weather.Type.STORMY
	)

	# 非降水: 清空粒子后跳过
	if not is_rain:
		if not _particles.is_empty():
			_particles.clear()
			_light_flash = 0.0
			queue_redraw()
		_last_type = _current_type
		return

	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return

	var target_count: int = MAX_STORM if _current_type == Weather.Type.STORMY else MAX_RAIN

	# 天气类型变化: 清空重建
	if _last_type != _current_type:
		_particles.clear()
		_thunder_timer = 6.0 + randf() * 12.0
	_last_type = _current_type

	# 填充粒子池 (首批散布在屏幕上，后续从顶部补入)
	var scattered: bool = _particles.size() >= int(target_count * 0.45)
	while _particles.size() < target_count:
		_particles.append(_make_rain_drop(w, h, scattered))
		scattered = true

	# 更新位置
	var i: int = 0
	while i < _particles.size():
		var p: Dictionary = _particles[i]
		p.x += p.vx * delta
		p.y += p.vy * delta
		if p.y > h + 60.0 or p.x < -180.0:
			_particles[i] = _make_rain_drop(w, h, true)
		i += 1

	# 雷暴: 随机闪电 + 雷声
	if _current_type == Weather.Type.STORMY:
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_timer = 10.0 + randf() * 18.0
			_light_flash = 0.9
			AudioManager.play_sfx("weather_thunder")

	# 闪电衰减
	if _light_flash > 0.0:
		_light_flash = maxf(0.0, _light_flash - delta * 5.0)

	queue_redraw()

# ---------------------------------------------------------------------------
# 粒子生成
# ---------------------------------------------------------------------------

func _make_rain_drop(w: float, h: float, from_top: bool) -> Dictionary:
	var is_storm: bool = (_current_type == Weather.Type.STORMY)
	return {
		"x":   randf() * (w + 200.0) - 100.0,
		"y":   (-randf() * 40.0) if from_top else (randf() * h),
		"vx":  -(75.0 + randf() * 95.0) if is_storm else -(15.0 + randf() * 28.0),
		"vy":  (360.0 + randf() * 190.0) if is_storm else (245.0 + randf() * 125.0),
		"len": (10.0 + randf() * 11.0)  if is_storm else (6.0  + randf() * 7.0),
		"a":   (135 + randi() % 85)     if is_storm else (90  + randi() % 80),
		"lw":  (1.0 + randf() * 0.6)   if is_storm else (0.7  + randf() * 0.4),
	}

# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _particles.is_empty():
		return

	var w: float = size.x
	var h: float = size.y
	var is_storm: bool = (_current_type == Weather.Type.STORMY)

	# 闪电白色叠加层
	if is_storm and _light_flash > 0.0:
		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.84, 0.89, 1.0, _light_flash * 0.2))

	# 顶部薄雾渐变 (简化为半透明矩形)
	var fog_a: float = 0.16 if is_storm else 0.08
	draw_rect(Rect2(0.0, 0.0, w, h * 0.25), Color(0.63, 0.75, 0.86, fog_a * 0.5))

	# 雨滴颜色
	var base_r: float = 0.59 if is_storm else 0.67
	var base_g: float = 0.71 if is_storm else 0.82
	var base_b: float = 0.88 if is_storm else 0.99

	for p: Dictionary in _particles:
		var a: float = p.a / 255.0
		if a <= 0.0:
			continue
		var spd: float = sqrt(p.vx * p.vx + p.vy * p.vy)
		if spd > 0.01:
			var nx: float = p.vx / spd
			var ny: float = p.vy / spd
			draw_line(
				Vector2(p.x, p.y),
				Vector2(p.x + nx * p.len, p.y + ny * p.len),
				Color(base_r, base_g, base_b, a),
				p.lw
			)
