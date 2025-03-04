extends Object
# TODO оптимизировать работу с "бумагой", чтобы при работе с инструментом
# не перерисовывать все заново на каждом движении

const Iterators = preload("iterators.gd")
const Common = preload("common.gd")

const QUAD = PoolVector2Array([
	Vector2.LEFT + Vector2.UP,   Vector2.UP,   Vector2.RIGHT + Vector2.UP,
	Vector2.LEFT,                Vector2.ZERO, Vector2.RIGHT,
	Vector2.LEFT + Vector2.DOWN, Vector2.DOWN, Vector2.RIGHT + Vector2.DOWN
])

const EMPTY_CELL_DATA: PoolIntArray = PoolIntArray([-1])

class RulerGridMap:
	extends TileMap
	
	const Common = preload("common.gd")
	
	var cell_half_offset_type: Common.CellHalfOffsetType
	var size: Vector2
	var linear_size: Vector2
	var center_offset: Vector2
	var linear_growth: float
	var has_offsetted_cell_lines: bool
	var has_offsetted_pattern_lines: bool

	func _init() -> void:
		connect("settings_changed", self, "__on_settings_changed")
		__on_settings_changed()

	func __on_settings_changed() -> void:
		cell_half_offset_type = Common.CELL_HALF_OFFSET_TYPES[cell_half_offset]
		var used_rect: Rect2 = get_used_rect()
		assert(used_rect.position == Vector2.ZERO)
		size = used_rect.size
		linear_size = cell_half_offset_type.conv(size)
		has_offsetted_cell_lines = linear_size.y > 1
		has_offsetted_pattern_lines = int(linear_size.y) & 1
		linear_growth = (int(has_offsetted_cell_lines) + int(has_offsetted_pattern_lines)) * 0.5 * cell_half_offset_type.offset_sign
		center_offset = (Vector2.ONE - linear_size + Vector2.RIGHT * linear_growth) / 2

signal changes_committed(tile_map, backup)
signal after_set_up()
signal before_tear_down()
signal tile_map_settings_changed()
signal tile_set_settings_changed()

var _is_input_freezed: bool

var __tile_map: TileMap
var __ruler_grid_map: RulerGridMap = RulerGridMap.new()
var __tile_set: TileSet
var __backup: Dictionary
var __previous_data_for_update_bitmask_area: Array

func has_changes() -> bool:
	return not __backup.empty()

func is_cell_changed(map_cell: Vector2) -> bool:
	return __backup.has(map_cell)

func _init() -> void:
	__ruler_grid_map.cell_size = Vector2.ONE
	__previous_data_for_update_bitmask_area.resize(9)

func process_input_event_key(event: InputEventKey) -> bool:
	return false

func set_up(tile_map: TileMap) -> void:
	assert(__tile_map == null)
	__tile_map = tile_map
	__tile_map.connect("settings_changed", self, "__on_tile_map_settings_changed")
	__ruler_grid_map.cell_half_offset = __tile_map.cell_half_offset
	__tile_set = __tile_map.tile_set
	if __tile_set:
		__tile_set.connect("changed", self, "__on_tile_set_settings_changed")
	emit_signal("after_set_up")

func tear_down() -> void:
	assert(__tile_map)
	emit_signal("before_tear_down")
	__backup.clear()
	if __tile_set:
		__tile_set.disconnect("changed", self, "__on_tile_set_settings_changed")
	__tile_map.disconnect("settings_changed", self, "__on_tile_map_settings_changed")
	__tile_map = null

func __on_tile_map_settings_changed() -> void:
	__ruler_grid_map.cell_half_offset = __tile_map.cell_half_offset
	if __tile_set != __tile_map.tile_set:
		if __tile_set:
			__tile_set.disconnect("changed", self, "__on_tile_set_settings_changed")
		__tile_set = __tile_map.tile_set
		if __tile_set:
			__tile_set.connect("changed", self, "__on_tile_set_settings_changed")
	emit_signal("tile_map_settings_changed")

func get_map_cell_data(map_cell: Vector2, original: bool = false) -> PoolIntArray:
	return __backup.get(map_cell, Common.get_map_cell_data(__tile_map, map_cell)) \
		if original else Common.get_map_cell_data(__tile_map, map_cell)

