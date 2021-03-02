//
//  Flow.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

enum FlowType {
    case seq
    case invd
    case call
    case jmp
    case jcc
    case ret
    case hlt
    
    init(for instruction: Instruction) {
        let invalid: [ud_mnemonic_code] = [
            UD_Iinvd
        ]

        let call: [ud_mnemonic_code] = [
            UD_Isyscall,
            UD_Icall,
            UD_Ivmcall,
            UD_Ivmmcall,
        ]

        let ret: [ud_mnemonic_code] = [
            UD_Isysret,
            UD_Iiretw,
            UD_Iiretd,
            UD_Iiretq,
            UD_Iret,
            UD_Iretf,
        ]
        
        let jmp: [ud_mnemonic_code] = [
            UD_Ijmp,
        ]
        
        let jcc: [ud_mnemonic_code] = [
            UD_Ijo,
            UD_Ijno,
            UD_Ijb,
            UD_Ijae,
            UD_Ijz,
            UD_Ijnz,
            UD_Ijbe,
            UD_Ija,
            UD_Ijs,
            UD_Ijns,
            UD_Ijp,
            UD_Ijnp,
            UD_Ijl,
            UD_Ijge,
            UD_Ijle,
            UD_Ijg,
            UD_Ijcxz,
            UD_Ijecxz,
            UD_Ijrcxz,
            UD_Iloopne,
            UD_Iloope,
            UD_Iloop,
        ]
        
        let hlt: [ud_mnemonic_code] = [
            UD_Ihlt,
        ]

        if invalid.contains(instruction.mnemonic) {
            self = .invd
        }
        else if call.contains(instruction.mnemonic) {
            self = .call
        }
        else if ret.contains(instruction.mnemonic) {
            self = .ret
        }
        else if jmp.contains(instruction.mnemonic) {
            self = .jmp
        }
        else if jcc.contains(instruction.mnemonic) {
            self = .jcc
        }
        else if hlt.contains(instruction.mnemonic) {
            self = .hlt
        }
        else {
            self = .seq
        }
    }
}

enum InstructionBranches {
    case none
    case jmp(target: UInt64)
    case jcc(next: UInt64, target: UInt64)
    case call(next: UInt64, target: UInt64)
    case seq(next: UInt64)
    
    var string: String {
        switch self {
        case .none:
            return "none"
            
        case .jmp(target: let t):
            return "jmp  (\(t.hexString))"
            
        case .jcc(next: let n, target: let t):
            return "jcc  (\(n.hexString), \(t.hexString))"
            
        case .call(next: let n, target: let t):
            return "call (\(n.hexString), \(t.hexString))"
            
        case .seq(next: let n):
            return "seq  (\(n.hexString))"
        }
    }
    
    var asList: [UInt64] {
        switch self {
        case .none:                             return []
        case .jmp (             target: let t): return [t]
        case .jcc (next: let n, target: let t): return [n, t]
        case .call(next: let n, target: _    ): return [n]
        case .seq (next: let n               ): return [n]
        }
    }
}

extension Instruction {
    var flowType: FlowType {
        FlowType(for: self)
    }
    
    var branches: InstructionBranches {
        let next_target = { () -> UInt64 in
            
            switch operands.0.type {
            case UD_OP_JIMM: fallthrough
            case UD_OP_IMM:
                switch operands.0.size {
                case 8:
                    let val = operands.0.lval.sbyte
                    
                    if val > 0 {
                        return pc + UInt64(val)
                    }
                    else {
                        return pc - UInt64(-val)
                    }

                case 16:
                    let val = operands.0.lval.sword
                    
                    if val > 0 {
                        return pc + UInt64(val)
                    }
                    else {
                        return pc - UInt64(-val)
                    }
                    
                default:
                    assertionFailure()
                }
                
            case UD_OP_PTR:
                return UInt64(operands.0.lval.ptr.seg << 4) + UInt64(operands.0.lval.ptr.off)
                
            case UD_OP_MEM:
                assertionFailure("mem")
                
            default:
                assertionFailure("AIEE")
            }
            
            return 0
        }
        
        switch flowType {
        case .seq:  return .seq  (next: pc)
        case .invd: return .none
        case .call: return .call (next: pc, target: next_target())
        case .jmp:  return .jmp  (          target: next_target())
        case .jcc:  return .jcc  (next: pc, target: next_target())
        case .ret:  return .none
        case .hlt:  return .none
        }
    }
}
