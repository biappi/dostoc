//
//  Operand.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

extension ud_operand {
    var operandType: OperandType? {
        switch type {
        case UD_OP_REG:   return .reg
        case UD_OP_MEM:   return .mem
        case UD_OP_PTR:   return .ptr
        case UD_OP_IMM:   return .imm
        case UD_OP_JIMM:  return .jimm
        case UD_OP_CONST: return .const
        case UD_NONE:     return nil
        default: fatalError("\(type.rawValue)")
        }
    }
    
    var registerName: Register {
        Register(base)!
    }

    var operandSize: OperandSize {
        return OperandSize(Int(size))!
    }
    
    func uint64value(size: OperandSize) -> UInt64 {
        switch size {
        case .size_8:  return UInt64(lval.ubyte)
        case .size_16: return UInt64(lval.uword)
        case .size_32: return UInt64(lval.udword)
        case .size_64: return UInt64(lval.uqword)
        }
    }
    
    func int64value(size: OperandSize) -> Int64 {
        switch size {
        case .size_8:  return Int64(lval.sbyte)
        case .size_16: return Int64(lval.sword)
        case .size_32: return Int64(lval.sdword)
        case .size_64: return Int64(lval.sqword)
        }
    }

    var uint64value: UInt64 {
        return uint64value(size: operandSize)
    }

    var int64value: Int64 {
        return int64value(size: operandSize)
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

enum OperandSize: Int {
    case size_8  =  8
    case size_16 = 16
    case size_32 = 32
    case size_64 = 64
    
    init?(_ size: Int) {
        if size == 0 {
            return nil
        }
        
        switch size {
        case  8: self = .size_8
        case 16: self = .size_16
        default: fatalError("\(size)")
        }
    }
}

struct OperandCast: CustomStringConvertible {
    enum Size: Int {
        case byte  =   8
        case word  =  16
        case dword =  32
        case qword =  64
        case tword =  80
        case oword = 128
        case yword = 256

        var description: String {
            switch self {
            case .byte:  return "byte"
            case .word:  return "word"
            case .dword: return "dword"
            case .qword: return "qword"
            case .tword: return "tword"
            case .oword: return "oword"
            case .yword: return "yword"
            }
        }
    }
    
    let far: Bool
    let size: Size
    
    var description: String {
        let far = self.far ? "far " : ""
        return "\(far)\(size)"
    }
}

enum Addressing: CustomStringConvertible {
    struct IndexScale {
        enum Scale: Int {
            case byte  = 1
            case word  = 2
            case dword = 4
            case qword = 8
        }
        
        let index: Register
        let scale: Scale?
    }
    
    case displacement(segment: Segment?, displacement: UInt64)
    case base(segment: Segment?, base: Register)
    case baseOffset(segment: Segment?, base: Register, displacement: Int64)
    case baseIndex(segment: Segment?, base: Register, index: IndexScale)
    case baseIndexOffset(segment: Segment?, base: Register, index: IndexScale, displacement: Int64)
    
    init(_ insn: Instruction, _ op: ud_operand) {
        let segment = insn.prefixSegment
        let index   = Register(op.index)
        let base    = Register(op.base)
        let offSize = OperandSize(Int(op.offset))
        
        let scale   = op.scale != 0
            ? IndexScale.Scale(rawValue: Int(op.scale))
            : nil
        
        let indexScale = index.map {
            IndexScale(index: $0, scale: scale)
        }

        switch (base, indexScale, offSize) {
        case (.some(let base), .some(let index), .some(let size)):
            self = .baseIndexOffset(
                segment: segment,
                base: base,
                index: index,
                displacement: op.int64value(size: size)
            )
            
        case (.some(let base), .some(let index), nil):
            self = .baseIndex(
                segment: segment,
                base: base,
                index: index
            )
            
        case (.some(let base), nil, .some(let size)):
            self = .baseOffset(
                segment: segment,
                base: base,
                displacement: op.int64value(size: size)
            )

        case (.some(let base), nil, nil):
            self = .base(
                segment: segment,
                base: base
            )
            
        case (nil, nil, .some(let size)):
            self = .displacement(
                segment: segment,
                displacement: op.uint64value(size: size)
            )
            
        default:
            fatalError()
        }
    }
    
    var description: String {
        let sg   = { (s: Segment?) in s.map { "\($0) " } ?? "" }
        let hex  = { (x: UInt64)   in String(format: "%x", x) }
        let shex = { (x: Int64)    in String(format: "%x", x) }
        let sgn  = { (x: Int64)    in x > 0 ? "+" : "-" }
        
        switch self {
        case .displacement(let s, let d):
            return "[\(sg(s))\(hex(d))]"
            
        case .base(let s, let base):
            return "[\(sg(s))\(base)]"
            
        case .baseOffset(let s, let base, let displacement):
            return "[\(sg(s))\(base)\(sgn(displacement))\(shex(abs(displacement)))]"
            
        case .baseIndex(let s, let base, let index):
            return "[\(sg(s))\(base)+\(index)]"
            
        case .baseIndexOffset(let s, let base, let index, let displacement):
            return "[\(sg(s))\(base)+\(index)\(sgn(displacement))\(shex(abs(displacement)))]"
        }
    }
    
    var base: Register? {
        switch self {
        case .displacement   (_, _):              return nil
        case .base           (_, let base):       return base
        case .baseOffset     (_, let base, _):    return base
        case .baseIndex      (_, let base, _):    return base
        case .baseIndexOffset(_, let base, _, _): return base
        }
    }
    
    var index: Register? {
        switch self {
        case .displacement   (_, _):               return nil
        case .base           (_, _):               return nil
        case .baseOffset     (_, _, _):            return nil
        case .baseIndex      (_, _, let index):    return index.index
        case .baseIndexOffset(_, _, let index, _): return index.index
        }
    }
    
    static let stackPointer = Addressing.base(
        segment: .ss,
        base: .gpr(.sp, .low16)
    )
}
