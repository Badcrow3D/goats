shader_type canvas_item;

uniform ivec2 sheet_grid = ivec2(4, 1);
uniform int first_frame = 0;
uniform int frame_count = 4;

void vertex() {
	int frame = first_frame + INSTANCE_ID % frame_count;
	vec2 cell = vec2(float(frame % sheet_grid.x), float(frame / sheet_grid.x));
	// QuadMesh UVs follow a Y-up convention. Keep the sprite sheet's orientation in 2D.
	UV = (vec2(UV.x, 1.0 - UV.y) + cell) / vec2(sheet_grid);
}
