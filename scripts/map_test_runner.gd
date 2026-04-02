extends RefCounted
class_name MapTestRunner

func run_batch_screenshots(map_view, seeds: Array[int], base_dir: String = "user://screenshots/reference") -> Array[String]:
	var results: Array[String] = []
	DirAccess.make_dir_recursive_absolute(base_dir)

	for seed in seeds:
		map_view.apply_seed_and_regenerate(seed)
		await map_view.get_tree().process_frame

		var image: Image = map_view.get_viewport().get_texture().get_image()
		var file_path: String = "%s/seed_%d.png" % [base_dir, int(seed)]
		image.save_png(file_path)
		results.append(ProjectSettings.globalize_path(file_path))

	return results
