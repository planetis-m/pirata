import typetraits

import ./pirata/[entities, slottables]

export entities

type
  PirataError* = object of CatchableError

  QueryMask*[K: enum] = set[K]

  ComponentEntry = object
    data: pointer
    clearSlotOp: proc (data: pointer; slot: int) {.nimcall, raises: [].}
    destroyOp: proc (data: pointer; capacity: int) {.nimcall, raises: [].}
    slotSize: uint32

  PirataWorld*[K: enum] = object
    signatures: SlotTable[QueryMask[K]]
    registry: array[K, ComponentEntry]
    registered: QueryMask[K]
    capacity: EntityImpl

const runtimeChecksEnabled* = defined(pirataRuntimeChecks)

template typedData[T](data: pointer): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](data)

proc fail(message: string) {.noinline, noreturn.} =
  raise newException(PirataError, message)

proc `=copy`*[K](dest: var PirataWorld[K]; src: PirataWorld[K]) {.error.}
proc `=dup`*[K](src: PirataWorld[K]): PirataWorld[K] {.error.}

func containsAll*[K: enum](mask, required: QueryMask[K]): bool {.inline.} =
  required <= mask

func intersects*[K: enum](a, b: QueryMask[K]): bool {.inline.} =
  (a * b) != {}

proc allocColumn[T](capacity: int): pointer =
  let bytes = capacity * sizeof(T)
  when supportsCopyMem(T):
    when compileOption("threads"):
      result = allocShared(bytes)
    else:
      result = alloc(bytes)
  else:
    when compileOption("threads"):
      result = allocShared0(bytes)
    else:
      result = alloc0(bytes)

proc freeColumn(data: pointer) =
  when compileOption("threads"):
    deallocShared(data)
  else:
    dealloc(data)

proc clearColumnSlot[T](data: pointer; slot: int) {.raises: [].} =
  when supportsCopyMem(T):
    zeroMem(addr typedData[T](data)[slot], sizeof(T))
  else:
    reset(typedData[T](data)[slot])

proc destroyColumn[T](data: pointer; capacity: int) {.raises: [].} =
  if data.isNil:
    return
  when not supportsCopyMem(T):
    let arr = typedData[T](data)
    for i in 0 ..< capacity:
      `=destroy`(arr[i])
  freeColumn(data)

proc `=destroy`*[K](world: var PirataWorld[K]) {.raises: [].} =
  for kind in low(K) .. high(K):
    if kind notin world.registered:
      continue
    let entry = world.registry[kind]
    if entry.data.isNil:
      continue
    entry.destroyOp(entry.data, int(world.capacity))
    world.registry[kind].data = nil
  world.registered = {}
  `=destroy`(world.signatures)

proc newPirata*[K: enum](maxEntities = 1024): PirataWorld[K] =
  if maxEntities <= 0:
    fail("maxEntities must be greater than zero")
  if maxEntities > entities.maxEntities:
    fail("maxEntities must be <= " & $entities.maxEntities)

  result = default(PirataWorld[K])
  result.capacity = EntityImpl(maxEntities)
  result.signatures = initSlotTableOfCap[QueryMask[K]](maxEntities)

proc contains*[K: enum](world: PirataWorld[K]; entity: Entity): bool {.inline.} =
  world.signatures.lookupIndex(entity) >= 0

proc ensureRegistered[K: enum](world: PirataWorld[K]; kind: K) {.inline.} =
  if kind notin world.registered:
    fail("component " & $kind & " is not registered")

template signatureAtEntity[K: enum](world: PirataWorld[K]; entity: Entity): untyped =
  world.signatures.valueAtSlot(entity.idx)

template signatureAt[K: enum](world: PirataWorld[K]; i: int): untyped =
  world.signatures.valueAtIndex(i)

template ensureSized[T](entry: ComponentEntry; kind: typed) =
  if entry.slotSize != uint32(sizeof(T)):
    fail("component " & $kind & " was registered with a different payload size")

template requireAlive[K: enum](world: PirataWorld[K]; entity: Entity) =
  when runtimeChecksEnabled:
    if world.signatures.lookupIndex(entity) < 0:
      fail("stale or unknown entity " & $entity)

