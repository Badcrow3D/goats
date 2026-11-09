shader_type canvas_item;

void vertex() {
	float frame = float(INSTANCE_ID % 4);
	UV.x = (UV.x + frame) * 0.25;
	// QuadMesh UVs follow a Y-up convention. Keep the sprite sheet's orientation in 2D.
	UV.y = 1.0 - UV.y;
}
