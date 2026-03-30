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

template slotRef[T](table: SlotTable[T]; idx: int): var Entity =
  table.slots[idx]

template entryRef[T](table: SlotTable[T]; idx: int): var Entry[T] =
  table.data[idx]

proc allocBuf[T](count: int): ptr UncheckedArray[T] =
  let bytes = count * sizeof(T)
  when supportsCopyMem(T):
    result = cast[typeof(result)](allocShared(bytes))
  else:
    result = cast[typeof(result)](allocShared0(bytes))

proc freeBuf[T](buf: ptr UncheckedArray[T]) =
  deallocShared(buf)

proc `=trace`*[T](table: var SlotTable[T]; env: pointer) {.raises: [].}

proc `=destroy`*[T](table: var SlotTable[T]) {.raises: [].} =
  if not table.data.isNil:
    when not supportsCopyMem(Entry[T]):
      for idx in 0..<table.len:
        `=destroy`(table.entryRef(idx))
    freeBuf(table.data)
    table.data = nil
  if not table.slots.isNil:
    freeBuf(table.slots)
    table.slots = nil
  table.len = 0
  table.capacity = 0
  table.freeHead = 0

proc `=trace`*[T](table: var SlotTable[T]; env: pointer) {.raises: [].} =
  when not supportsCopyMem(Entry[T]):
    if not table.data.isNil:
      for idx in 0..<table.len:
        `=trace`(table.entryRef(idx), env)

proc `=copy`*[T](dest: var SlotTable[T]; src: SlotTable[T]) {.error.}
proc `=dup`*[T](src: SlotTable[T]): SlotTable[T] {.error.}

proc initSlotTableOfCap*[T](capacity: Natural): SlotTable[T] =
  result = default(SlotTable[T])
  result.capacity = capacity.int
  result.freeHead = 0
  result.slots = allocBuf[Entity](result.capacity)
  result.data = allocBuf[Entry[T]](result.capacity)
  for idx in 0..<result.capacity:
    let next = if idx + 1 < result.capacity: idx + 1 else: result.capacity
    result.slotRef(idx) = toEntity(next.EntityImpl, 0)

proc lookupIndex*[T](table: SlotTable[T]; entity: Entity): int {.inline.} =
  let idx = entity.idx
  if idx >= table.capacity or (entity.version and 1) == 0:
    return -1

  let slot = table.slotRef(idx)
  if slot.version != entity.version:
    return -1

  slot.idx

proc contains*[T](table: SlotTable[T]; entity: Entity): bool {.inline.} =
  table.lookupIndex(entity) >= 0

template valueAtIndex*[T](table: SlotTable[T]; idx: int): untyped =
  table.entryRef(idx).value

template valueAtSlot*[T](table: SlotTable[T]; slotIdx: int): untyped =
  table.entryRef(table.slotRef(slotIdx).idx).value

proc incl*[T](table: var SlotTable[T]; value: sink T): Entity =
  let slotIdx = table.freeHead
  template slot: untyped = table.slotRef(slotIdx)
  let liveVersion = slot.version or 1
  result = toEntity(slotIdx.EntityImpl, liveVersion)
  table.freeHead = slot.idx
  table.entryRef(table.len) = Entry[T](e: result, value: value)
  slot = toEntity(table.len.EntityImpl, liveVersion)
  inc table.len

proc removeSlot[T](table: var SlotTable[T]; slotIdx: int) {.inline.} =
  template slot: untyped = table.slotRef(slotIdx)
  let valueIdx = slot.idx
  let lastIdx = table.len - 1
  slot = toEntity(table.freeHead.EntityImpl, slot.version + 1)
  table.freeHead = slotIdx

  if valueIdx != lastIdx:
    table.entryRef(valueIdx) = move(table.entryRef(lastIdx))
    let movedSlotIdx = table.entryRef(valueIdx).e.idx
    table.slotRef(movedSlotIdx) =
      toEntity(valueIdx.EntityImpl, table.slotRef(movedSlotIdx).version)
  else:
    when not supportsCopyMem(Entry[T]):
      `=destroy`(table.entryRef(lastIdx))

  dec table.len

proc delAt*[T](table: var SlotTable[T]; slotIdx: int) {.inline.} =
  table.removeSlot(slotIdx)

proc del*[T](table: var SlotTable[T]; entity: Entity) =
  if table.contains(entity):
    table.removeSlot(entity.idx)

proc `[]`*[T](table: SlotTable[T]; entity: Entity): lent T =
  table.valueAtSlot(entity.idx)

proc `[]`*[T](table: var SlotTable[T]; entity: Entity): var T =
  table.valueAtSlot(entity.idx)

iterator pairs*[T](table: SlotTable[T]): lent Entry[T] =
  for idx in 0..<table.len:
    yield table.entryRef(idx)
