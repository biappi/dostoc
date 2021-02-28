//
//  Operand.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

extension ud_operand {
    
    var operandType: OperandType {
        switch type {
        case UD_OP_REG:   return .reg
        case UD_OP_MEM:   return .mem
        case UD_OP_PTR:   return .ptr
        case UD_OP_IMM:   return .imm
        case UD_OP_JIMM:  return .jimm
        case UD_OP_CONST: return .const
        default: fatalError("\(type.rawValue)")
        }
    }
    
    var operandSize: OperandSize {
        switch size {
        case  8: return .size_8
        case 16: return .size_16
        default: fatalError("\(size)")
        }
    }

    var uint64value: UInt64 {
        switch operandSize {
        case .size_8:  return UInt64(lval.ubyte)
        case .size_16: return UInt64(lval.uword)
        case .size_32: return UInt64(lval.udword)
        case .size_64: return UInt64(lval.uqword)
        }
    }
    
    var int64value: Int64 {
        switch operandSize {
        case .size_8:  return Int64(lval.sbyte)
        case .size_16: return Int64(lval.sword)
        case .size_32: return Int64(lval.sdword)
        case .size_64: return Int64(lval.sqword)
        }
    }
}

enum OperandType {
    case reg
    case mem
    case ptr
    case imm
    case jimm
    case const
}

enum OperandSize {
    case size_8
    case size_16
    case size_32
    case size_64
    
    var ctype: String {
        switch self {
        case .size_8:  return "uint8_t "
        case .size_16: return "uint16_t"
        case .size_32: return "uint32_t"
        case .size_64: return "uint64_t"
        }
    }
    
    var readMemoryFunctionName: String {
        switch self {
        case .size_8:  return "c86_memory_read_8  "
        case .size_16: return "c86_memory_read_16 "
        case .size_32: return "c86_memory_read_32 "
        case .size_64: return "c86_memory_read_64 "
        }

    }
}

struct MemoryOperand {
    let base: RegisterName
    let offset: Int64
    
    init(_ operand: ud_operand) {
        assert(operand.index == UD_NONE)
        assert((operand.base != UD_NONE) || (operand.index != UD_NONE))

        base = operand.registerName
        
        switch operand.offset {
        case  8: offset = Int64(operand.lval.sbyte)
        case 16: offset = Int64(operand.lval.sword)
        case 32: offset = Int64(operand.lval.sdword)
        default: fatalError()
        }
    }
}
