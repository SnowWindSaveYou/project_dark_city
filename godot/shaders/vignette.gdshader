shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform float softness : hint_range(0.0, 1.0) = 0.5;
uniform float overall_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    uv.x *= 0.75;
    float dist = length(uv) * 2.0;
    float v = smoothstep(softness, softness + strength, dist);
    COLOR = vec4(tint_color.rgb, tint_color.a * v * overall_alpha);
}
