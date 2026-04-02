shader_type canvas_item;

uniform float border_start : hint_range(0.0, 1.0) = 0.94;
uniform float sample_inset_px : hint_range(0.0, 8.0) = 2.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	if (base.a <= 0.0) {
		COLOR = base;
	} else {
		vec2 centered = abs(UV - vec2(0.5));
		float diamond = (centered.x / 0.5) + (centered.y / 0.5);
		if (diamond <= border_start) {
			COLOR = base;
		} else {
			vec2 direction = normalize(vec2(0.5) - UV);
			vec2 inner_uv = clamp(UV + (direction * TEXTURE_PIXEL_SIZE * sample_inset_px), vec2(0.0), vec2(1.0));
			vec4 replacement = texture(TEXTURE, inner_uv) * COLOR;
			if (replacement.a > 0.0) {
				COLOR = replacement;
			} else {
				COLOR = base;
			}
		}
	}
}
