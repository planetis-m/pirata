type
  EntityBits* = uint32
  Entity* = distinct EntityBits

const
  versionBits = 3
  versionMask = (EntityBits(1) shl versionBits) - 1
  indexBits = sizeof(EntityBits) * 8 - versionBits
  indexMask = (EntityBits(1) shl indexBits) - 1
  invalidIdx* = int(indexMask)
  maxEntities* = int(indexMask)

template idx*(entity: Entity): int =
  int(EntityBits(entity) and indexMask)

template version*(entity: Entity): EntityBits =
  EntityBits(entity) shr indexBits

template toEntity*(idx, ver: EntityBits): Entity =
  Entity(((ver and versionMask) shl indexBits) or (idx and indexMask))

proc `==`*(a, b: Entity): bool {.borrow.}

func `$`*(entity: Entity): string {.inline.} =
  "Entity(i: " & $entity.idx & ", v: " & $entity.version & ")"
