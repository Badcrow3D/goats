shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float block_size = 1.0;

void fragment() {
	float size = round(block_size);
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 sample_pixel = floor(pixel / size) * size + floor(size * 0.5);
	vec2 sample_uv = min((sample_pixel + 0.5) * SCREEN_PIXEL_SIZE, 1.0 - 0.5 * SCREEN_PIXEL_SIZE);
	COLOR = textureLod(screen_texture, sample_uv, 0.0);
}
