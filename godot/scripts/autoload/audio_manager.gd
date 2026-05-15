extends Node
## AudioManager — 全局音频管理器 (autoload)
##
## 功能:
## - BGM 播放/停止/交叉淡入淡出
## - SFX 单次播放 (对象池, 自动回收)
## - SFX key → 文件路径映射 (data/audio_config.json)
## - 音量独立控制 (BGM / SFX)
## - Combo 音调递增 (可选)
## - 设置持久化 (user://audio_settings.cfg)

# ─── 常量 ─────────────────────────────────────────────
const SETTINGS_PATH: String = "user://audio_settings.cfg"
const MAX_SFX_POOL: int = 12
const BGM_FADE_TIME: float = 1.5
const COMBO_PITCH_STEP: float = 0.06  # 每级 +6%
const COMBO_MAX_LEVEL: int = 5
const PITCH_RANDOM_RANGE: float = 0.04  # +/-4%

# ─── BGM ──────────────────────────────────────────────
var _bgm_player_a: AudioStreamPlayer = null
var _bgm_player_b: AudioStreamPlayer = null
var _active_bgm: AudioStreamPlayer = null
var _current_bgm_key: String = ""
var _next_bgm_key: String = ""     # 交叉淡入中的目标曲目 key (用于 skip 判断)
var _bgm_volume: float = 0.3
var _bgm_fading: bool = false
var _fade_timer: float = 0.0
var _fade_out_player: AudioStreamPlayer = null
var _fade_in_player: AudioStreamPlayer = null

# ─── SFX ──────────────────────────────────────────────
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_volume: float = 0.5

# ─── Ambient (循环环境音，如雨声/风声) ────────────────
var _ambient_player: AudioStreamPlayer = null
var _current_ambient_key: String = ""
var _ambient_volume: float = 0.25
var _ambient_fading: bool = false
var _ambient_fade_timer: float = 0.0
var _ambient_fade_target: float = 0.0
const AMBIENT_FADE_TIME: float = 1.2

# ─── Combo ────────────────────────────────────────────
var _combo_level: int = 0
var _combo_timer: float = 0.0
const COMBO_TIMEOUT: float = 1.5  # 连击超时重置

# ─── 映射表 ───────────────────────────────────────────
## bgm_map:  { "day_light": "res://assets/audio/bgm_day.ogg", ... }
## sfx_map:  { "card_flip": "res://assets/audio/sfx/card_flip.ogg", ... }
var bgm_map: Dictionary = {}
var sfx_map: Dictionary = {}

# ─── 初始化 ───────────────────────────────────────────

func _ready() -> void:
	_load_settings()
	_load_audio_config()
	_setup_bgm_players()
	_setup_sfx_pool()


func _load_audio_config() -> void:
	var path: String = "res://data/audio_config.json"
	if not FileAccess.file_exists(path):
		# 无配置文件时使用内置默认映射
		_apply_default_mapping()
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_apply_default_mapping()
		return

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("AudioManager: audio_config.json parse error: %s" % json.get_error_message())
		_apply_default_mapping()
		return

	var data: Dictionary = json.data if json.data is Dictionary else {}
	bgm_map = data.get("bgm", {})
	sfx_map = data.get("sfx", {})


