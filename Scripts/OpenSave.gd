extends Node

var current_save_path := ""

func open_pxo_file(path : String) -> void:
	var file := File.new()
	var err := file.open_compressed(path, File.READ, File.COMPRESSION_ZSTD)
	if err == ERR_FILE_UNRECOGNIZED:
		err =  file.open(path, File.READ) # If the file is not compressed open it raw (pre-v0.7)

	if err != OK:
		file.close()
		OS.alert("Can't load file")
		return

	var file_version := file.get_line() # Example, "v0.6"
	var file_major_version = int(file_version.substr(1, 1))
	var file_minor_version = int(file_version.substr(3, 1))

	if file_major_version == 0 and file_minor_version < 5:
		Global.notification_label("File is from an older version of Pixelorama, as such it might not work properly")

	var frame := 0
	Global.layers.clear()
	if file_major_version >= 0 and file_minor_version > 6:
		var global_layer_line := file.get_line()
		while global_layer_line == ".":
			var layer_name := file.get_line()
			var layer_visibility := file.get_8()
			var layer_lock := file.get_8()
			var layer_new_frames_linked := file.get_8()
			var linked_frames = file.get_var()

			# Store [Layer name (0), Layer visibility boolean (1), Layer lock boolean (2), Frame container (3),
			# will new frames be linked boolean (4), Array of linked frames (5)]
			Global.layers.append([layer_name, layer_visibility, layer_lock, HBoxContainer.new(), layer_new_frames_linked, linked_frames])
			global_layer_line = file.get_line()

	var frame_line := file.get_line()
	Global.clear_canvases()
	while frame_line == "--": # Load frames
		var canvas : Canvas = load("res://Prefabs/Canvas.tscn").instance()
		Global.canvas = canvas
		var width := file.get_16()
		var height := file.get_16()

		var layer_line := file.get_line()
		while layer_line == "-": # Load layers
			var buffer := file.get_buffer(width * height * 4)
			if file_major_version == 0 and file_minor_version < 7:
				var layer_name_old_version = file.get_line()
				if frame == 0:
					# Store [Layer name (0), Layer visibility boolean (1), Layer lock boolean (2), Frame container (3),
					# will new frames be linked boolean (4), Array of linked frames (5)]
					Global.layers.append([layer_name_old_version, true, false, HBoxContainer.new(), false, []])
			var layer_transparency := 1.0
			if file_major_version >= 0 and file_minor_version > 5:
				layer_transparency = file.get_float()
			var image := Image.new()
			image.create_from_data(width, height, false, Image.FORMAT_RGBA8, buffer)
			image.lock()
			var tex := ImageTexture.new()
			tex.create_from_image(image, 0)
			canvas.layers.append([image, tex, layer_transparency])
			layer_line = file.get_line()

		var guide_line := file.get_line() # "guideline" no pun intended
		while guide_line == "|": # Load guides
			var guide := Guide.new()
			guide.default_color = Color.purple
			guide.type = file.get_8()
			if guide.type == guide.Types.HORIZONTAL:
				guide.add_point(Vector2(-99999, file.get_16()))
				guide.add_point(Vector2(99999, file.get_16()))
			else:
				guide.add_point(Vector2(file.get_16(), -99999))
				guide.add_point(Vector2(file.get_16(), 99999))
			guide.has_focus = false
			canvas.add_child(guide)
			guide_line = file.get_line()

		canvas.size = Vector2(width, height)
		Global.canvases.append(canvas)
		canvas.frame = frame
		Global.canvas_parent.add_child(canvas)
		frame_line = file.get_line()
		frame += 1

	Global.canvases = Global.canvases # Just to call Global.canvases_changed
	Global.current_frame = frame - 1
	Global.layers = Global.layers # Just to call Global.layers_changed
	# Load tool options
	Global.left_color_picker.color = file.get_var()
	Global.right_color_picker.color = file.get_var()
	Global.left_brush_size = file.get_8()
	Global.left_brush_size_edit.value = Global.left_brush_size
	Global.right_brush_size = file.get_8()
	Global.right_brush_size_edit.value = Global.right_brush_size
	if file_major_version == 0 and file_minor_version < 7:
		var left_palette = file.get_var()
		var right_palette = file.get_var()
		for color in left_palette:
			Global.left_color_picker.get_picker().add_preset(color)
		for color in right_palette:
			Global.right_color_picker.get_picker().add_preset(color)

	# Load custom brushes
	Global.custom_brushes.resize(Global.brushes_from_files)
	Global.remove_brush_buttons()

	var brush_line := file.get_line()
	while brush_line == "/":
		var b_width := file.get_16()
		var b_height := file.get_16()
		var buffer := file.get_buffer(b_width * b_height * 4)
		var image := Image.new()
		image.create_from_data(b_width, b_height, false, Image.FORMAT_RGBA8, buffer)
		Global.custom_brushes.append(image)
		Global.create_brush_button(image)
		brush_line = file.get_line()

	if file_major_version >= 0 and file_minor_version > 6:
		var tag_line := file.get_line()
		while tag_line == ".T/":
			var tag_name := file.get_line()
			var tag_color : Color = file.get_var()
			var tag_from := file.get_8()
			var tag_to := file.get_8()
			Global.animation_tags.append([tag_name, tag_color, tag_from, tag_to])
			Global.animation_tags = Global.animation_tags # To execute animation_tags_changed()
			tag_line = file.get_line()

	file.close()

	current_save_path = path
	Global.window_title = path.get_file() + " - Pixelorama"


