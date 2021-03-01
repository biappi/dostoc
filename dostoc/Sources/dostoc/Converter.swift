//
//  Converter.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

struct Assigner {
    let name: String
    
    var i = 0
    var gaveInitial = false
    
    mutating func giveMe() -> String {
        let n = "\(name)_\(i)"
        i += 1
        return n
    }
    
    mutating func last() -> String {
        if i == 0 {
            let n = "\(name)_init"
            gaveInitial = true
            return n
        }
        else {
            return "\(name)_\(i - 1)"
        }
    }
}

func labelName(addr: UInt64) -> String {
    return String(format: "loc_%x", addr)
}

func funcName(addr: UInt64) -> String {
    return String(format: "func_%x", addr)
}

func operandValue(operand: ud_operand, instruction: Instruction) -> String {
    switch operand.operandType {
    case .reg:
        fatalError()
        
    case .mem:
        assert(instruction.prefixSegment == nil)
        assert(operand.base == UD_NONE)
        assert(operand.index == UD_NONE)

        assert(operand.operandSize != .size_8) // udis86/syn.c:186
        
        let name = "\(operand.operandSize.readMemoryFunctionName)"
        let val  = operand.uint64value

        return String(format: "\(name)(0x%x)", val);
        
    case .ptr:
        fatalError()
        
    case .imm:
        let val  = operand.uint64value
        return String(format: "0x%x", val);

    case .jimm:
        fatalError()
        
    case .const:
        fatalError()
        
    case .none:
        fatalError()
    }
}

func convert(anals: InstructionXrefs) {
    var operandsAssigner = Assigner(name: "op")
    var zflagAssigner    = Assigner(name: "zflag")
    var tempAssigner     = Assigner(name: "temp")

    print("void \(funcName(addr: anals.start)) {")
    
    for addr in anals.insns.keys.sorted() {
        let i = anals.insns[addr]!
        
        print(String(format: "    // %08x        %@\n", i.offset, i.asm))
        
        if anals.xrefs[addr] != nil {
            print("\(labelName(addr: addr)):")
        }
        
        switch i.mnemonic {
        case UD_Icmp:
            let op0type = i.operands.0.operandSize.ctype
            let op0name = operandsAssigner.giveMe()
            let op0val  = operandValue(operand: i.operands.0, instruction: i)
            
            print("    \(op0type) \(op0name) = \(op0val);")
            
            let op1type = i.operands.1.operandSize.ctype
            let op1name = operandsAssigner.giveMe()
            let op1val  = operandValue(operand: i.operands.1, instruction: i)
            
            print("    \(op1type) \(op1name) = \(op1val);")
            print()
            
            let temp_name = tempAssigner.giveMe()
            print("    \(op0type) \(temp_name) = \(op0name) - \(op1name);")
            
            let zflag_name = zflagAssigner.giveMe()
            print("    uint8_t  \(zflag_name) = (\(temp_name) == 0);")
            break
            
        case UD_Ijnz:
            assert(i.operands.0.operandType == .jimm)
            
            print("    if (!\(zflagAssigner.last()))")
            
            let loc = UInt64(Int64(i.pc) + i.operands.0.int64value)
            let label = labelName(addr: loc)
            print("        goto \(label);")
            
        case UD_Icall:
            assert(i.operands.0.operandType == .ptr)
            
            let ptr = i.operands.0.lval.ptr
            let addr = UInt64(ptr.seg << 4) + UInt64(ptr.off)
            let name = funcName(addr: addr)
            print("    \(name)();")
            
        case UD_Iretf:
            print("    return;")
            
        default:
            fatalError()
        }
        
        print()
    }
    
    print("}\n")
}

