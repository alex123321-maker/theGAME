import sys

with open('scripts/presentation/mountain_region_builder.gd', 'r') as f:
    text = f.read()

# Restore _add_triangle
old_func = '''func _add_triangle(
surface: SurfaceTool,
a: Vector3,
a_color: Color,
b: Vector3,
b_color: Color,
c: Vector3,
c_color: Color
) -> void:
var normal: Vector3 = (c - a).cross(b - a)'''

new_func = '''func _add_triangle(
surface: SurfaceTool,
a: Vector3,
a_color: Color,
b: Vector3,
b_color: Color,
c: Vector3,
c_color: Color
) -> void:
var normal: Vector3 = (b - a).cross(c - a)'''

text = text.replace(old_func, new_func)

with open('scripts/presentation/mountain_region_builder.gd', 'w') as f:
    f.write(text)
