import std/[algorithm, monotimes, strutils, times]

import ../src/pirata
import ../src/pirata/slottables

type
  ComponentKind = enum
    ckPosition
    ckVelocity
    ckHealth
    ckSleeping
    ckMarker

  Position = object
    x, y: float32

  Velocity = object
    x, y: float32

  Health = object
    hp: int32

  BenchmarkResult = object
    name: string
    ops: int64
    checksum: int64
    minNsPerOp: float
    medianNsPerOp: float

const
  SlotCapacity = 4096
  WorldCapacity = 4096
  Runs = 9

var sinkChecksum {.global.}: int64

proc median(values: seq[float]): float =
  let mid = values.len shr 1
  if (values.len and 1) == 1:
    values[mid]
  else:
    (values[mid - 1] + values[mid]) * 0.5

template consume(value: SomeNumber) =
  sinkChecksum = sinkChecksum xor int64(value)

proc runBench(
  name: string;
  body: proc (): tuple[ops: int64, checksum: int64] {.nimcall.}
): BenchmarkResult =
  discard body()

  var samples: seq[float] = @[]
  var lastRun = body()

  for _ in 0 ..< Runs:
    let start = getMonoTime()
    lastRun = body()
    let elapsed = inNanoseconds(getMonoTime() - start)
    samples.add(elapsed.float / lastRun.ops.float)

  samples.sort()
  result = BenchmarkResult(
    name: name,
    ops: lastRun.ops,
    checksum: lastRun.checksum,
    minNsPerOp: samples[0],
    medianNsPerOp: median(samples)
  )

proc benchSlotTableLookup(): tuple[ops: int64, checksum: int64] =
  var table = initSlotTableOfCap[int32](SlotCapacity)
  var entities = newSeq[Entity](SlotCapacity)

  for i in 0 ..< SlotCapacity:
    entities[i] = table.incl(int32(i))

  var sum = 0'i64
  for _ in 0 ..< 256:
    for e in entities:
      if table.contains(e):
        sum += int64(table[e])

  consume(sum)
  (ops: int64(SlotCapacity) * 256, checksum: sum)

proc benchSpawnDestroyCycle(): tuple[ops: int64, checksum: int64] =
  var world = newPirata[ComponentKind](WorldCapacity)
  var entities = newSeq[Entity](WorldCapacity)
  var sum = 0'i64

  for round in 0 ..< 256:
    for i in 0 ..< WorldCapacity:
      let entity = world.spawn()
      entities[i] = entity
      sum += int64(entity.idx + round)

    for entity in entities:
      world.destroy(entity)

  consume(sum)
  (ops: int64(WorldCapacity) * 512, checksum: sum)

proc benchAddFetchRemovePayload(): tuple[ops: int64, checksum: int64] =
  var world = newPirata[ComponentKind](WorldCapacity)
  world.register(ckPosition, Position)
  var entities = newSeq[Entity](WorldCapacity)

  for i in 0 ..< WorldCapacity:
    entities[i] = world.spawn()

  var sum = 0'i64
  for round in 0 ..< 256:
    for i, entity in entities:
      world.add(entity, ckPosition, Position(x: float32(i + round), y: float32(round)))

    for entity in entities:
      var position = world.fetch(entity, ckPosition, Position)
      position.x += 1
      position.y += 2
      sum += int64(position.x) + int64(position.y)

    for entity in entities:
      world.remove(entity, ckPosition)

  consume(sum)
  (ops: int64(WorldCapacity) * 256 * 3, checksum: sum)

proc benchTagToggle(): tuple[ops: int64, checksum: int64] =
  var world = newPirata[ComponentKind](WorldCapacity)
  world.registerTag(ckMarker)
  var entities = newSeq[Entity](WorldCapacity)

  for i in 0 ..< WorldCapacity:
    entities[i] = world.spawn()

  var sum = 0'i64
  for round in 0 ..< 512:
    for entity in entities:
      world.add(entity, ckMarker)

    for entity in entities:
      if world.has(entity, ckMarker):
        inc sum

    for entity in entities:
      world.remove(entity, ckMarker)

    sum += round

  consume(sum)
  (ops: int64(WorldCapacity) * 512 * 3, checksum: sum)

