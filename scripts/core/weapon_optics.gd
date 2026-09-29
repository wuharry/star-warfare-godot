extends RefCounted

# New project design, not recovered Unity data. Optics are opt-in per weapon;
# neither a sci-fi model nor an AimID alone implies that a weapon has a scope.
# Inspected through EquipmentRefinement.weapon_mesh(), the same runtime path.
# Reticles share CoM-inspired thin amber strokes, but each optic has a distinct
# silhouette. Style names are consumed by WarfareScopeOverlay and the preview.
# Housing silhouettes are not magnified into solid panels around the view.
# Reticles and magnifications are new design choices, not recovered values.
const RETICLE_AMBER := Color(1.0, 0.72, 0.20, 0.94)
const PROFILES := {
	"gun00": {
		"id": "fr28a_prismatic_tube", "reticle_color": RETICLE_AMBER,
		"reticle": "segmented_ring", "reticle_name": "分段圓環",
		"lens_tint": Color(1.0, 0.58, 0.18, 0.012), "magnifications": [2.0, 4.0],
	},
	"gun14": {
		"id": "vox07_compact_sight", "reticle_color": RETICLE_AMBER,
		"reticle": "open_chevron", "reticle_name": "開口尖角",
		"lens_tint": Color(0.2, 0.9, 0.8, 0.012), "magnifications": [2.0],
	},
	"gun34": {
		"id": "r100_integrated_display", "reticle_color": RETICLE_AMBER,
		"reticle": "precision_cross", "reticle_name": "精密十字",
		"lens_tint": Color(0.15, 0.4, 0.8, 0.012), "magnifications": [2.0, 4.0, 6.0],
	},
	"gun35": {
		"id": "r700_integrated_display", "reticle_color": RETICLE_AMBER,
		"reticle": "bracket_diamond", "reticle_name": "四角菱形",
		"lens_tint": Color(0.1, 0.9, 0.8, 0.012), "magnifications": [2.0, 4.0, 6.0],
	},
	"gun40": {
		"id": "astkk_large_tube", "reticle_color": RETICLE_AMBER,
		"reticle": "t_post", "reticle_name": "T 型柱線",
		"lens_tint": Color(0.1, 0.7, 0.65, 0.012), "magnifications": [2.0, 4.0, 6.0],
	},
}

static func for_weapon(weapon_id: String) -> Dictionary:
	return PROFILES.get(weapon_id, {}).duplicate(true)

static func magnified_fov(base_fov: float, magnification: float) -> float:
	# Screen-space enlargement follows the perspective tangent, not FOV / zoom.
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / maxf(1.0, magnification)))
