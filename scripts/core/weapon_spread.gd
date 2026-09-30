extends RefCounted

# New hip-fire tuning for this project, not recovered Unity weapon values.
# Angles are cone half-angles in degrees. The existing weapon.spread remains
# the weapon's built-in pellet pattern, independently of this firing bloom.
const DEFAULT_PROFILE := {
	"min_degrees": 0.0,
	"max_degrees": 0.75,
	"per_shot_degrees": 0.12,
	"recovery_delay": 0.22,
	"recovery_degrees_per_second": 1.35,
	"reticle_max_scale": 1.18,
}

const KIND_OVERRIDES := {
	"laser": {"max_degrees": 0.55, "per_shot_degrees": 0.08, "reticle_max_scale": 1.16},
	"plasma": {"max_degrees": 0.65, "per_shot_degrees": 0.12},
	"beam": {"max_degrees": 0.65, "per_shot_degrees": 0.08},
	"snow": {"max_degrees": 0.75, "per_shot_degrees": 0.10},
	"machinegun": {"max_degrees": 1.1, "per_shot_degrees": 0.11, "reticle_max_scale": 1.25},
	"rocket": {"max_degrees": 0.5, "per_shot_degrees": 0.14, "reticle_max_scale": 1.15},
	"grenade": {"max_degrees": 0.65, "per_shot_degrees": 0.14},
	"fly_grenade": {"max_degrees": 0.5, "per_shot_degrees": 0.12, "reticle_max_scale": 1.15},
	"arrow": {"max_degrees": 0.45, "per_shot_degrees": 0.10, "reticle_max_scale": 1.14},
	"energy_fist": {"max_degrees": 0.6, "per_shot_degrees": 0.12},
	"tracking": {"max_degrees": 0.5, "per_shot_degrees": 0.10, "reticle_max_scale": 1.15},
	"ricochet": {"max_degrees": 0.6, "per_shot_degrees": 0.14},
	"spring": {"max_degrees": 0.45, "per_shot_degrees": 0.10, "reticle_max_scale": 1.14},
	"sniper": {"max_degrees": 0.35, "per_shot_degrees": 0.10, "reticle_max_scale": 1.12},
	"reflection": {"max_degrees": 0.35, "per_shot_degrees": 0.10, "reticle_max_scale": 1.12},
	"shockwave": {"max_degrees": 0.5, "per_shot_degrees": 0.12, "reticle_max_scale": 1.14},
	"sword": {"max_degrees": 0.0, "per_shot_degrees": 0.0, "reticle_max_scale": 1.0},
}

# Tune an individual gun here without changing its entire weapon family.
# Shotguns use the hitscan family but already have a wider pellet pattern.
const WEAPON_OVERRIDES := {
	"gun06": {"max_degrees": 0.5, "reticle_max_scale": 1.14},
	"gun07": {"max_degrees": 0.5, "reticle_max_scale": 1.14},
	"gun08": {"max_degrees": 0.5, "reticle_max_scale": 1.14},
	"gun09": {"max_degrees": 0.5, "reticle_max_scale": 1.14},
	"gun10": {"max_degrees": 0.5, "reticle_max_scale": 1.14},
	"gun40": {"max_degrees": 0.85, "per_shot_degrees": 0.10, "reticle_max_scale": 1.20},
}

static func for_weapon(weapon_id: String, kind: String) -> Dictionary:
	var profile := DEFAULT_PROFILE.duplicate(true)
	profile.merge(KIND_OVERRIDES.get(kind, {}), true)
	profile.merge(WEAPON_OVERRIDES.get(weapon_id, {}), true)
	return profile

static func sample_direction(forward: Vector3, camera_basis: Basis, half_angle_degrees: float) -> Vector3:
	if half_angle_degrees <= 0.0:
		return forward
	# Sample a disk and map its radius to a cone angle. Both axes share one
	# radius, so diagonal samples cannot exceed the configured half-angle.
	var angle := deg_to_rad(half_angle_degrees) * sqrt(randf())
	var azimuth := randf() * TAU
	var radial := camera_basis.x * cos(azimuth) + camera_basis.y * sin(azimuth)
	return (forward * cos(angle) + radial * sin(angle)).normalized()
