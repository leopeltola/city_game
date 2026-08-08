shader_type canvas_item;

uniform vec3 color: source_color = vec3(1.0);
uniform float scale: hint_range(0.01, 2.0, 0.01) = 1.0;
uniform float speed: hint_range(0.01, 2.0, 0.01) = 1.0;

void fragment() {
	vec2 scrolled_uv = UV * scale;
	scrolled_uv += vec2(1., 1.) * TIME * speed;
	vec4 col = texture(TEXTURE, scrolled_uv);
	col.rgb = color;
	COLOR = col;
}