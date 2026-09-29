extends RefCounted

# New project design, not recovered Unity data. Optics are opt-in per weapon;
# neither a sci-fi model nor an AimID alone implies that a weapon has a scope.
# Inspected through EquipmentRefinement.weapon_mesh(), the same runtime path.
# Reticles and magnifications are new design choices tied to the visible optic,
# not claims that its internals/magnification were recoverable from the mesh.
const PROFILES := {
	"gun00": {
		"id": "fr28a_prismatic_tube", "aperture": "pentagon", "reticle": "duplex",
		"rim_color": Color(0.28, 0.20, 0.43), "reticle_color": Color(1.0, 0.67, 0.25),
		"lens_tint": Color(1.0, 0.58, 0.18, 0.025), "magnifications": [2.0, 4.0],
	},
	"gun14": {
		"id": "vox07_compact_sight", "aperture": "circle", "reticle": "ladder",
		"rim_color": Color(0.25, 0.30, 0.27), "reticle_color": Color(0.45, 0.95, 0.83),
		"lens_tint": Color(0.2, 0.9, 0.8, 0.025), "magnifications": [2.0],
	},
	"gun34": {
		"id": "r100_integrated_display", "aperture": "portrait_screen", "reticle": "grid_cross",
		"rim_color": Color(0.13, 0.45, 0.78), "reticle_color": Color(0.94, 1.0, 0.32),
		"lens_tint": Color(0.15, 0.4, 0.8, 0.025), "magnifications": [2.0, 4.0, 6.0],
	},
	"gun35": {
		"id": "r700_integrated_display", "aperture": "square_screen", "reticle": "ring",
		"rim_color": Color(0.36, 0.44, 0.25), "reticle_color": Color(0.20, 1.0, 0.91),
		"lens_tint": Color(0.1, 0.9, 0.8, 0.035), "magnifications": [2.0, 4.0, 6.0],
	},
	"gun40": {
		"id": "astkk_large_tube", "aperture": "circle", "reticle": "chevron",
		"rim_color": Color(0.62, 0.65, 0.68), "reticle_color": Color(1.0, 0.32, 0.23),
		"lens_tint": Color(0.1, 0.7, 0.65, 0.025), "magnifications": [2.0, 4.0, 6.0],
	},
}

static func for_weapon(weapon_id: String) -> Dictionary:
	return PROFILES.get(weapon_id, {}).duplicate(true)

static func magnified_fov(base_fov: float, magnification: float) -> float:
	# Screen-space enlargement follows the perspective tangent, not FOV / zoom.
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / maxf(1.0, magnification)))