template requireHasComponent[K: enum](signature: QueryMask[K]; entity: Entity; kind: K) =
  when runtimeChecksEnabled:
    if kind notin signature:
      fail("entity " & $entity & " does not have component " & $kind)

template requireMissingComponent[K: enum](signature: QueryMask[K]; entity: Entity; kind: K) =
  when runtimeChecksEnabled:
    if kind in signature:
      fail("entity " & $entity & " already has component " & $kind)

template requirePayloadEntry[T](entry: ComponentEntry; kind: typed) =
  when runtimeChecksEnabled:
    if entry.data.isNil:
      fail("component " & $kind & " is a tag and cannot store payload data")
    ensureSized[T](entry, kind)

template requireTagEntry(entry: ComponentEntry; kind: typed) =
  when runtimeChecksEnabled:
    if not entry.data.isNil:
      fail("component " & $kind & " requires payload data")

proc registerComponentImpl[T; K: enum](world: var PirataWorld[K]; kind: K) =
  if kind in world.registered:
    if world.registry[kind].data.isNil:
      fail("component " & $kind & " was already registered as a tag")
    ensureSized[T](world.registry[kind], kind)
    return

  world.registry[kind] = ComponentEntry(
    data: allocColumn[T](int(world.capacity)),
    clearSlotOp: clearColumnSlot[T],
    destroyOp: destroyColumn[T],
    slotSize: uint32(sizeof(T))
  )
  world.registered.incl(kind)

proc registerTag*[K: enum](world: var PirataWorld[K]; kind: K) =
  if kind in world.registered:
    if not world.registry[kind].data.isNil:
      fail("component " & $kind & " already has payload storage")
    return

  world.registry[kind] = ComponentEntry(
    data: nil,
    clearSlotOp: nil,
    destroyOp: nil,
    slotSize: 0
  )
  world.registered.incl(kind)

proc spawn*[K: enum](world: var PirataWorld[K]): Entity {.inline.} =
  world.signatures.incl({})

proc destroy*[K: enum](world: var PirataWorld[K]; entity: Entity) =
  world.requireAlive(entity)
  let signature = world.signatureAtEntity(entity)
  for kind in signature:
    template entry: untyped = world.registry[kind]
    if entry.data.isNil:
      continue
    entry.clearSlotOp(entry.data, entity.idx)
  world.signatures.delAt(entity.idx)

proc has*[K: enum](world: PirataWorld[K]; entity: Entity; kind: K): bool =
  when runtimeChecksEnabled:
    let signatureIdx = world.signatures.lookupIndex(entity)
    if signatureIdx < 0:
      return false
    kind in world.signatureAt(signatureIdx)
  else:
    kind in world.signatureAtEntity(entity)

proc add*[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K; value: sink T) =
  world.requireAlive(entity)
  when runtimeChecksEnabled:
    world.ensureRegistered(kind)
  template signature: untyped = world.signatureAtEntity(entity)
  signature.requireMissingComponent(entity, kind)

  template entry: untyped = world.registry[kind]
  requirePayloadEntry[T](entry, kind)
  typedData[T](entry.data)[entity.idx] = value
  signature.incl(kind)

proc add*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  world.requireAlive(entity)
  when runtimeChecksEnabled:
    world.ensureRegistered(kind)
  template signature: untyped = world.signatureAtEntity(entity)
  signature.requireMissingComponent(entity, kind)
  requireTagEntry(world.registry[kind], kind)
  signature.incl(kind)

proc fetchImpl[T; K: enum](world: var PirataWorld[K]; entity: Entity; kind: K): var T =
  world.requireAlive(entity)
  when runtimeChecksEnabled:
    world.ensureRegistered(kind)
    world.signatureAtEntity(entity).requireHasComponent(entity, kind)

  template entry: untyped = world.registry[kind]
  requirePayloadEntry[T](entry, kind)
  typedData[T](entry.data)[entity.idx]

proc remove*[K: enum](world: var PirataWorld[K]; entity: Entity; kind: K) =
  world.requireAlive(entity)
  when runtimeChecksEnabled:
    world.ensureRegistered(kind)
  template signature: untyped = world.signatureAtEntity(entity)
  signature.requireHasComponent(entity, kind)

  template entry: untyped = world.registry[kind]
  if not entry.data.isNil:
    entry.clearSlotOp(entry.data, entity.idx)
  signature.excl(kind)

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
