shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// 边框颜色 & 整体透明度 (由脚本每帧设置 alpha)
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 边框粗细 (UV 空间, 0.0~0.5)
uniform float border_width : hint_range(0.0, 0.2) = 0.06;
// 外发光扩散宽度 (UV 空间)
uniform float glow_spread : hint_range(0.0, 0.3) = 0.08;

void fragment() {
	vec2 uv = UV;
	// 到四条边的距离 (UV 空间)
	float d_left   = uv.x;
	float d_right  = 1.0 - uv.x;
	float d_top    = uv.y;
	float d_bottom = 1.0 - uv.y;
	float d_edge   = min(min(d_left, d_right), min(d_top, d_bottom));

	// 内层实线边框
	float inner_edge = border_width;
	float inner = 1.0 - smoothstep(inner_edge * 0.6, inner_edge, d_edge);

	// 外层辉光 (从边框向内外扩散)
	float outer_edge = border_width + glow_spread;
	float glow = 1.0 - smoothstep(0.0, outer_edge, d_edge);
	glow = glow * glow;  // 平方衰减, 边缘更亮

	// 合成: 内层全亮 + 外层柔光
	float intensity = clamp(inner + glow * 0.5, 0.0, 1.0);

	ALBEDO = border_color.rgb * intensity;
	ALPHA = intensity * border_color.a;
}
