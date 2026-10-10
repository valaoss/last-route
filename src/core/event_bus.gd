extends Node

signal player_mounted(bike: Node)
signal player_dismounted(bike: Node)
signal bike_crashed(bike: Node, impact: float)
signal enemy_killed(enemy: Node, by_weapon: StringName)
signal player_damaged(amount: float, source: Node)
signal player_died
signal hit_confirmed(kill: bool, headshot: bool)
signal weapon_fired(weapon_id: StringName)
signal camera_impulse(strength: float)
signal toast(text: String)
signal radio(speaker: String, text: String)
signal mission_interact(target_id: String)