func set_map_cell_data(map_cell: Vector2, data: PoolIntArray) -> void:
	if not __backup.has(map_cell):
		__backup[map_cell] = get_map_cell_data(map_cell)
	if data[0] == TileMap.INVALID_CELL:
		__tile_map.set_cellv(map_cell, data[0])
	else:
		__tile_map.set_cellv(map_cell, data[0], data[1] & Common.CELL_X_FLIPPED, data[1] & Common.CELL_Y_FLIPPED, data[1] & Common.CELL_TRANSPOSED, Vector2(data[2], data[3]))

func update_bitmask_area(map_cell: Vector2) -> void:
	for i in range(9):
		__previous_data_for_update_bitmask_area[i] = get_map_cell_data(map_cell + QUAD[i])
	__tile_map.update_bitmask_area(map_cell)
	var data_map_cell: Vector2
	var previous_data: PoolIntArray
	for i in range(9):
		data_map_cell = map_cell + QUAD[i]
		previous_data = __previous_data_for_update_bitmask_area[i]
		if previous_data != get_map_cell_data(data_map_cell):
			__backup[data_map_cell] = previous_data

func update_bitmask_region(start: Vector2 = Vector2.ZERO, end: Vector2 = Vector2.ZERO) -> void:
	var affected_rect: Rect2 = \
		__tile_map.get_used_rect() \
		if not start.round() and not end.round() else \
		Rect2(start, end - start).grow(1).clip(__tile_map.get_used_rect())
	var previous_datas: Array
	previous_datas.resize(affected_rect.get_area())
	var affected_rect_map_cell_iterator = Iterators.rect(affected_rect) #: Iterators.Iterator
	var index: int = 0
	for map_cell in affected_rect_map_cell_iterator:
		previous_datas[index] = get_map_cell_data(map_cell)
		index += 1
	__tile_map.update_bitmask_region(start, end)
	index = 0
	var previous_data: PoolIntArray
	for map_cell in affected_rect_map_cell_iterator:
		previous_data = previous_datas[index]
		if previous_data != get_map_cell_data(map_cell):
			__backup[map_cell] = previous_data
		index += 1

func commit_changes() -> void:
	emit_signal("changes_committed", __tile_map, __backup)
	__backup.clear()

func reset_map_cell(map_cell: Vector2) -> void:
	if map_cell in __backup:
		var data = __backup[map_cell]
		if data[0] == TileMap.INVALID_CELL:
			__tile_map.set_cellv(map_cell, data[0])
		else:
			__tile_map.set_cellv(map_cell, data[0], data[1] & Common.CELL_X_FLIPPED, data[1] & Common.CELL_Y_FLIPPED, data[1] & Common.CELL_TRANSPOSED, Vector2(data[2], data[3]))
		__backup.erase(map_cell)

func reset_changes() -> void:
	for map_cell in __backup:
		# code duplication from set_cell_data for more performance
		var data = __backup[map_cell]
		if data[0] == TileMap.INVALID_CELL:
			__tile_map.set_cellv(map_cell, data[0])
		else:
			__tile_map.set_cellv(map_cell, data[0], data[1] & Common.CELL_X_FLIPPED, data[1] & Common.CELL_Y_FLIPPED, data[1] & Common.CELL_TRANSPOSED, Vector2(data[2], data[3]))
	__backup.clear()

func get_tile_set() -> TileSet:
	return __tile_map.tile_set

func get_cell_half_offset() -> int:
	return __tile_map.cell_half_offset

func get_used_rect() -> Rect2:
	return __tile_map.get_used_rect()

func get_ruler_grid_map() -> RulerGridMap:
	return __ruler_grid_map



func freeze_input() -> void:
	_is_input_freezed = true
func resume_input() -> void:
	_is_input_freezed = false













#static func create_cell_data(tile_id: int, cell_x_flipped: bool = false, cell_y_flipped: bool = false, cell_transposed: bool = false, subtile_coord: Vector2 = Vector2.ZERO) -> PoolIntArray:
#	var data = PoolIntArray()
#	if tile_id < 0:
#		data.resize(1)
#		data[0] = tile_id
#		return data
#	data.resize(4)
#	data[0] = tile_id
#	data[1] = 0
#	if cell_x_flipped:
#		data[1] |= CELL_X_FLIPPED
#	if cell_y_flipped:
#		data[1] |= CELL_Y_FLIPPED
#	if cell_transposed:
#		data[1] |= CELL_TRANSPOSED
#	data[2] = subtile_coord.x
#	data[3] = subtile_coord.y
#	return data
