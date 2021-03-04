//
//  RegisterNames.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

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

enum Register: Hashable {
    enum GeneralPurpose: Hashable {
        case ax
        case bx
        case cx
        case dx
        
        case bp
        case sp
        case si
        case di
    }
    
    enum Part: Hashable {
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
    
    case gpr(GeneralPurpose, Part)
    case segment(Segment)
}

extension Register : CustomStringConvertible {
    init?(_ int: ud_type) {
        if int == UD_NONE {
            return nil
        }

        switch int {
        
        /* 8 bit GPRs */
        case UD_R_AL:  self = .gpr(.ax, .low8)
        case UD_R_CL:  self = .gpr(.cx, .low8)
        case UD_R_DL:  self = .gpr(.dx, .low8)
        case UD_R_BL:  self = .gpr(.bx, .low8)
            
        case UD_R_AH:  self = .gpr(.ax, .high8)
        case UD_R_CH:  self = .gpr(.cx, .high8)
        case UD_R_DH:  self = .gpr(.dx, .high8)
        case UD_R_BH:  self = .gpr(.bx, .high8)
            
        case UD_R_SPL: self = .gpr(.sp, .low8)
        case UD_R_BPL: self = .gpr(.bp, .low8)
        case UD_R_SIL: self = .gpr(.si, .low8)
        case UD_R_DIL: self = .gpr(.di, .low8)
            
        /* 16 bit GPRs */
        case UD_R_AX:  self = .gpr(.ax, .low16)
        case UD_R_CX:  self = .gpr(.cx, .low16)
        case UD_R_DX:  self = .gpr(.dx, .low16)
        case UD_R_BX:  self = .gpr(.bx, .low16)
            
        case UD_R_SP:  self = .gpr(.sp, .low16)
        case UD_R_BP:  self = .gpr(.bp, .low16)
        case UD_R_SI:  self = .gpr(.si, .low16)
        case UD_R_DI:  self = .gpr(.di, .low16)

        /* 32 bit GPRs */
        case UD_R_EAX: self = .gpr(.ax, .low32)
        case UD_R_ECX: self = .gpr(.cx, .low32)
        case UD_R_EDX: self = .gpr(.dx, .low32)
        case UD_R_EBX: self = .gpr(.bx, .low32)
            
        case UD_R_ESP: self = .gpr(.sp, .low32)
        case UD_R_EBP: self = .gpr(.bp, .low32)
        case UD_R_ESI: self = .gpr(.si, .low32)
        case UD_R_EDI: self = .gpr(.di, .low32)

        /* segment registers */
        case UD_R_ES:  self = .segment(.es)
        case UD_R_CS:  self = .segment(.cs)
        case UD_R_SS:  self = .segment(.ss)
        case UD_R_DS:  self = .segment(.ds)
        case UD_R_FS:  self = .segment(.fs)
        case UD_R_GS:  self = .segment(.gs)
            
        default: fatalError()
        }
    }
    
    var description: String {
        switch self {
        case .gpr(let gp, let s):
            switch (gp, s) {
            case (.ax, .low8):    return "al"
            case (.cx, .low8):    return "cl"
            case (.dx, .low8):    return "dl"
            case (.bx, .low8):    return "bl"

            case (.ax, .high8):   return "ah"
            case (.cx, .high8):   return "ch"
            case (.dx, .high8):   return "dh"
            case (.bx, .high8):   return "bh"
                
            case (.sp, .low8):    return "spl"
            case (.bp, .low8):    return "bpl"
            case (.si, .low8):    return "sil"
            case (.di, .low8):    return "dil"
                
            case (.ax, .low16):   return "ax"
            case (.cx, .low16):   return "cx"
            case (.dx, .low16):   return "dx"
            case (.bx, .low16):   return "bx"
                
            case (.sp, .low16):   return "sp"
            case (.bp, .low16):   return "bp"
            case (.si, .low16):   return "si"
            case (.di, .low16):   return "di"
                
            case (.ax, .low32):   return "eax"
            case (.cx, .low32):   return "ecx"
            case (.dx, .low32):   return "edx"
            case (.bx, .low32):   return "ebx"
                
            case (.sp, .low32):   return "esp"
            case (.bp, .low32):   return "ebp"
            case (.si, .low32):   return "esi"
            case (.di, .low32):   return "edi"
                
            case (.di, .high8):   fallthrough
            case (.si, .high8):   fallthrough
            case (.bp, .high8):   fallthrough
            case (.sp, .high8):
                fatalError()
            }
            
        case .segment(let s):
            return "\(s)"
        }
    }

}
