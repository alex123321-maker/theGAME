import sys

with open("scripts/presentation/mountain_region_builder.gd") as f:
    lines = f.read().split("\n")

start_idx = -1
end_idx = -1

for i, l in enumerate(lines):
    if l.startswith("func _cliff_face_vertex("):
        start_idx = i
    if l.startswith("func _add_quad("):
        end_idx = i

if start_idx == -1 or end_idx == -1:
    print("Failed to find markers", start_idx, end_idx)
    sys.exit(1)

new_code = """func _cliff_face_block_data(
top_a: Vector3,
top_a_sample: Dictionary,
top_b: Vector3,
top_b_sample: Dictionary,
base_a: Vector3,
base_b: Vector3,
avg_cliff: float,
avg_foot: float,
avg_ledge: float,
avg_ridge: float,
u: float,
v: float,
phase: float,
is_shore: bool
) -> Dictionary:
var top_pos: Vector3 = top_a.lerp(top_b, u)
var base_pos: Vector3 = base_a.lerp(base_b, u)
var vertical_drop: float = maxf(0.001, top_pos.y - base_pos.y)
var height_scale: float = clampf(vertical_drop / 3.8, 0.24, 1.0)
var edge_fade: float = pow(maxf(sin(u * PI), 0.0), 1.10)
var seam_lock_top: float = smoothstep(0.04, 0.18, v)
var seam_lock_bottom: float = 1.0 - smoothstep(0.84, 0.98, v)
var seam_lock: float = seam_lock_top * seam_lock_bottom

var ledge_steps: float = 4.0 + floor((avg_cliff * 4.0) + (avg_ledge * 3.0))
var step_phase: float = (v * ledge_steps) + (phase * 0.3)
var blocky_v: float = floor(step_phase) / ledge_steps
var step_local: float = step_phase - floor(step_phase)
var step_mask: float = smoothstep(0.0, 0.15, step_local) * (1.0 - smoothstep(0.75, 1.0, step_local))

var vertical_bands: float = 3.0 + (avg_cliff * 3.0)
var blocky_u: float = floor(u * vertical_bands + phase * 2.0)
var ledge_wave: float = sin(blocky_v * 13.0 + blocky_u * 7.0 + phase * TAU) * 0.5 + 0.5
var ledge_mask: float = maxf(
pow(ledge_wave, 1.5),
step_mask * (0.6 + (avg_ledge * 0.4))
)
var breakup_wave: float = sin(blocky_u * 4.0 + blocky_v * 5.0 + phase * TAU) * 0.5 + 0.5

var ledge_push: float = CLIFF_LEDGE_DEPTH
ledge_push *= 0.5 + (avg_cliff * 0.5)
ledge_push *= 0.6 + (avg_ledge * 0.4)
ledge_push *= ledge_mask * edge_fade
ledge_push *= 0.6 + (breakup_wave * CLIFF_BREAKUP_STRENGTH)

var shore_flare: float = 0.0
if is_shore:
var upper_band: float = 1.0 - smoothstep(0.05, 0.45, v)
var overhang: float = smoothstep(0.0, 0.1, v)
var top_blockiness: float = 0.7 + (sin(blocky_u * 3.0 + phase * 4.0) * 0.5 + 0.5) * 0.3
shore_flare = SHORE_TOP_FLARE_DEPTH
shore_flare *= upper_band * overhang * edge_fade * top_blockiness
shore_flare *= clampf((avg_cliff * 0.8) + 0.4, 0.4, 1.0)

var max_push: float = WorldGridProjection3DClass.TILE_WORLD_SIZE * (0.60 if is_shore else 0.40)
var push_amount: float = clampf((ledge_push + shore_flare) * height_scale * seam_lock, 0.0, max_push)

var side_sample: Dictionary = _sample_lerp(top_a_sample, top_b_sample, u)
var face_sample: Dictionary = _face_sample(side_sample, maxf(avg_cliff, 0.26), avg_foot, 0.86 + (avg_ridge * 0.10))
var ground_sample: Dictionary = _ground_sample(side_sample)
var ground_mix: float = smoothstep(0.46, 1.0, v)
var color: Color = _vertex_color(face_sample).lerp(_vertex_color(ground_sample), ground_mix)
if is_shore:
color.g = clampf(color.g + ((1.0 - v) * 0.08), 0.0, 1.0)
color.b = clampf(color.b + (v * 0.06), 0.0, 1.0)

return {
"push": push_amount,
"color": color,
}

func _add_cliff_face(
surface: SurfaceTool,
top_a: Vector3,
top_a_sample: Dictionary,
top_b: Vector3,
top_b_sample: Dictionary,
base_a: Vector3,
base_b: Vector3,
_outward: Vector3,
is_shore: bool
) -> void:
var avg_cliff: float = (float(top_a_sample.get("cliff", 0.0)) + float(top_b_sample.get("cliff", 0.0))) * 0.5
var avg_foot: float = (float(top_a_sample.get("foot", 0.0)) + float(top_b_sample.get("foot", 0.0))) * 0.5
var avg_ledge: float = (float(top_a_sample.get("ledge", 0.0)) + float(top_b_sample.get("ledge", 0.0))) * 0.5
var avg_ridge: float = (float(top_a_sample.get("ridge", 0.0)) + float(top_b_sample.get("ridge", 0.0))) * 0.5
var avg_height: float = ((top_a.y - base_a.y) + (top_b.y - base_b.y)) * 0.5
if avg_height <= MIN_VISIBLE_HEIGHT:
return

if avg_height < 0.48:
_add_quad(
surface,
top_a,
_vertex_color(_face_sample(top_a_sample, maxf(avg_cliff, 0.26), avg_foot)),
top_b,
_vertex_color(_face_sample(top_b_sample, maxf(avg_cliff, 0.26), avg_foot)),
base_b,
_vertex_color(_ground_sample(top_b_sample)),
base_a,
_vertex_color(_ground_sample(top_a_sample))
)
return

var outward: Vector3 = _outward.normalized() if _outward.length_squared() > 0.00001 else Vector3.ZERO
var phase: float = _noise_01(
int(roundi((top_a.x + top_b.x) * 1.7)),
int(roundi((top_a.z + top_b.z) * 1.7)),
int(roundi((top_a.y + top_b.y) * 23.0))
)
var vertical_segments: int = CLIFF_VERTICAL_SEGMENTS
if avg_height < 1.6:
vertical_segments = maxi(2, CLIFF_VERTICAL_SEGMENTS - 1)
var horizontal_segments: int = CLIFF_HORIZONTAL_SEGMENTS
if not is_shore and avg_height < 1.2:
horizontal_segments = maxi(2, CLIFF_HORIZONTAL_SEGMENTS - 1)

var grid_pushes: Array = []
var grid_colors: Array = []
for y_index in range(vertical_segments):
var row_pushes: Array = []
var row_colors: Array = []
for x_index in range(horizontal_segments):
var u: float = (float(x_index) + 0.5) / float(horizontal_segments)
var v: float = (float(y_index) + 0.5) / float(vertical_segments)
var block_data: Dictionary = _cliff_face_block_data(
top_a, top_a_sample, top_b, top_b_sample, base_a, base_b,
avg_cliff, avg_foot, avg_ledge, avg_ridge, u, v, phase, is_shore
)
row_pushes.append(float(block_data.get("push", 0.0)))
row_colors.append(Color(block_data.get("color", Color.WHITE)))
grid_pushes.append(row_pushes)
grid_colors.append(row_colors)

for y in range(vertical_segments):
var v0: float = float(y) / float(vertical_segments)
var v1: float = float(y + 1) / float(vertical_segments)
for x in range(horizontal_segments):
var u0: float = float(x) / float(horizontal_segments)
var u1: float = float(x + 1) / float(horizontal_segments)

var push: float = grid_pushes[y][x]
var color: Color = grid_colors[y][x]

var tp_u0: Vector3 = top_a.lerp(top_b, u0)
var tp_u1: Vector3 = top_a.lerp(top_b, u1)
var bp_u0: Vector3 = base_a.lerp(base_b, u0)
var bp_u1: Vector3 = base_a.lerp(base_b, u1)

var p_a: Vector3 = tp_u0.lerp(bp_u0, v0) + outward * push
var p_b: Vector3 = tp_u1.lerp(bp_u1, v0) + outward * push
var p_c: Vector3 = tp_u1.lerp(bp_u1, v1) + outward * push
var p_d: Vector3 = tp_u0.lerp(bp_u0, v1) + outward * push

_add_quad(surface, p_a, color, p_b, color, p_c, color, p_d, color)

if x > 0 and (grid_pushes[y][x-1] as float) < push:
var prev_push: float = grid_pushes[y][x-1]
var p_prev_a: Vector3 = p_a - outward * (push - prev_push)
var p_prev_d: Vector3 = p_d - outward * (push - prev_push)
_add_quad(surface, p_prev_a, color, p_a, color, p_d, color, p_prev_d, color)
elif x == 0 and push > 0.001:
var p_prev_a: Vector3 = p_a - outward * push
var p_prev_d: Vector3 = p_d - outward * push
_add_quad(surface, p_prev_a, color, p_a, color, p_d, color, p_prev_d, color)

if x < horizontal_segments - 1 and (grid_pushes[y][x+1] as float) < push:
var next_push: float = grid_pushes[y][x+1]
var p_next_b: Vector3 = p_b - outward * (push - next_push)
var p_next_c: Vector3 = p_c - outward * (push - next_push)
_add_quad(surface, p_b, color, p_next_b, color, p_next_c, color, p_c, color)
elif x == horizontal_segments - 1 and push > 0.001:
var p_next_b: Vector3 = p_b - outward * push
var p_next_c: Vector3 = p_c - outward * push
_add_quad(surface, p_b, color, p_next_b, color, p_next_c, color, p_c, color)

if y > 0 and (grid_pushes[y-1][x] as float) < push:
var top_push: float = grid_pushes[y-1][x]
var p_top_a: Vector3 = p_a - outward * (push - top_push)
var p_top_b: Vector3 = p_b - outward * (push - top_push)
_add_quad(surface, p_top_a, color, p_top_b, color, p_b, color, p_a, color)
elif y == 0 and push > 0.001:
var p_top_a: Vector3 = p_a - outward * push
var p_top_b: Vector3 = p_b - outward * push
_add_quad(surface, p_top_a, color, p_top_b, color, p_b, color, p_a, color)

if y < vertical_segments - 1 and (grid_pushes[y+1][x] as float) < push:
var bot_push: float = grid_pushes[y+1][x]
var p_bot_d: Vector3 = p_d - outward * (push - bot_push)
var p_bot_c: Vector3 = p_c - outward * (push - bot_push)
_add_quad(surface, p_d, color, p_c, color, p_bot_c, color, p_bot_d, color)
elif y == vertical_segments - 1 and push > 0.001:
var p_bot_d: Vector3 = p_d - outward * push
var p_bot_c: Vector3 = p_c - outward * push
_add_quad(surface, p_d, color, p_c, color, p_bot_c, color, p_bot_d, color)
"""

new_lines = lines[:start_idx] + new_code.split("\n") + lines[end_idx:]
with open("scripts/presentation/mountain_region_builder.gd", "w") as f:
    f.write("\n".join(new_lines))

print("Patched!")
