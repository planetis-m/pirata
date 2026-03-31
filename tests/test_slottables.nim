import ../src/pirata/[entities, slottables]

type
  ComponentKind = enum
    ckPosition
    ckVelocity
    ckSleeping

proc verifyBasicFlow() =
  var table = initSlotTableOfCap[ComponentKind](4)
  let first = table.incl({ckPosition})
  let second = table.incl({ckVelocity})
  let third = table.incl({ckPosition, ckSleeping})

  doAssert table.contains(first)
  doAssert table.contains(second)
  doAssert table.contains(third)
  doAssert table[first] == {ckPosition}
  doAssert table[third] == {ckPosition, ckSleeping}

  table.del(second)
  doAssert table.contains(first)
  doAssert not table.contains(second)
  doAssert table.contains(third)
  doAssert table[third] == {ckPosition, ckSleeping}

  let recycled = table.incl({ckSleeping})
  doAssert recycled.idx == second.idx
  doAssert recycled.version != second.version
  doAssert table[recycled] == {ckSleeping}

proc verifyMoveDoesNotLoseEntries() =
  block:
    var table = initSlotTableOfCap[ComponentKind](4)
    let tracked = table.incl({ckPosition, ckVelocity})
    var movedTable = move(table)
    doAssert movedTable.contains(tracked)
    doAssert movedTable[tracked] == {ckPosition, ckVelocity}

proc verifyIteration() =
  var table = initSlotTableOfCap[ComponentKind](4)
  discard table.incl({ckPosition})
  discard table.incl({ckVelocity})
  discard table.incl({ckPosition, ckSleeping})

  var count = 0
  var sawSleeping = false
  for entry in table.pairs:
    inc count
    if ckSleeping in entry.value:
      sawSleeping = true

  doAssert count == 3
  doAssert sawSleeping

proc main() =
  verifyBasicFlow()
  verifyMoveDoesNotLoseEntries()
  verifyIteration()

when isMainModule:
  main()
