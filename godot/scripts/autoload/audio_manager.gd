extends Node
## AudioManager — 全局音频管理器 (autoload)
##
## 功能:
## - BGM 播放/停止/交叉淡入淡出
## - SFX 单次播放 (对象池, 自动回收)
## - SFX key → 文件路径映射 (data/audio_config.json)
## - 音量独立控制 (BGM / SFX)
## - Combo 音调递增 (可选)

# ─── 常量 ─────────────────────────────────────────────
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
var _bgm_volume: float = 0.3
var _bgm_fading: bool = false
var _fade_timer: float = 0.0
var _fade_out_player: AudioStreamPlayer = null
var _fade_in_player: AudioStreamPlayer = null

# ─── SFX ──────────────────────────────────────────────
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_volume: float = 0.5

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
	_load_audio_config()
	_setup_bgm_players()
	_setup_sfx_pool()


func _load_audio_config() -> void:
	var path: String = "res://data/audio_config.json"
	if not FileAccess.file_exists(path):
		# 无配置文件时使用内置默认映射
		_apply_default_mapping()
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_apply_default_mapping()
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("AudioManager: audio_config.json parse error: %s" % json.get_error_message())
		_apply_default_mapping()
		return

	var data: Dictionary = json.data if json.data is Dictionary else {}
	bgm_map = data.get("bgm", {})
	sfx_map = data.get("sfx", {})


func _apply_default_mapping() -> void:
	# 基于 Lua 版实际引用的 SFX key，映射到已有的 .ogg 文件
	sfx_map = {
		"day_transition": "res://assets/audio/sfx/day_transition_new.ogg",
		"item_use": "res://assets/audio/sfx/item_use.ogg",
		"item_use_coffee": "res://assets/audio/sfx/item_use_coffee.ogg",
		"item_use_fail": "res://assets/audio/sfx/item_use_fail.ogg",
		"item_use_map": "res://assets/audio/sfx/item_use_map.ogg",
		"item_use_order": "res://assets/audio/sfx/item_use_order.ogg",
		"item_use_sedative": "res://assets/audio/sfx/item_use_sedative.ogg",
	}
	bgm_map = {
		"main": "res://assets/audio/music_1777730398385.ogg",
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
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = linear_to_db(_sfx_volume)
		add_child(player)
		_sfx_pool.append(player)


# ─── BGM 接口 ─────────────────────────────────────────

## 播放 BGM (通过 key 或直接路径)
func play_bgm(key_or_path: String, loop: bool = true) -> void:
	if key_or_path == _current_bgm_key and _active_bgm != null and _active_bgm.playing:
		return  # 同一曲目不重复播放

	var path: String = bgm_map.get(key_or_path, key_or_path)
	var stream := _load_stream(path)
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


## 设置 BGM 音量 (0.0 - 1.0)
func set_bgm_volume(vol: float) -> void:
	_bgm_volume = clampf(vol, 0.0, 1.0)
	if _active_bgm != null and not _bgm_fading:
		_active_bgm.volume_db = linear_to_db(_bgm_volume)


# ─── SFX 接口 ─────────────────────────────────────────

## 播放 SFX (通过 key 或直接路径)
func play_sfx(key_or_path: String, volume: float = -1.0, combo: bool = false) -> void:
	var path: String = sfx_map.get(key_or_path, key_or_path)
	var stream := _load_stream(path)
	if stream == null:
		# 静默忽略缺失的音效（可能尚未制作）
		return

	var player := _get_free_sfx_player()
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


## 设置 SFX 音量 (0.0 - 1.0)
func set_sfx_volume(vol: float) -> void:
	_sfx_volume = clampf(vol, 0.0, 1.0)


## 重置 Combo
func reset_combo() -> void:
	_combo_level = 0


# ─── 内部实现 ─────────────────────────────────────────

func _process(delta: float) -> void:
	# Combo 超时重置
	if _combo_level > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_level = 0

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


func _get_free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	return null  # 所有播放器都在使用中


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream
