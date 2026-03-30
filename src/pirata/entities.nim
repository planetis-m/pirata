type
  Entity* = distinct EntityImpl
  EntityImpl* = uint16

const
  versionBits = 3
  versionMask = (EntityImpl(1) shl versionBits) - 1
  indexBits = sizeof(EntityImpl) * 8 - versionBits
  indexMask = (EntityImpl(1) shl indexBits) - 1
  maxEntities* = 8191

func idx*(entity: Entity): int {.inline.} =
  int(EntityImpl(entity) and indexMask)

func version*(entity: Entity): EntityImpl {.inline.} =
  EntityImpl(entity) shr indexBits

func toEntity*(idx, ver: EntityImpl): Entity {.inline.} =
  Entity(((ver and versionMask) shl indexBits) or (idx and indexMask))

proc `==`*(a, b: Entity): bool {.borrow.}

func `$`*(entity: Entity): string {.inline.} =
  "Entity(i: " & $entity.idx & ", v: " & $entity.version & ")"
