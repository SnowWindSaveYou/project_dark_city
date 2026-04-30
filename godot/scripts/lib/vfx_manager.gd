## VFXManager - 视觉特效管理器
## 对应原版 VFX.lua
## 在 Godot 中使用 _draw() 渲染，挂载到 CanvasLayer 上的 Control 节点
class_name VFXManager
extends Control

# ---------------------------------------------------------------------------
# 信号
# ---------------------------------------------------------------------------
signal shake_finished

# ---------------------------------------------------------------------------
# 屏幕震动 (匹配 Lua VFX.triggerShake: intensity, duration, frequency)
# ---------------------------------------------------------------------------
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_frequency: float = 25.0
var _shake_timer: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO

## 重置所有 VFX 状态 (匹配 Lua VFX.resetAll, 用于游戏重启)
func reset_all() -> void:
	_shake_intensity = 0.0
	_shake_duration = 0.0
	_shake_timer = 0.0
	shake_offset = Vector2.ZERO
	_banners.clear()
	_score_popups.clear()
	_particles.clear()
	_flash_alpha = 0.0
	queue_redraw()

## 触发屏幕震动
## intensity: 振幅 (像素级)
## duration: 持续时长 (秒), 到时间后自动停止
## frequency: 振动频率
func screen_shake(intensity: float = 6.0, duration: float = 0.4, frequency: float = 25.0) -> void:
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_timer = 0.0
	_shake_frequency = frequency

# ---------------------------------------------------------------------------
# 飞字横幅
# ---------------------------------------------------------------------------
var _banners: Array = []

## 触发飞字横幅
func action_banner(text: String, color: Color = Color.WHITE, duration: float = 1.8) -> void:
	var banner: Dictionary = {
		"text": text,
		"color": color,
		"timer": 0.0,
		"duration": duration,
		"char_offsets": [],  # 逐字偏移动画
	}
	# 初始化每个字符的偏移
	for i in range(text.length()):
		banner["char_offsets"].append({
			"y": 30.0,   # 初始向下偏移
			"alpha": 0.0,
			"delay": i * 0.04,  # 交错延迟
		})
	_banners.append(banner)

# ---------------------------------------------------------------------------
# 分数弹出
# ---------------------------------------------------------------------------
var _score_popups: Array = []

## 触发分数弹出 (4阶段: 弹性放大→稳定→上浮→淡出)
func score_popup(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	_score_popups.append({
		"pos": pos,
		"text": text,
		"color": color,
		"timer": 0.0,
		"scale": 0.0,
		"alpha": 1.0,
		"offset_y": 0.0,
		"phase": "expand",  # expand → settle → float → fade
	})

# ---------------------------------------------------------------------------
# 粒子爆发
# ---------------------------------------------------------------------------
var _particles: Array = []

## 触发粒子爆发
func spawn_burst(pos: Vector2, count: int = 8, color: Color = Color.WHITE, opts: Dictionary = {}) -> void:
	var speed: float = opts.get("speed", 80.0)
	var speed_var: float = opts.get("speed_var", 40.0)
	var life: float = opts.get("life", 0.8)
	var life_var: float = opts.get("life_var", 0.3)
	var gravity: float = opts.get("gravity", 120.0)
	var p_size: float = opts.get("size", 3.0)
	var size_var: float = opts.get("size_var", 1.5)

	for _i in range(count):
		var angle: float = randf() * TAU
		var spd: float = speed + (randf() - 0.5) * 2.0 * speed_var
		_particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle) * spd, sin(angle) * spd - opts.get("upward", 0.0)),
			"gravity": gravity,
			"life": life + (randf() - 0.5) * 2.0 * life_var,
			"max_life": life,
			"size": p_size + (randf() - 0.5) * 2.0 * size_var,
			"color": color,
		})

# ---------------------------------------------------------------------------
# 屏幕闪光
# ---------------------------------------------------------------------------
var _flash_alpha: float = 0.0
var _flash_color: Color = Color.WHITE

func screen_flash(color: Color = Color.WHITE, intensity: float = 0.6) -> void:
	_flash_alpha = intensity
	_flash_color = color

