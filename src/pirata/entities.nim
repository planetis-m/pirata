type
  Entity* = distinct EntityImpl
  EntityImpl* = uint16

const
  versionBits = 3
  versionMask = (EntityImpl(1) shl versionBits) - 1
  indexBits = sizeof(EntityImpl) * 8 - versionBits
  indexMask = (EntityImpl(1) shl indexBits) - 1
  maxEntities* = 8191

template idx*(e: Entity): int =
  int(e.EntityImpl and indexMask)

template version*(e: Entity): EntityImpl =
  e.EntityImpl shr indexBits

template toEntity*(idx, v: EntityImpl): Entity =
  Entity(((v and versionMask) shl indexBits) or (idx and indexMask))

proc `==`*(a, b: Entity): bool {.borrow.}

func `$`*(e: Entity): string {.inline.} =
  "Entity(i: " & $e.idx & ", v: " & $e.version & ")"