func save_pxo_file(path : String) -> void:
	current_save_path = path

	var file := File.new()
	var err := file.open_compressed(path, File.WRITE, File.COMPRESSION_ZSTD)
	if err == OK:
		# Store Pixelorama version
		file.store_line(ProjectSettings.get_setting("application/config/Version"))

		# Store Global layers
		for layer in Global.layers:
			file.store_line(".")
			file.store_line(layer[0]) # Layer name
			file.store_8(layer[1]) # Layer visibility
			file.store_8(layer[2]) # Layer lock
			file.store_8(layer[4]) # Future frames linked
			file.store_var(layer[5]) # Linked frames
		file.store_line("END_GLOBAL_LAYERS")

		 # Store frames
		for canvas in Global.canvases:
			file.store_line("--")
			file.store_16(canvas.size.x)
			file.store_16(canvas.size.y)
			for layer in canvas.layers: # Store canvas layers
				file.store_line("-")
				file.store_buffer(layer[0].get_data())
				file.store_float(layer[2]) # Layer transparency
			file.store_line("END_LAYERS")

			 # Store guides
			for child in canvas.get_children():
				if child is Guide:
					file.store_line("|")
					file.store_8(child.type)
					if child.type == child.Types.HORIZONTAL:
						file.store_16(child.points[0].y)
						file.store_16(child.points[1].y)
					else:
						file.store_16(child.points[1].x)
						file.store_16(child.points[0].x)
			file.store_line("END_GUIDES")
		file.store_line("END_FRAMES")

		# Save tool options
		var left_color : Color = Global.left_color_picker.color
		var right_color : Color = Global.right_color_picker.color
		var left_brush_size : int = Global.left_brush_size
		var right_brush_size : int = Global.right_brush_size
		file.store_var(left_color)
		file.store_var(right_color)
		file.store_8(left_brush_size)
		file.store_8(right_brush_size)

		# Save custom brushes
		for i in range(Global.brushes_from_files, Global.custom_brushes.size()):
			var brush = Global.custom_brushes[i]
			file.store_line("/")
			file.store_16(brush.get_size().x)
			file.store_16(brush.get_size().y)
			file.store_buffer(brush.get_data())
		file.store_line("END_BRUSHES")

		# Store animation tags
		for tag in Global.animation_tags:
			file.store_line(".T/")
			file.store_line(tag[0]) # Tag name
			file.store_var(tag[1]) # Tag color
			file.store_8(tag[2]) # Tag "from", the first frame
			file.store_8(tag[3]) # Tag "to", the last frame
		file.store_line("END_FRAME_TAGS")

	file.close()

	if !Global.saved:
		Global.saved = true

	Global.window_title = current_save_path.get_file() + " - Pixelorama"
	Global.notification_label("File saved")
