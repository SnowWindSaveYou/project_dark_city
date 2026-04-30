---
name: balatro-vfx
description: "Balatro 风格浮字特效系统，供 UrhoX Lua 游戏项目复用。包含行动飘字（逐字错时弹入）、分数弹出（4段动画+数字滚动）、屏幕抖动、阶段过渡文字、筹码粒子、底池脉冲、融合爆炸特效、4层文字渲染辅助。Use when: (1) 用户需要添加浮字/弹字特效，(2) 用户需要积分弹出动画，(3) 用户要复用 Balatro 风格 VFX 系统，(4) 用户需要屏幕抖动或粒子特效。"
---

# Balatro VFX — 浮字特效系统

提供 VFX.lua 和 Tween.lua 两个可独立复用的模块，以及像素字体 m6x11.ttf。

## 使用步骤

### 1. 复制文件到目标项目

- scripts/VFX.lua → 目标项目 scripts/game/VFX.lua
- scripts/Tween.lua → 目标项目 scripts/balatro/Tween.lua
- assets/Fonts/m6x11.ttf → 目标项目 assets/Fonts/m6x11.ttf

### 2. 调整 VFX.lua 依赖路径

VFX.lua 顶部两行 require 按目标项目路径调整：



若目标项目无 Card 模块，删除 Card require 行及 M.triggerReshuffle、M.getDeckGlowState、M.drawReshuffleEffect 三个函数，并在 M.updateAll 中删除 updateReshuffle(dt)，在 M.resetAll 中删除 reshuffle 相关行。

### 3. 初始化字体（Start() 中，每个 face 只调用一次）



### 4. 每帧调用



---

## 核心 API

### 生命周期

| 函数 | 说明 |
|------|------|
| VFX.setContext(vg, w, h, time) | 每帧在 NanoVGRender 开始时调用 |
| VFX.updateAll(dt) | 在 HandleUpdate 中调用 |
| VFX.resetAll() | 换关/重开时重置所有状态 |

### 行动飘字（逐字错时弹入 + 光晕背景）



### 分数弹出（4段动画 + 数字滚动 + 拖影）



### 阶段过渡文字（easeOutBack 弹入，1.2秒自动消失）



### 屏幕抖动



### 筹码粒子（贝塞尔弧线飞行）



### 底池脉冲



### 融合爆炸特效



### 4层文字渲染辅助

需先设置 nvgFontFace / nvgFontSize / nvgTextAlign：



### 阴影颜色（HSV -30° 同色系加深）



---

## Tween 动画引擎（独立模块）


