extends RefCounted
class_name MapSerializer

func to_json_text(map_data: MapData, indent: String = "\t") -> String:
	return JSON.stringify(map_data.to_dict(), indent)

func from_json_text(json_text: String) -> MapData:
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapSerializer.from_json_text: invalid JSON payload.")
		return MapData.new()

	return MapData.from_dict(parsed)
