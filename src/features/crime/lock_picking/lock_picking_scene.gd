extends Node3D

signal open_attempt(success: bool)

@export var screw_driver_sound: AudioStreamPlayer
@export var metal_pick_sound: AudioStreamPlayer

@export var screw_driver_pivot: Node3D
@export var metal_pick_pivot: Node3D

@export var prompt: Control

@export_group("Physics Tuning")
@export var acceleration: float = 400.0       # Player input force (deg/s^2)
@export var fall_acceleration: float = 200.0  # Constant falling force (deg/s^2)
@export var damping: float = 3.0              # Friction/resistance factor
@export var max_speed: float = 180.0          # Max rotation speed (deg/s)

@export_group("Lock Settings")
## Half-width of the sweet spot in degrees. 2.5 creates a 5-degree total window (+/- 2.5 deg).
@export var sweet_spot_tolerance: float = 5

# Oikeat kulmat lukon avaamiseksi
var screw_driver_sweet_spot: float = 0.0
var metal_pick_sweet_spot: float = 0.0

# Työkalujen nopeudet
var screw_driver_velocity: float = 0.0
var metal_pick_velocity: float = 0.0

# Sweet spotin ohituksen seuranta
var was_screwdriver_in_spot: bool = false
var was_metal_pick_in_spot: bool = false


func _ready() -> void:
	initialize_lock()


func initialize_lock() -> void:
	# Arvotaan sweetspotit 5 asteen välein väliltä [-90, 90]
	screw_driver_sweet_spot = randi_range(-16, 16) * 5.0
	metal_pick_sweet_spot = randi_range(-16, 16) * 5.0
	
	# Nollataan työkalujen aloitusasennot ja nopeudet
	screw_driver_velocity = 0.0
	metal_pick_velocity = 0.0
	was_screwdriver_in_spot = false
	was_metal_pick_in_spot = false
	
	if screw_driver_pivot:
		screw_driver_pivot.rotation_degrees.z = 0.0
	if metal_pick_pivot:
		metal_pick_pivot.rotation_degrees.z = 0.0


func _physics_process(delta: float) -> void:
	if not visible:
		return
	
	update_screwdriver_physics(delta)
	update_metal_pick_physics(delta)
	
	# Avausyritys
	if Input.is_action_just_pressed("lockpick_open"):
		attempt_open()


func update_screwdriver_physics(delta: float) -> void:
	if not screw_driver_pivot:
		return
		
	var prev_rot: float = screw_driver_pivot.rotation_degrees.z
	
	# Jatkuva putoaminen kohti Negaatiivista Z-akselia (-1.0)
	screw_driver_velocity -= fall_acceleration * delta
	
	# Pelaajan ohjaus (Vasen / Oikea)
	var input_dir: float = Input.get_axis("lockpick_left", "lockpick_right")
	screw_driver_velocity += input_dir * acceleration * delta
	
	# Ilmanvastus / kitka
	screw_driver_velocity = lerp(screw_driver_velocity, 0.0, damping * delta)
	screw_driver_velocity = clamp(screw_driver_velocity, -max_speed, max_speed)
	
	screw_driver_pivot.rotation_degrees.z += screw_driver_velocity * delta
	
	# Törmäys rajoihin [-90, 90]
	if screw_driver_pivot.rotation_degrees.z <= -90.0:
		screw_driver_pivot.rotation_degrees.z = -90.0
		screw_driver_velocity = 0.0
	elif screw_driver_pivot.rotation_degrees.z >= 90.0:
		screw_driver_pivot.rotation_degrees.z = 90.0
		screw_driver_velocity = 0.0
		
	var current_rot: float = screw_driver_pivot.rotation_degrees.z
	
	# Tarkistetaan ohittiko meisseli sweetspotin tällä framella
	if check_sweet_spot_crossed(prev_rot, current_rot, screw_driver_sweet_spot):
		if not was_screwdriver_in_spot and screw_driver_sound:
			screw_driver_sound.play()
		was_screwdriver_in_spot = true
	else:
		was_screwdriver_in_spot = false


func update_metal_pick_physics(delta: float) -> void:
	if not metal_pick_pivot:
		return
		
	var prev_rot: float = metal_pick_pivot.rotation_degrees.z
	
	# Jatkuva putoaminen kohti Positiivista Z-akselia (+1.0)
	metal_pick_velocity += fall_acceleration * delta
	
	# Pelaajan ohjaus (Alas / Ylös)
	var input_dir: float = Input.get_axis("lockpick_up", "lockpick_down")
	metal_pick_velocity += input_dir * acceleration * delta
	
	# Ilmanvastus / kitka
	metal_pick_velocity = lerp(metal_pick_velocity, 0.0, damping * delta)
	metal_pick_velocity = clamp(metal_pick_velocity, -max_speed, max_speed)
	
	metal_pick_pivot.rotation_degrees.z += metal_pick_velocity * delta
	
	if metal_pick_pivot.rotation_degrees.z <= -90.0:
		metal_pick_pivot.rotation_degrees.z = -90.0
		metal_pick_velocity = 0.0
	elif metal_pick_pivot.rotation_degrees.z >= 90.0:
		metal_pick_pivot.rotation_degrees.z = 90.0
		metal_pick_velocity = 0.0
		
	var current_rot: float = metal_pick_pivot.rotation_degrees.z
	
	if check_sweet_spot_crossed(prev_rot, current_rot, metal_pick_sweet_spot):
		if not was_metal_pick_in_spot and metal_pick_sound:
			metal_pick_sound.play()
		was_metal_pick_in_spot = true
	else:
		was_metal_pick_in_spot = false


## Palauttaa true, jos työkalu siirtyi sweet spot -alueen läpi tai päätyi sen sisälle
func check_sweet_spot_crossed(from_rot: float, to_rot: float, sweet_spot: float) -> bool:
	var move_min: float = min(from_rot, to_rot)
	var move_max: float = max(from_rot, to_rot)
	
	var zone_min: float = sweet_spot - sweet_spot_tolerance
	var zone_max: float = sweet_spot + sweet_spot_tolerance
	
	return (move_min <= zone_max) and (move_max >= zone_min)


func attempt_open() -> void:
	var screwdriver_correct: bool = false
	var metal_pick_correct: bool = false
	
	if screw_driver_pivot:
		screwdriver_correct = abs(screw_driver_pivot.rotation_degrees.z - screw_driver_sweet_spot) <= sweet_spot_tolerance
		
	if metal_pick_pivot:
		metal_pick_correct = abs(metal_pick_pivot.rotation_degrees.z - metal_pick_sweet_spot) <= sweet_spot_tolerance
	
	var success: bool = screwdriver_correct and metal_pick_correct
	
	if prompt and prompt.has_signal("_resolved"):
		prompt._resolved.emit(success)
	else:
		open_attempt.emit(success)
