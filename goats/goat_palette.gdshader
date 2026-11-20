shader_type canvas_item;

uniform vec4 highlight_color : source_color;
uniform vec4 light_color : source_color;
uniform vec4 midtone_color : source_color;
uniform vec4 shadow_color : source_color;
uniform vec4 team_color : source_color;

varying vec4 sprite_modulate;

void vertex() {
	sprite_modulate = COLOR;
}

void fragment() {
	vec4 sprite = texture(TEXTURE, UV);
	ivec3 rgb = ivec3(round(sprite.rgb * 255.0));

	if (rgb == ivec3(255)) {
		sprite.rgb = highlight_color.rgb;
	} else if (rgb == ivec3(191)) {
		sprite.rgb = light_color.rgb;
	} else if (rgb == ivec3(128)) {
		sprite.rgb = midtone_color.rgb;
	} else if (rgb == ivec3(64)) {
		sprite.rgb = shadow_color.rgb;
	} else if (rgb == ivec3(0, 0, 255)) {
		sprite.rgb = team_color.rgb;
	}

	COLOR = sprite * sprite_modulate;
}
