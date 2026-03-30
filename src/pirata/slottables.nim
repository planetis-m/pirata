import typetraits

import ./entities

type
  Entry*[T] = object
    e*: Entity
    value*: T

  SlotTable*[T] = object
    freeHead: int
    len: int
    capacity: int
    slots: ptr UncheckedArray[Entity]
    data: ptr UncheckedArray[Entry[T]]

template slotAt[T](x: SlotTable[T]; i: int): var Entity =
  x.slots[i]

template dataAt[T](x: SlotTable[T]; i: int): var Entry[T] =
  x.data[i]

proc allocArray[T](count: int): ptr UncheckedArray[T] =
  let bytes = count * sizeof(T)
  when supportsCopyMem(T):
    result = cast[typeof(result)](allocShared(bytes))
  else:
    result = cast[typeof(result)](allocShared0(bytes))

proc freeArray[T](p: ptr UncheckedArray[T]) =
  deallocShared(p)

template forEachLiveIndex(x, i, body: untyped) =
  for i {.inject.} in 0..<x.len:
    body

proc `=trace`*[T](x: var SlotTable[T]; env: pointer) {.raises: [].}

proc `=destroy`*[T](x: var SlotTable[T]) {.raises: [].} =
  if not x.data.isNil:
    when not supportsCopyMem(Entry[T]):
      forEachLiveIndex(x, i):
        `=destroy`(x.dataAt(i))
    freeArray(x.data)
    x.data = nil
  if not x.slots.isNil:
    freeArray(x.slots)
    x.slots = nil
  x.len = 0
  x.capacity = 0
  x.freeHead = 0

proc `=trace`*[T](x: var SlotTable[T]; env: pointer) {.raises: [].} =
  when not supportsCopyMem(Entry[T]):
    if not x.data.isNil:
      forEachLiveIndex(x, i):
        `=trace`(x.dataAt(i), env)

proc `=copy`*[T](dest: var SlotTable[T]; src: SlotTable[T]) {.error.}
proc `=dup`*[T](src: SlotTable[T]): SlotTable[T] {.error.}

proc initSlotTableOfCap*[T](capacity: Natural): SlotTable[T] =
  result = default(SlotTable[T])
  result.capacity = capacity.int
  result.freeHead = 0
  result.slots = allocArray[Entity](result.capacity)
  result.data = allocArray[Entry[T]](result.capacity)
  for i in 0 ..< result.capacity:
    let next = if i + 1 < result.capacity: i + 1 else: result.capacity
    result.slotAt(i) = toEntity(next.EntityImpl, 0)

proc lookupIndex*[T](x: SlotTable[T]; e: Entity): int {.inline.} =
  let idx = e.idx
  if idx >= x.capacity or (e.version and 1) == 0:
    return -1

  let slot = x.slotAt(idx)
  if slot.version != e.version:
    return -1

  slot.idx

proc contains*[T](x: SlotTable[T]; e: Entity): bool {.inline.} =
  x.lookupIndex(e) >= 0

template valueAtIndex*[T](x: SlotTable[T]; i: int): untyped =
  x.dataAt(i).value

template valueAtSlot*[T](x: SlotTable[T]; slotIdx: int): untyped =
  x.dataAt(x.slotAt(slotIdx).idx).value

proc raiseRangeDefect() {.noinline, noreturn.} =
  raise newException(RangeDefect, "SlotTable number of elements overflow")

proc incl*[T](x: var SlotTable[T]; value: sink T): Entity =
  if x.len >= x.capacity:
    raiseRangeDefect()

  let slotIdx = x.freeHead
  template slot: untyped = x.slotAt(slotIdx)
  let occupiedVersion = slot.version or 1
  result = toEntity(slotIdx.EntityImpl, occupiedVersion)
  x.freeHead = slot.idx
  x.dataAt(x.len) = Entry[T](e: result, value: value)
  slot = toEntity(x.len.EntityImpl, occupiedVersion)
  inc x.len

proc delFromSlot[T](x: var SlotTable[T]; slotIdx: int) {.inline.} =
  template slot: untyped = x.slotAt(slotIdx)
  let valueIdx = slot.idx
  let lastIdx = x.len - 1
  slot = toEntity(x.freeHead.EntityImpl, slot.version + 1)
  x.freeHead = slotIdx

  if valueIdx != lastIdx:
    x.dataAt(valueIdx) = move(x.dataAt(lastIdx))
    let movedSlotIdx = x.dataAt(valueIdx).e.idx
    x.slotAt(movedSlotIdx) = toEntity(valueIdx.EntityImpl, x.slotAt(movedSlotIdx).version)
  else:
    when not supportsCopyMem(Entry[T]):
      `=destroy`(x.dataAt(lastIdx))

  dec x.len

proc delAt*[T](x: var SlotTable[T]; slotIdx: int) {.inline.} =
  x.delFromSlot(slotIdx)

proc del*[T](x: var SlotTable[T]; e: Entity) =
  if x.contains(e):
    x.delFromSlot(e.idx)

template getValue(x, e) =
  let dataIdx = x.lookupIndex(e)
  if dataIdx < 0:
    raise newException(KeyError, "Entity not in SlotTable")
  result = x.valueAtIndex(dataIdx)

proc `[]`*[T](x: SlotTable[T]; e: Entity): lent T =
  getValue(x, e)

proc `[]`*[T](x: var SlotTable[T]; e: Entity): var T =
  getValue(x, e)

iterator pairs*[T](x: SlotTable[T]): lent Entry[T] =
  for i in 0..<x.len:
    yield x.dataAt(i)
