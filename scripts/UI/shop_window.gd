extends Panel

const TAB_EQUIP := 0
const TAB_USE := 1
const TAB_ETC := 2
const TAB_BUYBACK := 3  # Buy panel only

var player_inventory: PlayerInventory
var player_inv_component: InventoryComponent
@export var merchant_id: String = ""
@export var merchant_inventory: MerchantInventory

@onready var header_panel: Panel = $HeaderPanel
@onready var shop_title: Label = $HeaderPanel/ShopTitle
@onready var close_button: Button = $HeaderPanel/CloseButton

@onready var sell_tabs: TabContainer = %SellTabs
@onready var buy_tabs: TabContainer = %BuyTabs

@onready var sell_list_equip: VBoxContainer = %SellListEquip
@onready var sell_list_use: VBoxContainer = %SellListUse
@onready var sell_list_etc: VBoxContainer = %SellListEtc

@onready var buy_list_equip: VBoxContainer = %BuyListEquip
@onready var buy_list_use: VBoxContainer = %BuyListUse
@onready var buy_list_etc: VBoxContainer = %BuyListEtc
@onready var buy_list_buyback: VBoxContainer = %BuyListBuyback

@onready var money_label: Label = $FooterPanel/MoneyContainer/MoneyLabel

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("ui_window")
	visible = false
	visibility_changed.connect(_on_visibility_changed)

func _process(_delta: float) -> void:
	if not _is_dragging:
		return
	var new_pos := get_global_mouse_position() - _drag_offset
	var vp := get_viewport_rect().size
	new_pos.x = clamp(new_pos.x, 0, vp.x - size.x)
	new_pos.y = clamp(new_pos.y, 0, vp.y - size.y)
	global_position = new_pos

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if header_panel.get_global_rect().has_point(get_global_mouse_position()):
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				move_to_front()
		else:
			_is_dragging = false

func _on_visibility_changed() -> void:
	if visible:
		return
	# When the window hides (via Esc, close button, or close_shop), drop the
	# inventory-changed signal so we don't keep refreshing a hidden UI.
	_is_dragging = false
	if player_inv_component and player_inv_component.inventory_changed.is_connected(update_displays):
		player_inv_component.inventory_changed.disconnect(update_displays)

func open_shop(player_inv: PlayerInventory, merchant_inv: MerchantInventory, merch_id: String = "") -> void:
	player_inventory = player_inv
	player_inv_component = player_inv.inventory_component
	merchant_inventory = merchant_inv
	merchant_id = merch_id if merch_id else merchant_inv.merchant_name

	if is_instance_valid(shop_title) and merchant_inventory:
		shop_title.text = merchant_inventory.merchant_name.to_upper()

	# Register this shop window with the merchant so it can send RPCs back to us
	# This needs to be an RPC to the server's MerchantInventory instance
	merchant_inventory.shop_window = self

	# Connect to player inventory changes
	if not player_inv_component.inventory_changed.is_connected(update_displays):
		player_inv_component.inventory_changed.connect(update_displays.unbind(1))

	update_displays()

	# Request shop data from server (works for both host and clients)
	if multiplayer.is_server():
		# Server can get data directly
		receive_shop_data(merchant_inventory.get_stock_data(player_inventory.owner.player_id))
	else:
		# Client requests data from server
		merchant_inventory.request_shop_data.rpc_id(1)

	visible = true

func close_shop() -> void:
	# Signal cleanup happens in _on_visibility_changed; this just hides.
	visible = false

# Separate RPC for updating just the sell display
@rpc("authority", "call_local", "reliable")
func update_sell_display() -> void:
	update_displays()

# This RPC is called by the server to update the client's shop UI
@rpc("authority", "call_local", "reliable")
func receive_shop_data(data: Array):
	_clear_lists([buy_list_equip, buy_list_use, buy_list_etc, buy_list_buyback])

	for item_data in data:
		var is_buyback: bool = item_data.get("is_buyback", false)
		var item: ItemData
		var target: VBoxContainer
		if is_buyback:
			item = ItemData.from_dictionary(item_data["item_dict"])
			target = buy_list_buyback
		else:
			item = ResourceManager.get_item_data(item_data["item_id"])
			target = _buy_list_for(item) if item else null
		if target and item:
			add_shop_item(target, item_data, false)

	_update_buy_tab_visibility()

