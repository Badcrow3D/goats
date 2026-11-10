shader_type canvas_item;

uniform sampler2D palette : filter_nearest, repeat_disable;
uniform int step : hint_range(0, 3) = 0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	// Convert grayscale to one of four indices.
	float index = floor(source.r * 3.0 + 0.5);

	// Shift palette based on CPU-controlled step.
	float cycle = mod(index + float(step), 4.0);

	// Sample the center of the palette pixel.
	float u = (cycle + 0.5) / 4.0;
	vec4 color = texture(palette, vec2(u, 0.5));

	COLOR = vec4(color.rgb, source.a * color.a);
}