func _apply_default_mapping() -> void:
	# 映射到 assets/audio/ 下的 LFS 音频（godot/assets/audio 是该目录的 symlink）
	sfx_map = {
		# UI / 通用交互
		"button_click":      "res://assets/audio/sfx/btn_click.ogg",
		"popup_open":        "res://assets/audio/sfx/popup_open.ogg",
		"popup_close":       "res://assets/audio/sfx/popup_close.ogg",
		"banner_text":       "res://assets/audio/sfx/banner_text.ogg",
		"notebook_open":     "res://assets/audio/sfx/notebook_open.ogg",
		"notebook_close":    "res://assets/audio/sfx/notebook_close.ogg",
		# 卡牌操作
		"card_flip":         "res://assets/audio/sfx/card_flip.ogg",
		"card_deal":         "res://assets/audio/sfx/card_deal.ogg",
		"card_shake":        "res://assets/audio/sfx/card_shake.ogg",
		"card_transform":    "res://assets/audio/sfx/card_transform.ogg",
		# 相机系统
		"camera_enter":      "res://assets/audio/sfx/camera_enter.ogg",
		"camera_exit":       "res://assets/audio/sfx/camera_exit.ogg",
		"camera_shutter":    "res://assets/audio/sfx/camera_shutter.ogg",
		"viewfinder_hum":    "res://assets/audio/sfx/viewfinder_hum.ogg",
		"film_empty":        "res://assets/audio/sfx/film_empty.ogg",
		# 日夜/关卡流程
		"day_transition":    "res://assets/audio/sfx/day_transition.ogg",
		"layer_transition":  "res://assets/audio/sfx/layer_transition.ogg",
		# 暗世界
		"dark_world_enter":  "res://assets/audio/sfx/rift_enter.ogg",
		"dark_world_exit":   "res://assets/audio/sfx/rift_exit.ogg",
		"dark_ambient":      "res://assets/audio/sfx/dark_ambient.ogg",
		"ghost_encounter":   "res://assets/audio/sfx/evt_monster.ogg",
		"ghost_hit":         "res://assets/audio/sfx/ghost_hit.ogg",
		"ghost_dispel":      "res://assets/audio/sfx/ghost_dispel.ogg",
		"exorcise":          "res://assets/audio/sfx/exorcise.ogg",
		# 事件
		"story_event":       "res://assets/audio/sfx/banner_text.ogg",
		"npc_talk":          "res://assets/audio/sfx/popup_open.ogg",
		"evt_safe":          "res://assets/audio/sfx/evt_safe.ogg",
		"evt_trap":          "res://assets/audio/sfx/evt_trap.ogg",
		"evt_reward":        "res://assets/audio/sfx/evt_reward.ogg",
		"evt_plot":          "res://assets/audio/sfx/evt_plot.ogg",
		"evt_clue":          "res://assets/audio/sfx/evt_clue.ogg",
		"evt_photo":         "res://assets/audio/sfx/evt_photo.ogg",
		"evt_monster":       "res://assets/audio/sfx/evt_monster.ogg",
		# 资源
		"resource_gain":     "res://assets/audio/sfx/resource_gain.ogg",
		"resource_lose":     "res://assets/audio/sfx/resource_lose.ogg",
		"token_jump":        "res://assets/audio/sfx/token_jump.ogg",
		"item_pickup":       "res://assets/audio/sfx/item_pickup.ogg",
		# 道具使用
		"item_use":          "res://assets/audio/sfx/item_use.ogg",
		"item_use_coffee":   "res://assets/audio/sfx/item_use.ogg",
		"item_use_map":      "res://assets/audio/sfx/item_use.ogg",
		"item_use_order":    "res://assets/audio/sfx/item_use.ogg",
		"item_use_sedative": "res://assets/audio/sfx/item_use.ogg",
		"item_use_shield":   "res://assets/audio/sfx/item_use_shield.ogg",
		"item_use_fail":     "res://assets/audio/sfx/item_use_fail.ogg",
		# 商店
		"shop_buy":          "res://assets/audio/sfx/shop_buy.ogg",
		"shop_refresh":      "res://assets/audio/sfx/shop_refresh.ogg",
		"shop_reject":       "res://assets/audio/sfx/shop_reject.ogg",
		# 结局
		"ending_reveal":     "res://assets/audio/sfx/defeat_sting.ogg",
		"defeat_sting":      "res://assets/audio/sfx/defeat_sting.ogg",
		"victory_sting":     "res://assets/audio/sfx/victory_sting.ogg",
		# 特效
		"screen_flash":      "res://assets/audio/sfx/screen_flash.ogg",
		"screen_shake":      "res://assets/audio/sfx/screen_shake.ogg",
		# 天气
		"weather_rain":      "res://assets/audio/sfx/weather_rain.ogg",
		"weather_thunder":   "res://assets/audio/sfx/weather_thunder.ogg",
		"weather_wind":      "res://assets/audio/sfx/weather_wind.ogg",
	}
	bgm_map = {
		"main":       "res://assets/audio/bgm_day_light.ogg",
		"day_light":  "res://assets/audio/bgm_day_light.ogg",
		"day_dark":   "res://assets/audio/bgm_day_dark.ogg",
		"dark_world": "res://assets/audio/bgm_dark_world.ogg",
		"defeat":     "res://assets/audio/bgm_defeat.ogg",
		"victory":    "res://assets/audio/bgm_victory.ogg",
	}


