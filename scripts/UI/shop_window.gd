extends Panel

var player_inventory: PlayerInventory
var player_inv_component: InventoryComponent
@export var merchant_id: String = ""
@export var merchant_inventory: MerchantInventory

@onready var sell_list: VBoxContainer = $HBoxContainer/SellPanel/SellScroll/SellList
@onready var buy_list: VBoxContainer = $HBoxContainer/BuyPanel/BuyScroll/BuyList
@onready var money_label: Label = $MoneyContainer/MoneyLabel

func _ready() -> void:
	visible = false

func open_shop(player_inv: PlayerInventory, merchant_inv: MerchantInventory, merch_id: String = "") -> void:
	player_inventory = player_inv
	player_inv_component = player_inv.inventory_component
	merchant_inventory = merchant_inv
	merchant_id = merch_id if merch_id else merchant_inv.merchant_name
	
	# Register this shop window with the merchant so it can send RPCs back to us
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
		item = ResourceManager.get_item_data(data["item_id"])
		price = data["price"]
		count = data["count"]
		is_buyback = data.get("is_buyback", false)
	
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	
	var icon = TextureRect.new()
	icon.texture = item.icon
	icon.custom_minimum_size = Vector2(32, 32)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	
	var name_label = Label.new()
	name_label.add_theme_color_override("font_color", Color.BLACK)
	var display_name = item.name
	if count > 1:
		display_name += " x" + str(count)
	if is_buyback:
		display_name += " (Buyback)"
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	
	var price_label = Label.new()
	price_label.add_theme_color_override("font_color", Color.BLACK)
	price_label.text = str(price) + " Monies"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price_label)
	
	var button = Button.new()
	button.flat = true
	button.add_child(row)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 32
	button.pressed.connect(_on_item_clicked.bind(data, is_sell, is_buyback))
	container.add_child(button)

func _on_item_clicked(data: Dictionary, is_sell: bool, is_buyback: bool = false) -> void:
	if is_sell:
		var slot_index = data["slot_index"]
		merchant_inventory.request_sell_item.rpc_id(1, slot_index)
	else:
		var item_id = data["item_id"]
		merchant_inventory.request_buy_item.rpc_id(1, item_id, is_buyback)