proc initQueryWorld(
  entities: var seq[Entity];
  activeCount: var int
): PirataWorld[ComponentKind] =
  result = newPirata[ComponentKind](WorldCapacity)
  result.register(ckPosition, Position)
  result.register(ckVelocity, Velocity)
  result.register(ckHealth, Health)
  result.registerTag(ckSleeping)

  entities.setLen(WorldCapacity)
  activeCount = 0

  for i in 0 ..< WorldCapacity:
    let entity = result.spawn()
    entities[i] = entity
    result.add(entity, ckPosition, Position(x: float32(i), y: float32(i shr 1)))
    result.add(entity, ckHealth, Health(hp: int32(100 + (i and 31))))

    if (i and 1) == 0:
      result.add(entity, ckVelocity, Velocity(x: 0.5, y: 1.5))
      if (i and 7) == 0:
        result.add(entity, ckSleeping)
      else:
        inc activeCount

proc benchQueryUpdate(): tuple[ops: int64, checksum: int64] =
  var entities: seq[Entity] = @[]
  var activeCount = 0
  var world = initQueryWorld(entities, activeCount)
  var sum = 0'i64

  for _ in 0 ..< 512:
    for entity in world.query({ckPosition, ckVelocity}, {ckSleeping}):
      let velocity = world.fetch(entity, ckVelocity, Velocity)
      var position = world.fetch(entity, ckPosition, Position)
      position.x += velocity.x
      position.y += velocity.y
      sum += int64(position.x) + int64(position.y)

  consume(sum)
  (ops: int64(activeCount) * 512, checksum: sum)

proc benchDestroyPayloadDense(): tuple[ops: int64, checksum: int64] =
  var world = newPirata[ComponentKind](WorldCapacity)
  world.register(ckPosition, Position)
  world.register(ckVelocity, Velocity)
  world.register(ckHealth, Health)
  world.registerTag(ckSleeping)

  var entities = newSeq[Entity](WorldCapacity)
  var sum = 0'i64

  for i in 0 ..< WorldCapacity:
    let entity = world.spawn()
    entities[i] = entity
    world.add(entity, ckPosition, Position(x: float32(i), y: 0))
    world.add(entity, ckVelocity, Velocity(x: 1, y: 2))
    world.add(entity, ckHealth, Health(hp: int32(i)))
    if (i and 3) == 0:
      world.add(entity, ckSleeping)

  for entity in entities:
    let hp = world.fetch(entity, ckHealth, Health).hp
    world.destroy(entity)
    sum += hp

  consume(sum)
  (ops: int64(WorldCapacity), checksum: sum)

proc printResult(result: BenchmarkResult) =
  echo alignLeft(result.name, 28),
    align($result.ops, 12),
    align(formatFloat(result.minNsPerOp, ffDecimal, 2), 12),
    align(formatFloat(result.medianNsPerOp, ffDecimal, 2), 12),
    align($result.checksum, 16)

proc main() =
  let benches = [
    runBench("slot_table_lookup", benchSlotTableLookup),
    runBench("spawn_destroy_cycle", benchSpawnDestroyCycle),
    runBench("add_fetch_remove", benchAddFetchRemovePayload),
    runBench("tag_toggle", benchTagToggle),
    runBench("query_update", benchQueryUpdate),
    runBench("destroy_payload_dense", benchDestroyPayloadDense)
  ]

  echo "pirata microbench"
  echo "build: nim c -d:danger -r benchmarks/microbench.nim"
  echo ""
  echo alignLeft("benchmark", 28),
    align("ops", 12),
    align("min ns/op", 12),
    align("median", 12),
    align("checksum", 16)
  for bench in benches:
    printResult(bench)

  echo ""
  echo "sink checksum: ", sinkChecksum

when isMainModule:
  main()