func _setup_bgm_players() -> void:
	_bgm_player_a = AudioStreamPlayer.new()
	_bgm_player_a.bus = "Music"
	_bgm_player_a.volume_db = linear_to_db(_bgm_volume)
	add_child(_bgm_player_a)

	_bgm_player_b = AudioStreamPlayer.new()
	_bgm_player_b.bus = "Music"
	_bgm_player_b.volume_db = linear_to_db(0.0)
	add_child(_bgm_player_b)

	_active_bgm = _bgm_player_a


func _setup_sfx_pool() -> void:
	for i in range(MAX_SFX_POOL):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = linear_to_db(_sfx_volume)
		add_child(player)
		_sfx_pool.append(player)

	# Ambient 播放器 (独立节点，循环播放)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "SFX"
	_ambient_player.volume_db = linear_to_db(0.0)
	add_child(_ambient_player)


# ─── BGM 接口 ─────────────────────────────────────────

## 播放 BGM (通过 key 或直接路径)
func play_bgm(key_or_path: String, loop: bool = true) -> void:
	# 已在播放该曲目, 或已在向该曲目交叉淡入中 → 忽略
	# (防止 _process 每帧调用在淡入期间反复打断, 导致音乐静音)
	if key_or_path == _current_bgm_key or key_or_path == _next_bgm_key:
		return

	var path: String = bgm_map.get(key_or_path, key_or_path)
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		push_warning("AudioManager: BGM not found: %s" % path)
		return

	# 交叉淡入淡出
	if _active_bgm != null and _active_bgm.playing:
		_start_crossfade(stream, loop)
	else:
		# 直接播放
		if _active_bgm == null:
			_active_bgm = _bgm_player_a
		_active_bgm.stream = stream
		_active_bgm.volume_db = linear_to_db(_bgm_volume)
		_active_bgm.play()

	_current_bgm_key = key_or_path


## 停止 BGM
func stop_bgm(fade: bool = true) -> void:
	if _active_bgm == null or not _active_bgm.playing:
		_current_bgm_key = ""
		return

	if fade:
		_fade_out_player = _active_bgm
		_fade_in_player = null
		_bgm_fading = true
		_fade_timer = 0.0
	else:
		_active_bgm.stop()

	_current_bgm_key = ""


## 设置 BGM 音量 (0.0 - 1.0) 并持久化
func set_bgm_volume(vol: float) -> void:
	_bgm_volume = clampf(vol, 0.0, 1.0)
	if _active_bgm != null and not _bgm_fading:
		_active_bgm.volume_db = linear_to_db(_bgm_volume)
	save_settings()


# ─── SFX 接口 ─────────────────────────────────────────

## 播放 SFX (通过 key 或直接路径)
func play_sfx(key_or_path: String, volume: float = -1.0, combo: bool = false) -> void:
	var path: String = sfx_map.get(key_or_path, key_or_path)
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		# 静默忽略缺失的音效（可能尚未制作）
		return

	var player: AudioStreamPlayer = _get_free_sfx_player()
	if player == null:
		return  # 池已满

	player.stream = stream

	# 音量
	var vol: float = volume if volume >= 0.0 else _sfx_volume
	player.volume_db = linear_to_db(vol)

	# 音调: combo 递增 或 随机微调
	if combo:
		_combo_level = mini(_combo_level + 1, COMBO_MAX_LEVEL)
		_combo_timer = COMBO_TIMEOUT
		player.pitch_scale = 1.0 + _combo_level * COMBO_PITCH_STEP
	else:
		player.pitch_scale = 1.0 + randf_range(-PITCH_RANDOM_RANGE, PITCH_RANDOM_RANGE)

	player.play()


## 设置 SFX 音量 (0.0 - 1.0) 并持久化
func set_sfx_volume(vol: float) -> void:
	_sfx_volume = clampf(vol, 0.0, 1.0)
	# 同步更新池中所有闲置播放器音量 (Godot 不像 Lua 需要手动批量同步)
	for p: AudioStreamPlayer in _sfx_pool:
		if not p.playing:
			p.volume_db = linear_to_db(_sfx_volume)
	save_settings()


## 重置 Combo
func reset_combo() -> void:
	_combo_level = 0


# ─── Ambient 接口 ──────────────────────────────────────

