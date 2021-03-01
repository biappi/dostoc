import Foundation
import udis86

let data = try! Data(contentsOf: URL(fileURLWithPath: "example.exe"))
let mz = ParseMZ(data: data)
let code = data.subdata(in: Int(mz.headerSize << 4) ..< data.count)

func RealToLinear(seg: UInt16, off: UInt16) -> UInt64 {
    return UInt64((UInt64(seg) << 4) + UInt64(off))
}

enum Examples {
    static let main            = RealToLinear(seg: 0x1000, off: 0x0000)
    static let simpleFunction  = RealToLinear(seg: 0x11c0, off: 0x1c70)
    static let bpFunction      = RealToLinear(seg: 0x1bdc, off: 0x07d6)
    static let noLoops         = RealToLinear(seg: 0x1dc6, off: 0x2f92)
    static let twoLoops        = RealToLinear(seg: 0x1bdc, off: 0x0b25)
}

let udis = UDis86(data: code, base: RealToLinear(seg: 0x1000, off: 0x0000))
//let anals = XrefAnalisys(at: Examples.main, using: udis)
//let anals = XrefAnalisys(at: Examples.simpleFunction, using: udis)
let anals = XrefAnalisys(at: Examples.twoLoops, using: udis)

//print_disasm(xref: anals)
//
//print()
//print(" --- ")
//print()

let cfg = CFGGraph(from: anals)
cfg.dump()

let doms = dominators(graph: cfg)
print(doms)

let f = dominanceFrontier(graph: cfg, doms: doms)
print(f)

var c = Converter(cfg: cfg)
c.convert()

struct ExampleGraph : Graph {
    var start = 1
    var nodes = [1, 2, 3, 4, 5, 6]
    
    func predecessors(of node: Int) -> [Int] {
        return [
            1: [],
            2: [1, 5],
            3: [2],
            4: [2],
            5: [3, 4],
            6: [2]
        ][node]!
    }
    
    func successors(of node: Int) -> [Int] {
        return [
            1: [2],
            2: [3, 4, 6],
            3: [5],
            4: [5],
            5: [2],
            6: []
        ][node]!
    }
}

let DOM = dominators(graph: ExampleGraph())
print(DOM)
