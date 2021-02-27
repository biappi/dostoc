import Foundation
import udis86

let data = try! Data(contentsOf: URL(fileURLWithPath: "example.exe"))
let mz = ParseMZ(data: data)
let code = data.subdata(in: Int(mz.headerSize << 4) ..< data.count)

func RealToLinear(seg: UInt16, off: UInt16) -> UInt64 {
    return UInt64((UInt64(seg) << 4) + UInt64(off))
}

let addressOfMain            = RealToLinear(seg: 0x1000, off: 0x0000)
let addressOfSimplerFunction = RealToLinear(seg: 0x11c0, off: 0x1c70)
let addressOfBPFunction      = RealToLinear(seg: 0x1bdc, off: 0x07d6)

let udis = UDis86(data: code, base: RealToLinear(seg: 0x1000, off: 0x0000))
//let anals = XrefAnalisys(at: addressOfMain, using: udis)
//let anals = XrefAnalisys(at: addressOfSimplerFunction, using: udis)
let anals = XrefAnalisys(at: addressOfBPFunction, using: udis)

print_disasm(xref: anals)
// convert(anals: anals)

print()
print(" --- ")
print()

let cfg = CFGGraph(from: anals)
cfg.dump()

var c = Converter(cfg: cfg)
c.convert()
