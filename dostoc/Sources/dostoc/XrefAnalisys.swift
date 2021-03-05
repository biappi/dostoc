//
//  XrefAnalisys.swift
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
        
        nextAddresses.append(contentsOf: i.branches.asList)
        
        switch i.branches {
        case .jmp(.imm(let target)):
            xrefs[target, default: []].append(addr)
            
        case .jcc(_, .imm(let target)):
            xrefs[target, default: []].append(addr)

        default:
            break
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