# ---------------------------------------------------------------------------
# 更新
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# 屏幕震动 (匹配 Lua updateShake: 基于 duration 的进度衰减)
	if _shake_intensity > 0.0:
		_shake_timer += delta
		var progress: float = _shake_timer / _shake_duration if _shake_duration > 0.0 else 1.0
		if progress >= 1.0:
			_shake_intensity = 0.0
			_shake_duration = 0.0
			_shake_timer = 0.0
			shake_offset = Vector2.ZERO
			shake_finished.emit()
		else:
			var decay: float = pow(1.0 - progress, 1.5)
			var amp: float = _shake_intensity * decay
			var t: float = _shake_timer * _shake_frequency
			shake_offset = Vector2(
				sin(t * 2.17 + 0.3) * amp + sin(t * 3.51) * amp * 0.3,
				cos(t * 1.73 + 0.7) * amp + cos(t * 2.89) * amp * 0.3
			)
	
	# 横幅更新
	var i: float = _banners.size() - 1
	while i >= 0:
		var b: Dictionary = _banners[i]
		b["timer"] += delta
		# 更新每个字符
		for ch in b["char_offsets"]:
			var ct: float = b["timer"] - ch["delay"]
			if ct > 0:
				ch["y"] = lerpf(ch["y"], 0.0, minf(1.0, delta * 12.0))
				ch["alpha"] = minf(ch["alpha"] + delta * 5.0, 1.0)
		if b["timer"] > b["duration"]:
			_banners.remove_at(i)
		i -= 1

	# 分数弹出更新
	i = _score_popups.size() - 1
	while i >= 0:
		var sp: Dictionary = _score_popups[i]
		sp["timer"] += delta
		match sp["phase"]:
			"expand":
				sp["scale"] = lerpf(sp["scale"], 1.0, minf(1.0, delta * 12.0))
				if sp["timer"] > 0.25:
					sp["phase"] = "settle"
			"settle":
				if sp["timer"] > 0.65:
					sp["phase"] = "float"
			"float":
				sp["offset_y"] -= 30.0 * delta
				sp["alpha"] -= 1.5 * delta
				if sp["timer"] > 1.0:
					sp["phase"] = "fade"
			"fade":
				sp["alpha"] -= 3.0 * delta
		if sp["alpha"] <= 0:
			_score_popups.remove_at(i)
		i -= 1

	# 粒子更新
	i = _particles.size() - 1
	while i >= 0:
		var p: Dictionary = _particles[i]
		p["life"] -= delta
		if p["life"] <= 0:
			_particles.remove_at(i)
		else:
			p["vel"].y += p["gravity"] * delta
			p["pos"] += p["vel"] * delta
		i -= 1

	# 屏幕闪光衰减
	if _flash_alpha > 0:
		_flash_alpha -= delta * 2.0
		if _flash_alpha < 0:
			_flash_alpha = 0

	queue_redraw()

# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------
func _draw() -> void:
	var vp_size: Vector2 = get_viewport_rect().size

	# 屏幕闪光
	if _flash_alpha > 0.01:
		var fc: Color = _flash_color
		fc.a = _flash_alpha
		draw_rect(Rect2(Vector2.ZERO, vp_size), fc)

	# 横幅
	for b in _banners:
		var text: String = b["text"]
		var cx: float = vp_size.x / 2.0
		var cy: float = vp_size.y * 0.35
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 32

		# 计算总宽度用于居中
		var total_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var start_x: float = cx - total_w / 2.0

		var char_x: float = start_x
		for ci in range(text.length()):
			var ch: String = text[ci]
			var ch_info: Dictionary = b["char_offsets"][ci]
			var ch_w: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var color: Color = b["color"]
			color.a = ch_info["alpha"]

			# 阴影
			var shadow_color: Color = Color(0, 0, 0, color.a * 0.4)
			draw_string(font, Vector2(char_x + 2, cy + ch_info["y"] + 2), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
			# 主体
			draw_string(font, Vector2(char_x, cy + ch_info["y"]), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

			char_x += ch_w

	# 分数弹出
	for sp in _score_popups:
		if sp["alpha"] <= 0:
			continue
		var color: Color = sp["color"]
		color.a = clampf(sp["alpha"], 0.0, 1.0)
		var pos: Vector2 = sp["pos"] + Vector2(0, sp["offset_y"])
		var font: Font = ThemeDB.fallback_font
		var font_size: int = int(20 * sp["scale"])
		if font_size < 1:
			continue
		# 阴影
		draw_string(font, pos + Vector2(1, 1), sp["text"],
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, color.a * 0.5))
		draw_string(font, pos, sp["text"],
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)

	# 粒子
	for p in _particles:
		var life_ratio: float = p["life"] / p["max_life"]
		var color: Color = p["color"]
		color.a = life_ratio
		var s: float = p["size"] * life_ratio
		draw_circle(p["pos"], s, color)
