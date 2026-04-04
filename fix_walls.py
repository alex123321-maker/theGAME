import sys

with open('scripts/presentation/mountain_region_builder.gd', 'r', encoding='utf-8') as f:
    text = f.read()

new_blocky_func = '''func _add_blocky_top_face(
	surface: SurfaceTool,
	nw: Vector3, nw_sample: Dictionary,
	sw: Vector3, sw_sample: Dictionary,
	se: Vector3, se_sample: Dictionary,
	ne: Vector3, ne_sample: Dictionary,
	phase: float
) -> void:
	var segments: int = CLIFF_HORIZONTAL_SEGMENTS
	var pushes: Array = []
	var colors: Array = []
	
	for y in range(segments):
		var row_pushes: Array = []
		var row_colors: Array = []
		for x in range(segments):
			var u: float = (float(x) + 0.5) / float(segments)
			var v: float = (float(y) + 0.5) / float(segments)
			
			var edge_fade_u: float = pow(maxf(sin(u * PI), 0.0), 0.6)
			var edge_fade_v: float = pow(maxf(sin(v * PI), 0.0), 0.6)
			var seam_lock: float = edge_fade_u * edge_fade_v
			
			var blocky_u: float = floor(u * 5.0 + phase * 2.0)
			var blocky_v: float = floor(v * 4.0 + phase * 1.5)
			var bump: float = sin(blocky_u * 13.0 + blocky_v * 7.0 + phase * TAU) * 0.5 + 0.5
			bump = floor(bump * 3.0) / 3.0
			
			var push: float = bump * seam_lock * 1.5 * CLIFF_LEDGE_DEPTH
			row_pushes.append(push)
			
			var c_top = _vertex_color(nw_sample).lerp(_vertex_color(ne_sample), u)
			var c_bot = _vertex_color(sw_sample).lerp(_vertex_color(se_sample), u)
			row_colors.append(c_top.lerp(c_bot, v))
			
		pushes.append(row_pushes)
		colors.append(row_colors)

	for y in range(segments):
		var v0: float = float(y) / float(segments)
		var v1: float = float(y + 1) / float(segments)
		for x in range(segments):
			var u0: float = float(x) / float(segments)
			var u1: float = float(x + 1) / float(segments)
			
			var push: float = pushes[y][x]
			var color: Color = colors[y][x]
			
			var tp_u0: Vector3 = nw.lerp(ne, u0)
			var tp_u1: Vector3 = nw.lerp(ne, u1)
			var bp_u0: Vector3 = sw.lerp(se, u0)
			var bp_u1: Vector3 = sw.lerp(se, u1)
			
			var tp_a: Vector3 = tp_u0.lerp(bp_u0, v0)
			var tp_b: Vector3 = tp_u0.lerp(bp_u0, v1)
			var tp_c: Vector3 = tp_u1.lerp(bp_u1, v1)
			var tp_d: Vector3 = tp_u1.lerp(bp_u1, v0)
			
			var p_a: Vector3 = tp_a + Vector3.UP * push
			var p_b: Vector3 = tp_b + Vector3.UP * push
			var p_c: Vector3 = tp_c + Vector3.UP * push
			var p_d: Vector3 = tp_d + Vector3.UP * push
			
			# TOP
			_add_quad(surface, p_a, color, p_b, color, p_c, color, p_d, color)
			
			# WALLS
			if x > 0 and float(pushes[y][x-1]) < push:
				var prev_push: float = float(pushes[y][x-1])
				var p_prev_a: Vector3 = p_a - Vector3.UP * (push - prev_push)
				var p_prev_b: Vector3 = p_b - Vector3.UP * (push - prev_push)
				_add_quad(surface, p_b, color, p_prev_b, color, p_prev_a, color, p_a, color)
			elif x == 0 and push > 0.001:
				var p_prev_a: Vector3 = p_a - Vector3.UP * push
				var p_prev_b: Vector3 = p_b - Vector3.UP * push
				_add_quad(surface, p_b, color, p_prev_b, color, p_prev_a, color, p_a, color)
				
			if x < segments - 1 and float(pushes[y][x+1]) < push:
				var next_push: float = float(pushes[y][x+1])
				var p_next_d: Vector3 = p_d - Vector3.UP * (push - next_push)
				var p_next_c: Vector3 = p_c - Vector3.UP * (push - next_push)
				_add_quad(surface, p_d, color, p_next_d, color, p_next_c, color, p_c, color)
			elif x == segments - 1 and push > 0.001:
				var p_next_d: Vector3 = p_d - Vector3.UP * push
				var p_next_c: Vector3 = p_c - Vector3.UP * push
				_add_quad(surface, p_d, color, p_next_d, color, p_next_c, color, p_c, color)
				
			if y > 0 and float(pushes[y-1][x]) < push:
				var top_push: float = float(pushes[y-1][x])
				var p_top_a: Vector3 = p_a - Vector3.UP * (push - top_push)
				var p_top_d: Vector3 = p_d - Vector3.UP * (push - top_push)
				_add_quad(surface, p_a, color, p_top_a, color, p_top_d, color, p_d, color)
			elif y == 0 and push > 0.001:
				var p_top_a: Vector3 = p_a - Vector3.UP * push
				var p_top_d: Vector3 = p_d - Vector3.UP * push
				_add_quad(surface, p_a, color, p_top_a, color, p_top_d, color, p_d, color)
				
			if y < segments - 1 and float(pushes[y+1][x]) < push:
				var bot_push: float = float(pushes[y+1][x])
				var p_bot_b: Vector3 = p_b - Vector3.UP * (push - bot_push)
				var p_bot_c: Vector3 = p_c - Vector3.UP * (push - bot_push)
				_add_quad(surface, p_c, color, p_bot_c, color, p_bot_b, color, p_b, color)
			elif y == segments - 1 and push > 0.001:
				var p_bot_b: Vector3 = p_b - Vector3.UP * push
				var p_bot_c: Vector3 = p_c - Vector3.UP * push
				_add_quad(surface, p_c, color, p_bot_c, color, p_bot_b, color, p_b, color)
'''

start_idx = text.find('func _add_blocky_top_face(')
end_idx = text.find('func _add_cliff_face(')

if start_idx != -1 and end_idx != -1:
    text = text[:start_idx] + new_blocky_func + '\n' + text[end_idx:]

with open('scripts/presentation/mountain_region_builder.gd', 'w', encoding='utf-8') as f:
    f.write(text)
