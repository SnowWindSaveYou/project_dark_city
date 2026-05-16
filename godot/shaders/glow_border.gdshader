shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// 光环颜色 & 整体透明度 (由脚本每帧设置 alpha)
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 外发光扩散宽度 (UV 空间): 控制从卡牌边缘向外的渐隐范围
uniform float glow_spread : hint_range(0.0, 0.5) = 0.10;

void fragment() {
	vec2 uv = UV;

	// 到四条 quad 边的距离 (UV 空间, 0 = quad 外边缘, 增大 = 向 quad 中心)
	float d_left   = uv.x;
	float d_right  = 1.0 - uv.x;
	float d_top    = uv.y;
	float d_bottom = 1.0 - uv.y;
	float d_edge   = min(min(d_left, d_right), min(d_top, d_bottom));

	// 外圈方向: 从 quad 外边缘(d=0)向内渐强, 在 glow_spread 处达到最大
	// 卡牌本体遮住中央, 可见区域为外圈 margin 条带
	float glow = smoothstep(0.0, glow_spread, d_edge);

	ALBEDO = border_color.rgb;
	ALPHA = glow * border_color.a;
}
