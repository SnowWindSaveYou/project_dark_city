-- ============================================================================
-- ItemIcons.lua - 道具图标纹理索引 & NanoVG 绘制工具
-- 统一管理所有道具的手绘风图标纹理，供 ShopPopup / HandPanel / EventPopup 等使用
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- 图标路径映射 (key → 资源路径)
-- 路径相对于 assets/ 资源根目录
-- ---------------------------------------------------------------------------

local ICON_PATHS = {
    film        = "image/道具_胶卷v2_20260426153757.png",
    shield      = "image/道具_护身符v2_20260426153859.png",
    exorcism    = "image/道具_驱魔香v2_20260426153756.png",
    coffee      = "image/道具_咖啡v2_20260426153856.png",
    mapReveal   = "image/道具_地图碎片v2_20260426153808.png",
    sedative    = "image/道具_镇定剂v2_20260426155757.png",
    orderManual = "image/道具_秩序手册v2_20260426155707.png",
}

-- 缓存: key → NanoVG image handle
local nvgImages = {}
-- 缓存: key → Texture2D
local textures  = {}

-- NanoVG context (由 init 注入)
local vg_ = nil

-- ---------------------------------------------------------------------------
-- 初始化 (在 NanoVG 就绪后调用一次)
-- ---------------------------------------------------------------------------

--- 初始化图标模块
---@param vg userdata  NanoVG context
function M.init(vg)
    vg_ = vg
    -- 预加载所有 NanoVG 图片
    for key, path in pairs(ICON_PATHS) do
        local handle = nvgCreateImage(vg_, path, 0)
        if handle and handle > 0 then
            nvgImages[key] = handle
            print(string.format("[ItemIcons] Loaded NVG image: %s → handle %d", key, handle))
        else
            print(string.format("[ItemIcons] WARNING: Failed to load NVG image: %s (%s)", key, path))
        end
    end
end

-- ---------------------------------------------------------------------------
-- 查询 API
-- ---------------------------------------------------------------------------

--- 获取道具的 NanoVG image handle (用于 nvgImagePattern 绘制)
---@param key string  道具 key: "film"|"shield"|"exorcism"|"coffee"|"mapReveal"
---@return number|nil  NanoVG image handle, nil 表示未加载
function M.getNvgImage(key)
    return nvgImages[key]
end

--- 获取道具的 Texture2D (用于 3D 场景中的 Billboard/Sprite)
---@param key string
---@return Texture2D|nil
function M.getTexture(key)
    if textures[key] then return textures[key] end
    local path = ICON_PATHS[key]
    if not path then return nil end
    local tex = cache:GetResource("Texture2D", path)
    if tex then
        textures[key] = tex
        print(string.format("[ItemIcons] Loaded Texture2D: %s", key))
    end
    return tex
end

--- 检查是否有指定道具的图标
---@param key string
---@return boolean
function M.has(key)
    return ICON_PATHS[key] ~= nil
end

--- 获取所有已注册的道具 key 列表
---@return string[]
function M.keys()
    local result = {}
    for k in pairs(ICON_PATHS) do
        result[#result + 1] = k
    end
    return result
end

-- ---------------------------------------------------------------------------
-- NanoVG 绘制便捷函数
-- ---------------------------------------------------------------------------

--- 在指定位置绘制道具图标 (NanoVG)
--- 图标绘制在 (cx - size/2, cy - size/2) 到 (cx + size/2, cy + size/2) 的正方形内
---@param vg userdata  NanoVG context
---@param key string   道具 key
---@param cx number    中心 X
---@param cy number    中心 Y
---@param size number  图标边长 (像素)
---@param alpha number|nil  透明度 0~255, 默认 255
---@return boolean     是否绘制成功 (有对应图标)
function M.draw(vg, key, cx, cy, size, alpha)
    local img = nvgImages[key]
    if not img then return false end

    alpha = alpha or 255
    local hs = size / 2
    local x, y = cx - hs, cy - hs

    local paint = nvgImagePattern(vg, x, y, size, size, 0, img, alpha / 255.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, size, size)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    return true
end

--- 在指定位置绘制圆形裁剪的道具图标
---@param vg userdata
---@param key string
---@param cx number
---@param cy number
---@param radius number
---@param alpha number|nil  0~255
---@return boolean
function M.drawCircle(vg, key, cx, cy, radius, alpha)
    local img = nvgImages[key]
    if not img then return false end

    alpha = alpha or 255
    local size = radius * 2

    local paint = nvgImagePattern(vg, cx - radius, cy - radius, size, size, 0, img, alpha / 255.0)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    return true
end

return M
