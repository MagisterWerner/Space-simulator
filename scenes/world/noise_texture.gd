extends TextureRect

func _process(_delta):
	queue_redraw()

func _draw():
	RenderingServer.canvas_item_add_texture_rect(get_canvas_item(), get_viewport_rect(), texture.get_rid(), true)
