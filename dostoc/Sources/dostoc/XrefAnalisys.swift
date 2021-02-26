//
//  File.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation

struct InstructionXrefs {
    let start: UInt64
    let insns: [UInt64 : Instruction]
    let xrefs: [UInt64 : [UInt64]]
}

func XrefAnalisys(at address: UInt64, using dis: UDis86) -> InstructionXrefs {
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
        start: address,
        insns: insns,
        xrefs: xrefs
    )
}

func print_disasm(xref anals: InstructionXrefs) {
    for addr in anals.insns.keys.sorted() {
        let i = anals.insns[addr]!
        
        if let xref = anals.xrefs[addr] {
            let x = xref.map { String(format: "%x", $0) }.joined(separator: ", ")
            print(String(format: "%08x", i.offset))
            print(String(format: "%08x    loc_%x\t\t\t\t\txrefs: \(x)", i.offset, i.offset))
        }
        
        print(String(format: "%08x        %@", i.offset, i.asm))
    }
}
