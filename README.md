dostoc
======

An incomplete toy decompiler of DOS 16-bit executables written in Swift.

The idea of this project is to translate select parts of a dos executable
into C to aid with ports or exeprimentation of old software.

Overview
--------

The binary is first loaded, then, after ecompilation a CFG is recovered,
the x86 instructions are transated into SSA form to aid translation into
C.

Structure
---------

- `udis86` - a Swift package wrapping the disassmebler
  [udis86](https://github.com/vmt/udis86.git) to enable compilation with
  the SPM

- `dostoc` - the Swift package implementing this project




