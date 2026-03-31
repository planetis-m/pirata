import ./entities

type
  Entry*[K: enum] = object
    e*: Entity
    value*: set[K]

  SlotTable*[K: enum] = object
    freeHead: int
    len: int
    capacity: int
    slots: ptr UncheckedArray[Entity]
    data: ptr UncheckedArray[Entry[K]]

template slotRef[K](table: SlotTable[K]; idx: int): Entity =
  table.slots[idx]

template entryRef[K](table: SlotTable[K]; idx: int): Entry[K] =
  table.data[idx]

proc allocBuf[T](count: int): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](allocShared(count * sizeof(T)))

proc `=destroy`*[K](table: var SlotTable[K]) =
  if not table.data.isNil:
    deallocShared(table.data)
  if not table.slots.isNil:
    deallocShared(table.slots)

proc `=wasMoved`*[K](table: var SlotTable[K]) =
  table.slots = nil
  table.data = nil

proc `=copy`*[K](dest: var SlotTable[K]; src: SlotTable[K]) {.error.}
proc `=dup`*[K](src: SlotTable[K]): SlotTable[K] {.error.}

proc initSlotTableOfCap*[K: enum](capacity: Natural): SlotTable[K] =
  let cap = capacity.int
  result = SlotTable[K](
    capacity: cap,
    freeHead: 0,
    slots: allocBuf[Entity](cap),
    data: allocBuf[Entry[K]](cap)
  )
  for idx in 0..<cap:
    let next = if idx + 1 < cap: idx + 1 else: invalidIdx
    result.slotRef(idx) = toEntity(EntityBits(next), 0)

proc lookupIndex*[K](table: SlotTable[K]; entity: Entity): int {.inline.} =
  let idx = entity.idx
  result = -1
  if idx < table.capacity and (entity.version and 1) != 0:
    let slot = table.slotRef(idx)
    if slot.version == entity.version:
      result = slot.idx

proc contains*[K](table: SlotTable[K]; entity: Entity): bool {.inline.} =
  table.lookupIndex(entity) >= 0

template valueAtIndex*[K](table: SlotTable[K]; idx: int): set[K] =
  table.entryRef(idx).value

template valueAtSlot*[K](table: SlotTable[K]; slotIdx: int): set[K] =
  table.entryRef(table.slotRef(slotIdx).idx).value

proc incl*[K](table: var SlotTable[K]; value: set[K]): Entity =
  let slotIdx = table.freeHead
  let liveVersion = table.slotRef(slotIdx).version or 1
  result = toEntity(EntityBits(slotIdx), liveVersion)
  table.freeHead = table.slotRef(slotIdx).idx
  table.entryRef(table.len) = Entry[K](e: result, value: value)
  table.slotRef(slotIdx) = toEntity(EntityBits(table.len), liveVersion)
  inc table.len

proc removeSlot[K](table: var SlotTable[K]; slotIdx: int) {.inline.} =
  let valueIdx = table.slotRef(slotIdx).idx
  let lastIdx = table.len - 1
  table.slotRef(slotIdx) = toEntity(EntityBits(table.freeHead), table.slotRef(slotIdx).version + 1)
  table.freeHead = slotIdx

  if valueIdx != lastIdx:
    table.entryRef(valueIdx) = table.entryRef(lastIdx)
    let movedSlotIdx = table.entryRef(valueIdx).e.idx
    table.slotRef(movedSlotIdx) = toEntity(EntityBits(valueIdx), table.slotRef(movedSlotIdx).version)

  dec table.len

proc delAt*[K](table: var SlotTable[K]; slotIdx: int) {.inline.} =
  table.removeSlot(slotIdx)

proc del*[K](table: var SlotTable[K]; entity: Entity) =
  if table.contains(entity):
    table.removeSlot(entity.idx)

proc `[]`*[K](table: SlotTable[K]; entity: Entity): lent set[K] =
  table.valueAtSlot(entity.idx)

proc `[]`*[K](table: var SlotTable[K]; entity: Entity): var set[K] =
  table.valueAtSlot(entity.idx)

iterator pairs*[K](table: SlotTable[K]): lent Entry[K] =
  for idx in 0..<table.len:
    yield table.entryRef(idx)
