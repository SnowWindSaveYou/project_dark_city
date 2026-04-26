## Weather - 天气系统
## 对应原版 Weather.lua
## 确定性天气生成 (基于 dayCount 的哈希)
class_name Weather
extends RefCounted

# ---------------------------------------------------------------------------
# 天气类型枚举
# ---------------------------------------------------------------------------
enum Type {
	SUNNY,
	PARTLY_CLOUDY,
	CLOUDY,
	RAINY,
	STORMY,
}

# ---------------------------------------------------------------------------
# 天气名称
# ---------------------------------------------------------------------------
const NAMES := {
	Type.SUNNY:         "晴",
	Type.PARTLY_CLOUDY: "多云",
	Type.CLOUDY:        "阴",
	Type.RAINY:         "雨",
	Type.STORMY:        "雷暴",
}

const ICONS := {
	Type.SUNNY:         "☀️",
	Type.PARTLY_CLOUDY: "⛅",
	Type.CLOUDY:        "☁️",
	Type.RAINY:         "🌧️",
	Type.STORMY:        "⛈️",
}

# ---------------------------------------------------------------------------
# 确定性天气生成
# ---------------------------------------------------------------------------

## 基于 dayCount 的确定性哈希，同一天永远返回相同天气
static func get_weather(day_count: int) -> Type:
	# 与 Lua 版相同的哈希算法
	var hash: int = ((day_count * 2654435761) % 2147483647) % 100
	if hash < 0:
		hash += 100
	if hash < 30:
		return Type.SUNNY
	elif hash < 50:
		return Type.PARTLY_CLOUDY
	elif hash < 72:
		return Type.CLOUDY
	elif hash < 90:
		return Type.RAINY
	else:
		return Type.STORMY

## 获取天气名称
static func get_name(weather_type: Type) -> String:
	return NAMES.get(weather_type, "未知")

## 获取天气图标
static func get_icon(weather_type: Type) -> String:
	return ICONS.get(weather_type, "❓")

# ---------------------------------------------------------------------------
# 日期计算 (与 DateTransition 共享)
# ---------------------------------------------------------------------------

const BASE_YEAR  := 2026
const BASE_MONTH := 4
const BASE_DAY   := 24
const WEEKDAY_NAMES := ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
const MONTH_NAMES := [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

static func is_leap_year(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)

static func days_in_month(y: int, m: int) -> int:
	if m == 2 and is_leap_year(y):
		return 29
	return DAYS_IN_MONTH[m - 1]

## 计算日期 (dayCount → year, month, day)
static func calc_date(day_count: int) -> Dictionary:
	var y := BASE_YEAR
	var m := BASE_MONTH
	var d := BASE_DAY + (day_count - 1)
	while d < 1:
		m -= 1
		if m < 1:
			m = 12
			y -= 1
		d += days_in_month(y, m)
	while d > days_in_month(y, m):
		d -= days_in_month(y, m)
		m += 1
		if m > 12:
			m = 1
			y += 1
	return { "year": y, "month": m, "day": d }

## 计算星期 (Zeller's formula, 返回 1=SUN ... 7=SAT)
static func calc_weekday(y: int, m: int, d: int) -> int:
	var t := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	if m < 3:
		y -= 1
	return (y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7 + 1
