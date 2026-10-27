extends Node
## Global signal bus (autoload "Events").
## Systems talk through these signals so world, combat and progression code
## never need direct references to each other. Add new signals here only.

# Combat
signal actor_damaged(target: Node, amount: int, source: Node, is_crit: bool)
signal actor_healed(target: Node, amount: int, source: Node)
signal actor_died(actor: Node, killer: Node)
signal skill_used(caster: Node, skill_id: String)
signal target_changed(new_target: Node)

# Progression
signal xp_gained(actor: Node, amount: int)
signal level_up(actor: Node, new_level: int)
signal loot_dropped(item_id: String, quantity: int, world_position: Vector2)
signal item_picked_up(item_id: String, quantity: int)
signal inventory_changed()
signal equipment_changed(slot: String)
signal gold_changed(new_total: int)

# World
signal player_spawned(player: Node)
signal zone_loaded(zone_id: String)
signal ground_clicked(world_position: Vector2)