## 播放循环环境音 (key 为空字符串时等同于 stop_ambient)
func play_ambient(key: String) -> void:
	if key == _current_ambient_key and _ambient_player != null and _ambient_player.playing:
		return  # 已在播放同一音效，不重复触发

	if key.is_empty():
		stop_ambient()
		return

	var path: String = sfx_map.get(key, key)
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		# 静默忽略（音效文件可能尚未制作）
		_current_ambient_key = ""
		return

	if _ambient_player != null:
		# 停止旧音轨（直接切换；ambient 通常是背景环境音，无需交叉淡入淡出）
		if _ambient_player.playing:
			_ambient_player.stop()

		# 确保流支持循环（必须 duplicate() 避免污染 ResourceCache 共享实例）
		stream = stream.duplicate() as AudioStream
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true

		_ambient_player.stream = stream
		_ambient_player.volume_db = linear_to_db(0.0)
		_ambient_player.play()
		# 淡入到目标音量
		_ambient_fading = true
		_ambient_fade_timer = 0.0
		_ambient_fade_target = _ambient_volume

	_current_ambient_key = key


## 停止循环环境音 (带淡出)
func stop_ambient(instant: bool = false) -> void:
	if _ambient_player == null or not _ambient_player.playing:
		_current_ambient_key = ""
		return

	if instant:
		_ambient_player.stop()
		_current_ambient_key = ""
		return

	# 淡出
	_ambient_fading = true
	_ambient_fade_timer = 0.0
	_ambient_fade_target = 0.0
	_current_ambient_key = ""


# ─── 内部实现 ─────────────────────────────────────────

func _process(delta: float) -> void:
	# Combo 超时重置
	if _combo_level > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_level = 0

	# Ambient 淡入/淡出
	if _ambient_fading and _ambient_player != null:
		_ambient_fade_timer += delta
		var t: float = clampf(_ambient_fade_timer / AMBIENT_FADE_TIME, 0.0, 1.0)
		var cur_vol: float = lerpf(
			db_to_linear(_ambient_player.volume_db),
			_ambient_fade_target,
			t
		)
		_ambient_player.volume_db = linear_to_db(cur_vol)
		if t >= 1.0:
			_ambient_fading = false
			if _ambient_fade_target <= 0.0 and _ambient_player.playing:
				_ambient_player.stop()

	# BGM 交叉淡入淡出
	if _bgm_fading:
		_fade_timer += delta
		var t: float = clampf(_fade_timer / BGM_FADE_TIME, 0.0, 1.0)

		if _fade_out_player != null:
			_fade_out_player.volume_db = linear_to_db(_bgm_volume * (1.0 - t))

		if _fade_in_player != null:
			_fade_in_player.volume_db = linear_to_db(_bgm_volume * t)

		if t >= 1.0:
			_bgm_fading = false
			if _fade_out_player != null:
				_fade_out_player.stop()
			if _fade_in_player != null:
				_active_bgm = _fade_in_player
			_fade_out_player = null
			_fade_in_player = null
			_next_bgm_key = ""  # 交叉完成, 清空过渡目标标记


func _start_crossfade(stream: AudioStream, loop: bool) -> void:
	# 选择非活跃播放器作为淡入目标
	var next_player: AudioStreamPlayer
	if _active_bgm == _bgm_player_a:
		next_player = _bgm_player_b
	else:
		next_player = _bgm_player_a

	next_player.stream = stream
	next_player.volume_db = linear_to_db(0.0)
	next_player.play()

	_fade_out_player = _active_bgm
	_fade_in_player = next_player
	_bgm_fading = true
	_fade_timer = 0.0
	# _next_bgm_key 已在 play_bgm 末尾通过 _current_bgm_key 更新, 此处保持同步
	_next_bgm_key = _current_bgm_key


func _get_free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	return null  # 所有播放器都在使用中


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


# ─── 设置持久化 ───────────────────────────────────────

## 将 BGM/SFX 音量保存到 user://audio_settings.cfg
func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "bgm_volume", _bgm_volume)
	cfg.set_value("audio", "sfx_volume", _sfx_volume)
	cfg.save(SETTINGS_PATH)


## 从 user://audio_settings.cfg 加载音量设置 (初始化时调用)
func _load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(SETTINGS_PATH)
	if err != OK:
		return  # 文件不存在则保持默认值
	_bgm_volume = clampf(cfg.get_value("audio", "bgm_volume", _bgm_volume), 0.0, 1.0)
	_sfx_volume = clampf(cfg.get_value("audio", "sfx_volume", _sfx_volume), 0.0, 1.0)


## 获取当前 BGM 音量 (0.0 - 1.0)
func get_bgm_volume() -> float:
	return _bgm_volume


## 获取当前 SFX 音量 (0.0 - 1.0)
func get_sfx_volume() -> float:
	return _sfx_volume
