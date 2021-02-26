import Foundation
import udis86

typealias MZHeader = (
    signature:         UInt16,
    extraBytes:        UInt16,
    pages:             UInt16,
    relocationItems:   UInt16,
    headerSize:        UInt16,
    minimumAllocation: UInt16,
    maximumAllocation: UInt16,
    initialSS:         UInt16,
    initialSP:         UInt16,
    checksum:          UInt16,
    initialIP:         UInt16,
    initialCS:         UInt16,
    relocationTable:   UInt16,
    overlay:           UInt16
)

let data = try! Data(contentsOf: URL(fileURLWithPath: "example.exe"))

let mz = data.withUnsafeBytes {
    $0.bindMemory(to: MZHeader.self).first!
}

let code = data.subdata(in: Int(mz.headerSize << 4) ..< data.count)

struct InstructionXrefs {
    let insns: [UInt64 : Instruction]
    let xrefs: [UInt64 : [UInt64]]
}

func XrefAnalisys(at address: UInt64) -> InstructionXrefs {
    var nextAddresses = [address]
    var insns = [UInt64 : Instruction]()
    var xrefs = [UInt64 : [UInt64]]()
    
    while nextAddresses.count > 0 {
        let addr = nextAddresses.removeFirst()
        
        if insns[addr] != nil {
            continue
        }
        
        let i = dis.disassemble(addr: addr)!
        insns[addr] = i
        
        switch i.branches {
        case .none:
            break
            
        case .jmp(target: let target):
            nextAddresses.append(target)
            xrefs[target, default: []].append(addr)
            
        case .jcc(next: let next, target: let target):
            nextAddresses.append(next)
            nextAddresses.append(target)
            xrefs[target, default: []].append(addr)
            
        case .call(next: let next, target: _):
            nextAddresses.append(next)
            
        case .seq(next: let next):
            nextAddresses.append(next)
        }
    }
    
    return InstructionXrefs(
        insns: insns,
        xrefs: xrefs
    )
}


let addressOfMain = 0x10000
let addressOfSimplerFunction = UInt64((0x11c0 << 4) + 0x1c70)

var dis = UDis86(data: code, base: 0x10000)

let anals = XrefAnalisys(at: addressOfSimplerFunction)

for addr in anals.insns.keys.sorted() {
    let i = anals.insns[addr]!
    
    if let xref = anals.xrefs[addr] {
        let x = xref.map { String(format: "%x", $0) }.joined(separator: ", ")
        print(String(format: "%08x", i.offset))
        print(String(format: "%08x    loc_%x\t\t\t\t\txrefs: \(x)", i.offset, i.offset))
    }
    
    print(String(format: "%08x        %@", i.offset, i.asm))
}
