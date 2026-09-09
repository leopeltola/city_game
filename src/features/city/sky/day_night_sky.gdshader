shader_type sky;

uniform sampler2D day_texture : filter_linear, source_color, hint_default_black;
uniform sampler2D night_texture : filter_linear, source_color, hint_default_black;

// Range around the horizon where day and night cross-fade.
uniform float blend_range : hint_range(0.01, 1.0) = 0.25;

void sky() {
	vec2 sky_uv = vec2(
		atan(EYEDIR.x, -EYEDIR.z) / TAU + 0.5,
		acos(clamp(EYEDIR.y, -1.0, 1.0)) / PI
	);

	float blend = smoothstep(-blend_range, blend_range, LIGHT0_DIRECTION.y);

	vec3 day_col = texture(day_texture, sky_uv).rgb;
	vec3 night_col = texture(night_texture, sky_uv).rgb;

	COLOR = mix(night_col, day_col, blend);
}