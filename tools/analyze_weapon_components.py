import bpy
import sys


def component_bounds(mesh):
    adjacency = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(range(len(mesh.vertices)))
    components = []
    while unseen:
        seed = unseen.pop()
        stack = [seed]
        indices = [seed]
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    stack.append(neighbor)
                    indices.append(neighbor)
        coordinates = [mesh.vertices[index].co for index in indices]
        minimum = tuple(min(point[axis] for point in coordinates) for axis in range(3))
        maximum = tuple(max(point[axis] for point in coordinates) for axis in range(3))
        components.append((len(indices), minimum, maximum))
    return sorted(components, reverse=True)


for path in sys.argv[sys.argv.index("--") + 1:]:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.wm.obj_import(filepath=path)
    print(f"WEAPON_COMPONENTS {path}")
    for obj in bpy.context.selected_objects:
        if obj.type != "MESH":
            continue
        for index, (count, minimum, maximum) in enumerate(component_bounds(obj.data)):
            if count < 8:
                continue
            size = tuple(maximum[axis] - minimum[axis] for axis in range(3))
            print(
                "  %03d vertices=%d min=(%.4f,%.4f,%.4f) max=(%.4f,%.4f,%.4f) size=(%.4f,%.4f,%.4f)"
                % (index, count, *minimum, *maximum, *size)
            )
