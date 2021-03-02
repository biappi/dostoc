//
//  RegisterNames.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

typealias regs = RegisterName.Designations

struct RegisterName: CustomStringConvertible {
    
    enum Designations {
        case ax
        case bx
        case cx
        case dx
        case bp
        case sp
        case si
        case di
        case ip
        case es
        case cs
        case ss
        case ds
        case fs
        case gs
    }
    
    enum Parts {
        case low8
        case high8
        case low16
        case low32
        
        var byteSize: Int {
            switch self {
            case .low8:  return 1
            case .high8: return 1
            case .low16: return 2
            case .low32: return 4
            }
        }
    }
    
    let designation: Designations
    let part: Parts
    
    init(_ designation: Designations, _ part: Parts) {
        self.designation = designation
        self.part = part
    }
    
    var description: String {
        return "reg(\(designation) \(part))"
    }
}

extension ud_operand {
    var registerName: RegisterName {
        switch base {
        /* 8 bit GPRs */
        case UD_R_AL:  return RegisterName(.ax, .low8)
        case UD_R_CL:  return RegisterName(.cx, .low8)
        case UD_R_DL:  return RegisterName(.dx, .low8)
        case UD_R_BL:  return RegisterName(.bx, .low8)

        case UD_R_AH:  return RegisterName(.ax, .high8)
        case UD_R_CH:  return RegisterName(.cx, .high8)
        case UD_R_DH:  return RegisterName(.dx, .high8)
        case UD_R_BH:  return RegisterName(.bx, .high8)

        case UD_R_SPL: return RegisterName(.sp, .low8)
        case UD_R_BPL: return RegisterName(.bp, .low8)
        case UD_R_SIL: return RegisterName(.si, .low8)
        case UD_R_DIL: return RegisterName(.di, .low8)

        /* 16 bit GPRs */
        case UD_R_AX:  return RegisterName(.ax, .low16)
        case UD_R_CX:  return RegisterName(.cx, .low16)
        case UD_R_DX:  return RegisterName(.dx, .low16)
        case UD_R_BX:  return RegisterName(.bx, .low16)

        case UD_R_SP:  return RegisterName(.sp, .low16)
        case UD_R_BP:  return RegisterName(.bp, .low16)
        case UD_R_SI:  return RegisterName(.si, .low16)
        case UD_R_DI:  return RegisterName(.di, .low16)

        /* 32 bit GPRs */
        case UD_R_EAX: return RegisterName(.ax, .low32)
        case UD_R_ECX: return RegisterName(.cx, .low32)
        case UD_R_EDX: return RegisterName(.dx, .low32)
        case UD_R_EBX: return RegisterName(.bx, .low32)

        case UD_R_ESP: return RegisterName(.sp, .low32)
        case UD_R_EBP: return RegisterName(.bp, .low32)
        case UD_R_ESI: return RegisterName(.si, .low32)
        case UD_R_EDI: return RegisterName(.di, .low32)

        /* segment registers */
        case UD_R_ES:  return RegisterName(.es, .low16)
        case UD_R_CS:  return RegisterName(.cs, .low16)
        case UD_R_SS:  return RegisterName(.ss, .low16)
        case UD_R_DS:  return RegisterName(.ds, .low16)
        case UD_R_FS:  return RegisterName(.fs, .low16)
        case UD_R_GS:  return RegisterName(.gs, .low16)

        case UD_R_RIP: return RegisterName(.ip, .low16)
            
        default: fatalError()
        }
    }
}
