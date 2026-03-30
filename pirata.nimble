# Package
version     = "0.1.0"
author      = "Antonis Geralis"
description = "A compact ECS for Nim with enum-driven components, tags, and flat queries."
license     = "MIT"
srcDir      = "src"

# Dependencies
requires "nim >= 1.6.0"

task benchmark, "Builds and runs the micro-benchmark suite":
  exec("nim c -d:danger -r benchmarks/microbench.nim")
