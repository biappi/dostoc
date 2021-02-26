import Foundation
import udis86

let data = try! Data(contentsOf: URL(fileURLWithPath: "example.exe"))
let mz = ParseMZ(data: data)
let code = data.subdata(in: Int(mz.headerSize << 4) ..< data.count)

let addressOfMain = 0x10000
let addressOfSimplerFunction = UInt64((0x11c0 << 4) + 0x1c70)

let udis = UDis86(data: code, base: 0x10000)
let anals = XrefAnalisys(at: addressOfSimplerFunction, using: udis)

// print_disasm(xref: anals)
convert(anals: anals)

