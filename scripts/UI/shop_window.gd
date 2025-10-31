extends Panel

var player_inventory: PlayerInventory
var player_inv_component: InventoryComponent
@export var merchant_id: String = ""
@export var merchant_inventory: MerchantInventory

@onready var sell_list: VBoxContainer = $ContentPanel/HBoxContainer/SellPanel/SellScroll/SellList
@onready var buy_list: VBoxContainer = $ContentPanel/HBoxContainer/BuyPanel/BuyScroll/BuyList
@onready var money_label: Label = $FooterPanel/MoneyContainer/MoneyLabel

func _ready() -> void:
	visible = false

func open_shop(player_inv: PlayerInventory, merchant_inv: MerchantInventory, merch_id: String = "") -> void:
	player_inventory = player_inv
	player_inv_component = player_inv.inventory_component
	merchant_inventory = merchant_inv
	merchant_id = merch_id if merch_id else merchant_inv.merchant_name
	
	# Register this shop window with the merchant so it can send RPCs back to us
	# This needs to be an RPC to the server's MerchantInventory instance
	merchant_inventory.shop_window = self
	
	print("=== SHOP OPEN DEBUG ===")
	print("Player ID: %d" % multiplayer.get_unique_id())
	print("Player inventory valid: %s" % (player_inventory != null))
	print("Inventory component valid: %s" % (player_inv_component != null))
	if player_inv_component:
		var slots = player_inv_component.get_slots()
		print("Inventory slots count: %d" % slots.size())
		var item_count = 0
		for slot in slots:
			if slot and slot.item:
				item_count += 1
		print("Items in inventory: %d" % item_count)
	print("Registered shop window with merchant: %s" % (merchant_inventory.shop_window != null))
	print("=== END DEBUG ===")
	
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
	if player_inv_component and player_inv_component.inventory_changed.is_connected(update_displays):
		player_inv_component.inventory_changed.disconnect(update_displays)
	visible = false

# Separate RPC for updating just the sell display
@rpc("authority", "call_local", "reliable")
func update_sell_display() -> void:
	print("=== UPDATE SELL DISPLAY DEBUG ===")
	print("Player %d updating sell display" % multiplayer.get_unique_id())
	update_displays()
	print("=== END DEBUG ===")

# This RPC is called by the server to update the client's shop UI
@rpc("authority", "call_local", "reliable")
func receive_shop_data(data: Array):
	print("=== RECEIVE SHOP DATA DEBUG ===")
	print("Player %d received shop data with %d items" % [multiplayer.get_unique_id(), data.size()])
	
	# Clear buy list
	for child in buy_list.get_children():
		child.queue_free()
	
	# Populate buy list with merchant's items
	for item_data in data:
		add_shop_item(buy_list, item_data, false)
	
	print("Added %d items to buy list" % buy_list.get_child_count())
	print("=== END DEBUG ===")

func update_displays() -> void:
	print("=== UPDATE DISPLAYS DEBUG ===")
	print("Player ID: %d" % multiplayer.get_unique_id())
	
	# Clear sell list
	for child in sell_list.get_children():
		child.queue_free()
	
	# Populate sell list with player's items
	if player_inv_component:
		var slots = player_inv_component.get_slots()
		print("Updating sell list with %d slots" % slots.size())
		var items_added = 0
		for i in slots.size():
			var slot = slots[i]
			if slot.item:
				add_shop_item(sell_list, {"item": slot.item, "slot_index": i}, true)
				items_added += 1
		print("Added %d items to sell list" % items_added)
	else:
		print("WARNING: player_inv_component is null!")
	
	# Update money display
	if player_inventory:
		money_label.text = player_inv_component.format_number_with_commas(player_inventory.monies_amount) + " Monies"
	print("=== END UPDATE DISPLAYS DEBUG ===")

@rpc("authority", "call_local", "reliable")
func update_money_display(new_monies_amount: int) -> void:
	if player_inventory:
		player_inventory.monies_amount = new_monies_amount # Update client's local monies amount
		money_label.text = player_inv_component.format_number_with_commas(new_monies_amount) + " Monies"

func add_shop_item(container: VBoxContainer, data: Dictionary, is_sell: bool) -> void:
	var item: ItemData
	var price: int
	var count: int = 1
	var is_buyback: bool = false
	
	if is_sell:
		# Player is selling their item to merchant
		item = data["item"]
		price = merchant_inventory.get_sell_price(item.item_id)
		count = item.current_stack_amount
	else:
		# Player is buying from merchant (either base stock or buyback)
		price = data["price"]
		count = data["count"]
		is_buyback = data.get("is_buyback", false)
		if is_buyback:
			print("DEBUG: add_shop_item - item_dict for buyback: %s" % data["item_dict"])
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
	
	# Name and details
	var info_container = VBoxContainer.new()
	info_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_container.add_theme_constant_override("separation", 2)
	info_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var name_label = Label.new()
	name_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.2, 1))
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var display_name = item.name
	if count > 1:
		display_name += " ×" + str(count)
	name_label.text = display_name
	info_container.add_child(name_label)
	
	# Buyback tag
	if is_buyback:
		var buyback_label = Label.new()
		buyback_label.add_theme_color_override("font_color", Color(0.3, 0.6, 0.9, 1))
		buyback_label.add_theme_font_size_override("font_size", 9)
		buyback_label.text = "Buyback"
		buyback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_container.add_child(buyback_label)
	
	row.add_child(info_container)
	
	# Price
	var price_container = VBoxContainer.new()
	price_container.add_theme_constant_override("separation", 0)
	price_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var price_label = Label.new()
	price_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.2, 1))
	price_label.add_theme_font_size_override("font_size", 12)
	price_label.text = str(price)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_container.add_child(price_label)
	
	var monies_label = Label.new()
	monies_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 1))
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
