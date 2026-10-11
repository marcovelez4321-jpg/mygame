class_name BackpackHold
extends Resource

## How the open backpack is held in first person (BackpackView): where the
## bag sits on screen, where on it the left hand grips and how, and how the
## top unzips. The user tunes it in game (F2, then O with the bag open; F3
## saves this file) or here in the inspector.
## Starting position (the user's): the left hand in a fist round the top of
## the backpack, the zipper opening so you see inside and click the items.

@export_group("Bag")
## Where the bag sits (camera space: x right, y up, -z ahead) and its turn.
@export var bag_position: Vector3 = Vector3(-0.08, -0.42, -0.62)
@export var bag_rotation_degrees: Vector3 = Vector3(-38.0, 12.0, 0.0)
## The pack's model is far too big (1.3 m tall): this brings it to size
## (60% bigger than the first try: the user's).
@export var bag_scale: float = 0.672
## How long it takes to swing round from your back, and to unzip.
@export var swing_time: float = 0.35
@export var unzip_time: float = 0.3
## How much of the top unzips (a share of the bag's height).
@export_range(0.0, 0.6, 0.01) var zipper_open_share: float = 0.22

@export_group("Hand")
## Where on the bag the left hand grips (bag space, as a share of the bag's
## size from its middle: y 0.5 = the very top) -- the top handle.
@export var handle_point: Vector3 = Vector3(0.0, 0.48, -0.15)
## The hand turned from gripping the handle straight (degrees).
@export var hand_rotation_degrees: Vector3 = Vector3.ZERO
## How tight the fist is (0 open .. 1 closed).
@export_range(0.0, 1.0, 0.05) var fist: float = 0.9
## Each finger's own curl on top of the fist (thumb, index, middle, ring,
## pinky; -1 .. 1, added to `fist`).
@export var finger_curl: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
## Which way the elbow points (camera space), and its bend (degrees).
@export var elbow_direction: Vector3 = Vector3(-0.7, -1.0, 0.3)
@export_range(40.0, 170.0, 1.0) var elbow_degrees: float = 100.0

@export_group("Items")
## Where the items sit in the open top (bag space, shares of its size): a
## box they're laid out in, a grid of them.
@export var items_area: AABB = AABB(Vector3(-0.36, 0.18, -0.3), Vector3(0.72, 0.18, 0.6))
## How big each item prop is drawn (metres, its longest side).
@export var item_size: float = 0.12