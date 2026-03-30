import typetraits

import ./pirata/[entities, slottables]

export entities

type
  QueryMask*[K: enum] = set[K]

  Column = object
    data: pointer
    clearSlot: proc (data: pointer; slot: int) {.nimcall, raises: [].}
    traceSlot: proc (data: pointer; slot: int; env: pointer) {.nimcall, raises: [].}
    freeData: proc (data: pointer) {.nimcall, raises: [].}

  PirataWorld*[K: enum] = object
    signatures: SlotTable[QueryMask[K]]
    registry: array[K, Column]
    registered: QueryMask[K]
    capacity: EntityImpl

template asArray[T](data: pointer): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](data)

proc `=trace`*[K](world: var PirataWorld[K]; env: pointer) {.raises: [].}

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

proc freeColumn(data: pointer) =
  deallocShared(data)

proc clearColumnSlot[T](data: pointer; slot: int) {.raises: [].} =
  when supportsCopyMem(T):
    zeroMem(addr asArray[T](data)[slot], sizeof(T))
  else:
    reset(asArray[T](data)[slot])

proc traceColumnSlot[T](data: pointer; slot: int; env: pointer) {.raises: [].} =
  when not supportsCopyMem(T):
    `=trace`(asArray[T](data)[slot], env)

proc freeColumnStorage(data: pointer) {.raises: [].} =
  if not data.isNil:
    freeColumn(data)

proc `=destroy`*[K](world: var PirataWorld[K]) {.raises: [].} =
  for signatureEntry in world.signatures.pairs:
    let entity = signatureEntry.e
    for kind in signatureEntry.value:
      let col = world.registry[kind]
      if not col.data.isNil:
        col.clearSlot(col.data, entity.idx)
  for kind in low(K)..high(K):
    let col = world.registry[kind]
    if not col.data.isNil:
      col.freeData(col.data)
    world.registry[kind] = default(Column)
  world.registered = {}
  world.capacity = 0
  `=destroy`(world.signatures)

proc `=trace`*[K](world: var PirataWorld[K]; env: pointer) {.raises: [].} =
  `=trace`(world.signatures, env)
  for signatureEntry in world.signatures.pairs:
    let entity = signatureEntry.e
    for kind in signatureEntry.value:
      let col = world.registry[kind]
      if not col.data.isNil:
        col.traceSlot(col.data, entity.idx, env)

proc `=copy`*[K](dest: var PirataWorld[K]; src: PirataWorld[K]) {.error.}
proc `=dup`*[K](src: PirataWorld[K]): PirataWorld[K] {.error.}

proc newPirata*[K: enum](maxEntities = 1024): PirataWorld[K] =
  result = default(PirataWorld[K])
  result.capacity = EntityImpl(maxEntities)
  result.signatures = initSlotTableOfCap[QueryMask[K]](maxEntities)

proc contains*[K: enum](world: PirataWorld[K]; entity: Entity): bool {.inline.} =
  world.signatures.contains(entity)

template signature[K: enum](world: PirataWorld[K]; entity: Entity): untyped =
  world.signatures.valueAtSlot(entity.idx)

proc registerComponent[T; K: enum](world: var PirataWorld[K]; kind: K) =
  world.registry[kind] = Column(
    data: allocColumn[T](int(world.capacity)),
    clearSlot: clearColumnSlot[T],
    traceSlot: traceColumnSlot[T],
    freeData: freeColumnStorage
  )
  world.registered.incl(kind)

proc registerTag*[K: enum](world: var PirataWorld[K]; kind: K) =
  world.registry[kind] = Column(
    data: nil,
    clearSlot: nil,
    traceSlot: nil,
    freeData: nil
  )
  world.registered.incl(kind)

proc spawn*[K: enum](world: var PirataWorld[K]): Entity {.inline.} =
  world.signatures.incl({})

proc destroy*[K: enum](world: var PirataWorld[K]; entity: Entity) =
  let mask = world.signature(entity)
  for kind in mask:
    let col = world.registry[kind]
    if not col.data.isNil:
      col.clearSlot(col.data, entity.idx)
  world.signatures.delAt(entity.idx)

proc has*[K: enum](world: PirataWorld[K]; entity: Entity; kind: K): bool =
  kind in world.signature(entity)

proc add*[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K; value: sink T) =
  asArray[T](world.registry[kind].data)[entity.idx] = value
  world.signature(entity).incl(kind)

proc add*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  world.signature(entity).incl(kind)

proc fetchSlot[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K): var T =
  asArray[T](world.registry[kind].data)[entity.idx]

proc remove*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  let col = world.registry[kind]
  if not col.data.isNil:
    col.clearSlot(col.data, entity.idx)
  world.signature(entity).excl(kind)

iterator query*[K: enum](world: PirataWorld[K], all: QueryMask[K] = {}, none: QueryMask[K] = {}): Entity =
  for entry in world.signatures.pairs:
    if entry.value.containsAll(all) and not entry.value.intersects(none):
      yield entry.e

proc register*[T; K: enum](world: var PirataWorld[K]; kind: K; _: typedesc[T]) {.inline.} =
  registerComponent[T, K](world, kind)

proc fetch*[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K; _: typedesc[T]): var T {.inline.} =
  fetchSlot[T, K](world, entity, kind)
