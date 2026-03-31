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

template slotRef[T](table: SlotTable[T]; idx: int): Entity =
  table.slots[idx]

template entryRef[T](table: SlotTable[T]; idx: int): Entry[T] =
  table.data[idx]

proc allocBuf[T](count: int): ptr UncheckedArray[T] =
  let bytes = count * sizeof(T)
  when supportsCopyMem(T):
    result = cast[typeof(result)](allocShared(bytes))
  else:
    result = cast[typeof(result)](allocShared0(bytes))

template cloneTable(dest, src: untyped) =
  dest.freeHead = src.freeHead
  dest.len = src.len
  dest.capacity = src.capacity
  dest.slots = nil
  dest.data = nil

  if not src.slots.isNil:
    dest.slots = allocBuf[Entity](src.capacity)
    copyMem(dest.slots, src.slots, src.capacity * sizeof(Entity))

  if not src.data.isNil:
    let bytes = src.capacity * sizeof(src.data[][0])
    when supportsCopyMem(typeof(src.data[][0])):
      dest.data = cast[typeof(dest.data)](allocShared(bytes))
      copyMem(dest.data, src.data, src.len * sizeof(src.data[][0]))
    else:
      dest.data = cast[typeof(dest.data)](allocShared0(bytes))
      for idx in 0..<src.len:
        dest.entryRef(idx) = `=dup`(src.entryRef(idx))

proc `=destroy`*[T](table: var SlotTable[T]) =
  if not table.data.isNil:
    when not supportsCopyMem(Entry[T]):
      for idx in 0..<table.len:
        `=destroy`(table.entryRef(idx))
    deallocShared(table.data)
  if not table.slots.isNil:
    deallocShared(table.slots)

proc `=wasMoved`*[T](table: var SlotTable[T]) =
  table.slots = nil
  table.data = nil

proc `=copy`*[T](dest: var SlotTable[T]; src: SlotTable[T]) =
  if dest.data != src.data or dest.slots != src.slots:
    `=destroy`(dest)
    cloneTable(dest, src)

proc `=dup`*[T](src: SlotTable[T]): SlotTable[T] {.nodestroy.} =
  cloneTable(result, src)

proc `=sink`*[T](dest: var SlotTable[T]; src: SlotTable[T]) =
  `=destroy`(dest)
  dest.freeHead = src.freeHead
  dest.len = src.len
  dest.capacity = src.capacity
  dest.slots = src.slots
  dest.data = src.data

proc initSlotTableOfCap*[T](capacity: Natural): SlotTable[T] =
  let cap = capacity.int
  result = SlotTable[T](
    capacity: cap,
    freeHead: 0,
    slots: allocBuf[Entity](cap),
    data: allocBuf[Entry[T]](cap)
  )
  for idx in 0..<cap:
    let next = if idx + 1 < cap: idx + 1 else: invalidIdx
    result.slotRef(idx) = toEntity(EntityBits(next), 0)

proc lookupIndex*[T](table: SlotTable[T]; entity: Entity): int {.inline.} =
  let idx = entity.idx
  result = -1
  if idx < table.capacity and (entity.version and 1) != 0:
    let slot = table.slotRef(idx)
    if slot.version == entity.version:
      result = slot.idx

proc contains*[T](table: SlotTable[T]; entity: Entity): bool {.inline.} =
  table.lookupIndex(entity) >= 0

template valueAtIndex*[T](table: SlotTable[T]; idx: int): T =
  table.entryRef(idx).value

template valueAtSlot*[T](table: SlotTable[T]; slotIdx: int): T =
  table.entryRef(table.slotRef(slotIdx).idx).value

proc incl*[T](table: var SlotTable[T]; value: sink T): Entity =
  let slotIdx = table.freeHead
  let liveVersion = table.slotRef(slotIdx).version or 1
  result = toEntity(EntityBits(slotIdx), liveVersion)
  table.freeHead = table.slotRef(slotIdx).idx
  table.entryRef(table.len) = Entry[T](e: result, value: value)
  table.slotRef(slotIdx) = toEntity(EntityBits(table.len), liveVersion)
  inc table.len

proc removeSlot[T](table: var SlotTable[T]; slotIdx: int) {.inline.} =
  let valueIdx = table.slotRef(slotIdx).idx
  let lastIdx = table.len - 1
  table.slotRef(slotIdx) = toEntity(EntityBits(table.freeHead), table.slotRef(slotIdx).version + 1)
  table.freeHead = slotIdx

  if valueIdx != lastIdx:
    table.entryRef(valueIdx) = move(table.entryRef(lastIdx))
    let movedSlotIdx = table.entryRef(valueIdx).e.idx
    table.slotRef(movedSlotIdx) = toEntity(EntityBits(valueIdx), table.slotRef(movedSlotIdx).version)
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
