import typetraits

import ./pirata/[entities, slottables]

export entities

type
  QueryMask*[K: enum] = set[K]

  ComponentEntry = object
    data: pointer
    clearSlotOp: proc (data: pointer; slot: int) {.nimcall, raises: [].}
    traceSlotOp: proc (data: pointer; slot: int; env: pointer) {.nimcall, raises: [].}
    freeOp: proc (data: pointer) {.nimcall, raises: [].}
    slotSize: uint32

  PirataWorld*[K: enum] = object
    signatures: SlotTable[QueryMask[K]]
    registry: array[K, ComponentEntry]
    registered: QueryMask[K]
    capacity: EntityImpl

template typedData[T](data: pointer): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](data)

template forEachLivePayload(world, entity, kind, entry, body: untyped) =
  for signatureEntry in world.signatures.pairs:
    let entity {.inject.} = signatureEntry.e
    for kind in signatureEntry.value:
      let entry {.inject.} = world.registry[kind]
      if not entry.data.isNil:
        body

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
    zeroMem(addr typedData[T](data)[slot], sizeof(T))
  else:
    reset(typedData[T](data)[slot])

proc traceColumnSlot[T](data: pointer; slot: int; env: pointer) {.raises: [].} =
  when not supportsCopyMem(T):
    `=trace`(typedData[T](data)[slot], env)

proc freeColumnStorage(data: pointer) {.raises: [].} =
  if not data.isNil:
    freeColumn(data)

proc `=destroy`*[K](world: var PirataWorld[K]) {.raises: [].} =
  forEachLivePayload(world, entity, kind, entry):
    entry.clearSlotOp(entry.data, entity.idx)
  for kind in low(K)..high(K):
    let entry = world.registry[kind]
    if not entry.data.isNil:
      entry.freeOp(entry.data)
    world.registry[kind] = default(ComponentEntry)
  world.registered = {}
  world.capacity = 0
  `=destroy`(world.signatures)

proc `=trace`*[K](world: var PirataWorld[K]; env: pointer) {.raises: [].} =
  `=trace`(world.signatures, env)
  forEachLivePayload(world, entity, kind, entry):
    entry.traceSlotOp(entry.data, entity.idx, env)

proc `=copy`*[K](dest: var PirataWorld[K]; src: PirataWorld[K]) {.error.}
proc `=dup`*[K](src: PirataWorld[K]): PirataWorld[K] {.error.}

proc newPirata*[K: enum](maxEntities = 1024): PirataWorld[K] =
  result = default(PirataWorld[K])
  result.capacity = EntityImpl(maxEntities)
  result.signatures = initSlotTableOfCap[QueryMask[K]](maxEntities)

proc contains*[K: enum](world: PirataWorld[K]; entity: Entity): bool {.inline.} =
  world.signatures.lookupIndex(entity) >= 0

template signatureAtEntity[K: enum](world: PirataWorld[K]; entity: Entity): untyped =
  world.signatures.valueAtSlot(entity.idx)

proc registerComponentImpl[T; K: enum](world: var PirataWorld[K]; kind: K) =
  world.registry[kind] = ComponentEntry(
    data: allocColumn[T](int(world.capacity)),
    clearSlotOp: clearColumnSlot[T],
    traceSlotOp: traceColumnSlot[T],
    freeOp: freeColumnStorage,
    slotSize: uint32(sizeof(T))
  )
  world.registered.incl(kind)

proc registerTag*[K: enum](world: var PirataWorld[K]; kind: K) =
  world.registry[kind] = ComponentEntry(
    data: nil,
    clearSlotOp: nil,
    traceSlotOp: nil,
    freeOp: nil,
    slotSize: 0
  )
  world.registered.incl(kind)

proc spawn*[K: enum](world: var PirataWorld[K]): Entity {.inline.} =
  world.signatures.incl({})

proc destroy*[K: enum](world: var PirataWorld[K]; entity: Entity) =
  let signature = world.signatureAtEntity(entity)
  for kind in signature:
    let entry = world.registry[kind]
    if not entry.data.isNil:
      entry.clearSlotOp(entry.data, entity.idx)
  world.signatures.delAt(entity.idx)

proc has*[K: enum](world: PirataWorld[K]; entity: Entity; kind: K): bool =
  kind in world.signatureAtEntity(entity)

proc add*[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K; value: sink T) =
  template entry: untyped = world.registry[kind]
  typedData[T](entry.data)[entity.idx] = value
  world.signatureAtEntity(entity).incl(kind)

proc add*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  world.signatureAtEntity(entity).incl(kind)

proc fetchImpl[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K): var T =
  typedData[T](world.registry[kind].data)[entity.idx]

proc remove*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  template entry: untyped = world.registry[kind]
  if not entry.data.isNil:
    entry.clearSlotOp(entry.data, entity.idx)
  world.signatureAtEntity(entity).excl(kind)

iterator query*[K: enum](
  world: PirataWorld[K],
  all: QueryMask[K] = {},
  none: QueryMask[K] = {}
): Entity =
  for entry in world.signatures.pairs:
    if entry.value.containsAll(all) and not entry.value.intersects(none):
      yield entry.e

proc register*[T; K: enum](
  world: var PirataWorld[K];
  kind: K;
  _: typedesc[T]
) {.inline.} =
  registerComponentImpl[T, K](world, kind)

proc fetch*[T; K: enum](
  world: var PirataWorld[K];
  entity: Entity;
  kind: K;
  _: typedesc[T]
): var T {.inline.} =
  fetchImpl[T, K](world, entity, kind)
