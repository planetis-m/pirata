import algorithm

import ../src/pirata

type
  ComponentKind = enum
    ckPosition
    ckVelocity
    ckTag
    ckPayload

  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Payload = object
    text: string

proc expectPirataError(body: proc ()) =
  var raised = false
  try:
    body()
  except PirataError:
    raised = true
  doAssert raised, "Expected a PirataError"

proc main() =
  var world = newPirata[ComponentKind](16)
  world.register(ckPosition, Position)
  world.register(ckVelocity, Velocity)
  world.registerTag(ckTag)
  world.register(ckPayload, Payload)

  let first = world.spawn()
  doAssert world.contains(first)

  world.add(first, ckPosition, Position(x: 1, y: 2))
  doAssert world.has(first, ckPosition)
  doAssert world.fetch(first, ckPosition, Position).x == 1
  doAssert world.fetch(first, ckPosition, Position).y == 2

  world.add(first, ckPayload, Payload(text: "booty"))
  doAssert world.fetch(first, ckPayload, Payload).text == "booty"

  expectPirataError(proc () =
    discard world.fetch(first, ckVelocity, Velocity)
  )

  let moving = world.spawn()
  world.add(moving, ckPosition, Position(x: 5, y: 8))
  world.add(moving, ckVelocity, Velocity(x: 1, y: 1))

  let tagged = world.spawn()
  world.add(tagged, ckPosition, Position(x: 9, y: 9))
  world.add(tagged, ckTag)
  doAssert world.contains(tagged)

  var queried: seq[int] = @[]
  for entity in world.query(mask(ckPosition), mask(ckTag)):
    queried.add(entity.idx)
  queried.sort()
  doAssert queried == @[first.idx, moving.idx]

  world.remove(moving, ckVelocity)
  doAssert not world.has(moving, ckVelocity)

  world.destroy(first)
  doAssert not world.contains(first)

  expectPirataError(proc () =
    discard world.fetch(first, ckPosition, Position)
  )

  let recycled = world.spawn()
  doAssert recycled.idx == first.idx
  doAssert recycled.version != first.version
  doAssert world.contains(recycled)

  world.add(recycled, ckPayload, Payload(text: "fresh"))
  doAssert world.fetch(recycled, ckPayload, Payload).text == "fresh"

  expectPirataError(proc () =
    world.add(recycled, ckPosition, Position(x: 3, y: 4))
    world.add(recycled, ckPosition, Position(x: 5, y: 6))
  )

when isMainModule:
  main()
