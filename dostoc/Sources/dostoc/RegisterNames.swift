//
//  RegisterNames.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

typealias regs = RegisterName.Designations

enum Segment {
    case cs
    case ss
    case ds
    case es
    case fs
    case gs
    
    init?(_ int: ud_type) {
        if int == UD_NONE {
            return nil
        }
        
        switch int {
        case UD_R_CS: self = .cs
        case UD_R_SS: self = .ss
        case UD_R_DS: self = .ds
        case UD_R_ES: self = .es
        case UD_R_FS: self = .fs
        case UD_R_GS: self = .gs
        default: fatalError()
        }
    }
}


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
        
        case cs
        case ds
        case ss
        case es
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

extension RegisterName {
    init?(_ int: ud_type) {
        if int == UD_NONE {
            return nil
        }

        switch int {
        /* 8 bit GPRs */
        case UD_R_AL:  self = RegisterName(.ax, .low8)
        case UD_R_CL:  self = RegisterName(.cx, .low8)
        case UD_R_DL:  self = RegisterName(.dx, .low8)
        case UD_R_BL:  self = RegisterName(.bx, .low8)

        case UD_R_AH:  self = RegisterName(.ax, .high8)
        case UD_R_CH:  self = RegisterName(.cx, .high8)
        case UD_R_DH:  self = RegisterName(.dx, .high8)
        case UD_R_BH:  self = RegisterName(.bx, .high8)

        case UD_R_SPL: self = RegisterName(.sp, .low8)
        case UD_R_BPL: self = RegisterName(.bp, .low8)
        case UD_R_SIL: self = RegisterName(.si, .low8)
        case UD_R_DIL: self = RegisterName(.di, .low8)

        /* 16 bit GPRs */
        case UD_R_AX:  self = RegisterName(.ax, .low16)
        case UD_R_CX:  self = RegisterName(.cx, .low16)
        case UD_R_DX:  self = RegisterName(.dx, .low16)
        case UD_R_BX:  self = RegisterName(.bx, .low16)

        case UD_R_SP:  self = RegisterName(.sp, .low16)
        case UD_R_BP:  self = RegisterName(.bp, .low16)
        case UD_R_SI:  self = RegisterName(.si, .low16)
        case UD_R_DI:  self = RegisterName(.di, .low16)

        /* 32 bit GPRs */
        case UD_R_EAX: self = RegisterName(.ax, .low32)
        case UD_R_ECX: self = RegisterName(.cx, .low32)
        case UD_R_EDX: self = RegisterName(.dx, .low32)
        case UD_R_EBX: self = RegisterName(.bx, .low32)

        case UD_R_ESP: self = RegisterName(.sp, .low32)
        case UD_R_EBP: self = RegisterName(.bp, .low32)
        case UD_R_ESI: self = RegisterName(.si, .low32)
        case UD_R_EDI: self = RegisterName(.di, .low32)

        /* segment registers */
        case UD_R_ES:  self = RegisterName(.es, .low16)
        case UD_R_CS:  self = RegisterName(.cs, .low16)
        case UD_R_SS:  self = RegisterName(.ss, .low16)
        case UD_R_DS:  self = RegisterName(.ds, .low16)
        case UD_R_FS:  self = RegisterName(.fs, .low16)
        case UD_R_GS:  self = RegisterName(.gs, .low16)

        case UD_R_RIP: self = RegisterName(.ip, .low16)
            
        default: fatalError()
        }
    }
}
