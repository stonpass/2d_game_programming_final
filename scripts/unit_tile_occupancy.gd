extends Node

const EMPTY_SOURCE_ID := 0
const RAMP_SOURCE_ID := 2
const DEFAULT_ATLAS := Vector2i(0, 0)

@export var tile_map_path: NodePath

var tile_map: TileMapLayer
var occupied_cells: Dictionary = {}
var converted_cells: Dictionary = {}

func _ready():
	tile_map = get_node_or_null(tile_map_path)

func _process(_delta):
	if not tile_map:
		return
	var placement = get_tree().get_first_node_in_group("BuildingPlacement")
	if not placement or not placement.get("active"):
		_clear_converted_cells()
		occupied_cells.clear()
		return

	var current_cells: Dictionary = {}
	var selected_units = _get_selected_units()
	for unit in get_tree().get_nodes_in_group("Unit"):
		if not is_instance_valid(unit) or not (unit is Node2D):
			continue
		if selected_units.has(unit):
			continue
		var cell = tile_map.local_to_map(tile_map.to_local(unit.global_position))
		current_cells[cell] = true
		if not occupied_cells.has(cell) and tile_map.get_cell_source_id(cell) == EMPTY_SOURCE_ID:
			tile_map.set_cell(cell, RAMP_SOURCE_ID, DEFAULT_ATLAS)
			converted_cells[cell] = true

	for cell in occupied_cells.keys():
		if not current_cells.has(cell) and converted_cells.has(cell) and tile_map.get_cell_source_id(cell) == RAMP_SOURCE_ID:
			tile_map.set_cell(cell, EMPTY_SOURCE_ID, DEFAULT_ATLAS)
			converted_cells.erase(cell)

	occupied_cells = current_cells

func _clear_converted_cells():
	for cell in converted_cells.keys():
		if tile_map and tile_map.get_cell_source_id(cell) == RAMP_SOURCE_ID:
			tile_map.set_cell(cell, EMPTY_SOURCE_ID, DEFAULT_ATLAS)
	converted_cells.clear()

func _get_selected_units() -> Dictionary:
	var selected: Dictionary = {}
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if not manager or not ("unit_selected" in manager):
		return selected
	for unit in manager.unit_selected:
		if is_instance_valid(unit):
			selected[unit] = true
	return selected
