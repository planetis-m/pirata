import typetraits

import ./pirata/[entities, slottables]

export entities

type
  QueryMask*[K: enum] = set[K]

  Column = object
    data: pointer
    destroySlots: proc (data: pointer; capacity: int) {.nimcall, raises: [].}

  PirataWorld*[K: enum] = object
    signatures: SlotTable[K]
    registry: array[K, Column]
    capacity: EntityBits

template asArray[T](data: pointer): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](data)

func containsAll[K: enum](mask, required: QueryMask[K]): bool {.inline.} =
  required <= mask

func intersects[K: enum](a, b: QueryMask[K]): bool {.inline.} =
  (a * b) != {}

proc allocColumn[T](capacity: int): pointer =
  let bytes = capacity * sizeof(T)
  when supportsCopyMem(T):
    result = allocShared(bytes)
  else:
    result = allocShared0(bytes)

proc destroyColumnSlots[T](data: pointer; capacity: int) =
  when not supportsCopyMem(T):
    for slot in 0..<capacity:
      `=destroy`(asArray[T](data)[slot])

proc `=destroy`*[K](world: var PirataWorld[K]) =
  for kind in low(K)..high(K):
    let col = world.registry[kind]
    if not col.data.isNil:
      if col.destroySlots != nil:
        col.destroySlots(col.data, int(world.capacity))
      deallocShared(col.data)
  `=destroy`(world.signatures)

proc `=wasMoved`*[K](world: var PirataWorld[K]) =
  `=wasMoved`(world.signatures)
  for kind in low(K)..high(K):
    world.registry[kind].data = nil

proc `=copy`*[K](dest: var PirataWorld[K]; src: PirataWorld[K]) {.error.}
proc `=dup`*[K](src: PirataWorld[K]): PirataWorld[K] {.error.}

proc newPirata*[K: enum](maxEntities = 1024): PirataWorld[K] =
  result = PirataWorld[K](
    capacity: EntityBits(maxEntities),
    signatures: initSlotTableOfCap[K](maxEntities)
  )

proc contains*[K: enum](world: PirataWorld[K]; entity: Entity): bool {.inline.} =
  world.signatures.contains(entity)

template signature[K: enum](world: PirataWorld[K]; entity: Entity): untyped =
  world.signatures.valueAtSlot(entity.idx)

proc registerComponent[T; K: enum](world: var PirataWorld[K]; kind: K) =
  world.registry[kind] = Column(
    data: allocColumn[T](int(world.capacity)),
    destroySlots: when supportsCopyMem(T): nil else: destroyColumnSlots[T]
  )

proc registerTag*[K: enum](world: var PirataWorld[K]; kind: K) =
  world.registry[kind] = Column(
    data: nil,
    destroySlots: nil
  )

proc spawn*[K: enum](world: var PirataWorld[K]): Entity {.inline.} =
  world.signatures.incl({})

proc destroy*[K: enum](world: var PirataWorld[K]; entity: Entity) =
  world.signatures.delAt(entity.idx)

proc has*[K: enum](world: PirataWorld[K]; entity: Entity; kind: K): bool =
  kind in world.signature(entity)

proc add*[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K; value: sink T) =
  asArray[T](world.registry[kind].data)[entity.idx] = value
  world.signature(entity).incl(kind)

proc add*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  world.signature(entity).incl(kind)

proc remove*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  world.signature(entity).excl(kind)

iterator query*[K: enum](world: PirataWorld[K], all: QueryMask[K] = {}, none: QueryMask[K] = {}): Entity =
  for entry in world.signatures.pairs:
    if entry.value.containsAll(all) and not entry.value.intersects(none):
      yield entry.e

proc register*[T; K: enum](world: var PirataWorld[K]; kind: K; _: typedesc[T]) {.inline.} =
  registerComponent[T, K](world, kind)

proc fetch*[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K; _: typedesc[T]): var T {.inline.} =
  asArray[T](world.registry[kind].data)[entity.idx]
