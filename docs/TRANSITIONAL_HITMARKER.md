# Transitional hit / kill confirmation

Status: **TRANSITIONAL — not final approved art**

The current procedural marker is a gameplay-complete bridge so hit-confirm
timing, networking semantics, hierarchy, and audio can be evaluated before
commissioning final authored assets. Future agents must not treat the current
geometry or recovered sounds as locked art direction.

## Preserve when replacing

- Keep the recovered weapon crosshair visible; hit feedback is a separate layer.
- Trigger only from `WarfarePlayer.hit_confirmed`, which represents damage the
  target actually accepted, never from reticle hover or a client-side guess.
- Preserve accepted-damage reporting for both enemy targets and PvP players;
  blocked or fully mitigated attacks must not display a hit.
- Preserve defeat reporting for both enemy and PvP player targets so the same
  kill-confirm contract works when online matchmaking is restored.
- Keep ordinary hit and kill confirmation visually and sonically distinct.
- Do not add floating damage numbers unless the product direction changes.
- Coalesce same-frame pellet/splash hits so shotguns do not create audio spam.
- Give kill confirmation priority if a splash hit damages multiple enemies.
- Preserve the small center gap and short duration so the target remains visible.

## Reference rationale

- Apex Legends exposes crosshair damage feedback as an `X`, optionally paired
  with shield state, and allows damage numbers to be disabled. This project uses
  the compact `X` language but intentionally omits numbers and the shield icon:
  https://www.ea.com/able/resources/apex-legends/pc/features
- Call of Duty separates ordinary, damage-based, and final-hit marker feedback,
  including distinct audio controls. This project borrows only that hierarchy,
  not its exact geometry or sound:
  https://www.callofduty.com/blog/2020/11/Black-Ops-Cold-War-Controls-and-Settings-PlayStation

## Current temporary art direction

- Hit: four tapered cyan-white segments, 85 ms, subtle outward expansion.
- Kill: warm-gold double segments, 155 ms, stronger but still reticle-sized.
- Temporary audio: recovered `menu/exp.wav` and `pickup/killcombo.wav`.

## Final asset handoff

Replace `scripts/ui/hit_marker.gd` drawing and the two audio paths while keeping
its `show_hit()` / `show_kill()` interface. Candidate final assets should be
tested at 720p, 1080p, ultrawide, and mobile scale over both bright and dark maps.