func update_displays() -> void:
	_clear_lists([sell_list_equip, sell_list_use, sell_list_etc])

	# Populate sell lists with player's items, routed by item type
	if player_inv_component:
		var slots = player_inv_component.get_slots()
		for i in slots.size():
			var slot = slots[i]
			if slot.item:
				var target := _sell_list_for(slot.item)
				if target:
					add_shop_item(target, {"item": slot.item, "slot_index": i}, true)
	else:
		print("WARNING: player_inv_component is null!")

	# Update money display
	if player_inventory:
		money_label.text = player_inv_component.format_number_with_commas(player_inventory.monies_amount) + " Monies"

@rpc("authority", "call_local", "reliable")
func update_money_display(new_monies_amount: int) -> void:
	if player_inventory:
		var changed: bool = player_inventory.monies_amount != new_monies_amount
		player_inventory.monies_amount = new_monies_amount # Update client's local monies amount
		money_label.text = player_inv_component.format_number_with_commas(new_monies_amount) + " Monies"
		# Juice: a coin cha-ching on a real buy/sell (a no-op refresh like opening
		# the shop passes the same amount, so it stays silent).
		if changed:
			AudioManager.play_ui_sfx("res://assets/sounds/coin.wav")

# ── Tab routing ───────────────────────────────────────────────────────────────

func _sell_list_for(item: ItemData) -> VBoxContainer:
	match item.item_type:
		Constants.ItemType.EQUIPMENT: return sell_list_equip
		Constants.ItemType.CONSUMABLE: return sell_list_use
		_: return sell_list_etc

func _buy_list_for(item: ItemData) -> VBoxContainer:
	match item.item_type:
		Constants.ItemType.EQUIPMENT: return buy_list_equip
		Constants.ItemType.CONSUMABLE: return buy_list_use
		_: return buy_list_etc

func _clear_lists(lists: Array) -> void:
	for list in lists:
		for child in list.get_children():
			child.queue_free()

func _update_buy_tab_visibility() -> void:
	# Hide tabs that have no items. The merchant only sells what's stocked;
	# the buyback tab only appears once the player has sold something.
	var entries := [
		[TAB_EQUIP, buy_list_equip],
		[TAB_USE, buy_list_use],
		[TAB_ETC, buy_list_etc],
		[TAB_BUYBACK, buy_list_buyback],
	]
	for entry in entries:
		var idx: int = entry[0]
		var list: VBoxContainer = entry[1]
		buy_tabs.set_tab_hidden(idx, list.get_child_count() == 0)

	# If the active tab just got hidden, jump to the first visible one.
	if buy_tabs.get_tab_count() > 0 and buy_tabs.is_tab_hidden(buy_tabs.current_tab):
		for i in buy_tabs.get_tab_count():
			if not buy_tabs.is_tab_hidden(i):
				buy_tabs.current_tab = i
				break

func add_shop_item(container: VBoxContainer, data: Dictionary, is_sell: bool) -> void:
	var item: ItemData
	var price: int
	var count: int = 1
	var is_buyback: bool = false

	if is_sell:
		# Player is selling their item to merchant
		item = data["item"]
		price = merchant_inventory.get_sell_price(item)
		count = item.current_stack_amount
	else:
		# Player is buying from merchant (either base stock or buyback)
		price = data["price"]
		count = data["count"]
		is_buyback = data.get("is_buyback", false)
		if is_buyback:
			item = ItemData.from_dictionary(data["item_dict"])
		else:
			item = ResourceManager.get_item_data(data["item_id"])

	# Create button container
	var button = Button.new()
	button.flat = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 42

	# Add tooltip - same format as Slot
	button.tooltip_text = item.name
	if item.can_stack:
		button.tooltip_text += "\nStack: " + str(count) + "/" + str(item.max_stack_amount)
	if item.description != "":
		button.tooltip_text += "\n" + item.description
	if item.item_type == Constants.ItemType.EQUIPMENT:
		if item.equipment_type == Constants.EquipmentType.WEAPON:
			button.tooltip_text += "\n" + "Type: " + str(Constants.WeaponType.keys()[item.weapon_type]).capitalize()
			button.tooltip_text += "\n" + "Attack Speed: " + str(item.attack_speed).to_upper()
		if item.equipment_type == Constants.EquipmentType.ARMOR:
			button.tooltip_text += "\n" + "Type: " + str(Constants.ArmorType.keys()[item.armor_type]).capitalize()
		if item.bonus_stats:
			for stat_type in item.bonus_stats:
				if item.bonus_stats[stat_type].flat_bonus_value > 0:
					button.tooltip_text += "\n" + str(Constants.StatType.keys()[stat_type]).to_upper() + " : +" + str(item.bonus_stats[stat_type].flat_bonus_value)

	# Add price info to tooltip
	button.tooltip_text += "\n\nPrice: " + str(price) + " Monies"

	# Style the button with hover effect
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(1, 1, 1, 0)
	normal_style.content_margin_left = 6
	normal_style.content_margin_right = 6
	normal_style.content_margin_top = 4
	normal_style.content_margin_bottom = 4
	normal_style.corner_radius_top_left = 4
	normal_style.corner_radius_top_right = 4
	normal_style.corner_radius_bottom_left = 4
	normal_style.corner_radius_bottom_right = 4

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.4, 0.6, 0.9, 0.2)
	hover_style.content_margin_left = 6
	hover_style.content_margin_right = 6
	hover_style.content_margin_top = 4
	hover_style.content_margin_bottom = 4
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4
	hover_style.border_width_left = 1
	hover_style.border_width_right = 1
	hover_style.border_width_top = 1
	hover_style.border_width_bottom = 1
	hover_style.border_color = Color(0.4, 0.6, 0.9, 0.4)

	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.4, 0.6, 0.9, 0.3)
	pressed_style.content_margin_left = 6
	pressed_style.content_margin_right = 6
	pressed_style.content_margin_top = 4
	pressed_style.content_margin_bottom = 4
	pressed_style.corner_radius_top_left = 4
	pressed_style.corner_radius_top_right = 4
	pressed_style.corner_radius_bottom_left = 4
	pressed_style.corner_radius_bottom_right = 4
	pressed_style.border_width_left = 1
	pressed_style.border_width_right = 1
	pressed_style.border_width_top = 1
	pressed_style.border_width_bottom = 1
	pressed_style.border_color = Color(0.4, 0.6, 0.9, 0.6)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)

	# Create row content
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Icon with background
	var icon_container = PanelContainer.new()
	icon_container.custom_minimum_size = Vector2(36, 36)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(0.2, 0.2, 0.25, 0.15)
	icon_style.corner_radius_top_left = 4
	icon_style.corner_radius_top_right = 4
	icon_style.corner_radius_bottom_left = 4
	icon_style.corner_radius_bottom_right = 4
	icon_container.add_theme_stylebox_override("panel", icon_style)

	var icon = TextureRect.new()
	icon.texture = item.icon
	icon.custom_minimum_size = Vector2(32, 32)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon)
	row.add_child(icon_container)

	# Name (buyback now has its own dedicated tab — no per-row "Buyback" label)
	var info_container = VBoxContainer.new()
	info_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_container.add_theme_constant_override("separation", 2)
	info_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label = Label.new()
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var display_name = item.name
	if count > 1:
		display_name += " ×" + str(count)
	name_label.text = display_name
	info_container.add_child(name_label)

	row.add_child(info_container)

	# Price
	var price_container = VBoxContainer.new()
	price_container.add_theme_constant_override("separation", 0)
	price_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var price_label = Label.new()
	price_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1))
	price_label.add_theme_font_size_override("font_size", 12)
	price_label.text = str(price)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_container.add_child(price_label)

	var monies_label = Label.new()
	monies_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
	monies_label.add_theme_font_size_override("font_size", 8)
	monies_label.text = "Monies"
	monies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	monies_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_container.add_child(monies_label)

	row.add_child(price_container)

	button.add_child(row)
	button.pressed.connect(_on_item_clicked.bind(data, is_sell, is_buyback))
	container.add_child(button)

func _on_item_clicked(data: Dictionary, is_sell: bool, is_buyback: bool = false) -> void:
	if is_sell:
		var slot_index = data["slot_index"]
		merchant_inventory.request_sell_item.rpc_id(1, slot_index)
	else:
		var item_id = data["item_id"]
		var is_stackable_buyback = data.get("is_stackable_buyback", false)
		merchant_inventory.request_buy_item.rpc_id(1, item_id, is_buyback, is_stackable_buyback)
