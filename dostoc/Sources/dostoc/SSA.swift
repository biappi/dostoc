//
//  SSA.swift
//  
//
//  Created by Antonio Malara on 27/02/21.
//

import Foundation
import udis86

struct SSAName: Hashable {
    enum Kind: Hashable {
        case string(String)
        case register(Register)
    }
        
    let kind: Kind
    var index: Int?
    
    init(name: String) {
        self.kind = .string(name)
        self.index = nil
    }

    init(register: Register) {
        self.kind = .register(register)
        self.index = nil
    }

    var name: String {
        switch kind {
        case .string(let a):
            return a
            
        case .register(let r):
            return r.description
        }
    }
        
    var dump: String {
        if let i = index { return "\(name)_\(i)" }
        else { return name }
    }
    
    mutating func reindex(name: String, index: Int) {
        if self.name == name {
            self.index = index
        }
    }
}

/* - */

protocol SSAStatement {
    var dump: String { get }
    
    var allVariables:        Set<SSAName> { get }
    var variablesDefined:    Set<SSAName> { get }
    var variablesReferenced: Set<SSAName> { get }
    
    mutating func renameDefinedVariables   (name: String, index: Int)
    mutating func renameReferencedVariables(name: String, index: Int)
}

extension SSAStatement {
    var allVariables: Set<SSAName> { variablesDefined.union(variablesReferenced) }
}

protocol SSANoVariablesDefined {
    var variablesDefined: Set<SSAName> { get }
    mutating func renameDefinedVariables(name: String, index: Int)
}

protocol SSANoVariablesReferenced {
    var variablesReferenced: Set<SSAName> { get }
    mutating func renameReferencedVariables(name: String, index: Int)
}

extension SSANoVariablesDefined {
    var variablesDefined: Set<SSAName> { [] }
    func renameDefinedVariables(name: String, index: Int) { }
}

extension SSANoVariablesReferenced {
    var variablesReferenced: Set<SSAName> { [] }
    func renameReferencedVariables(name: String, index: Int) { }
}

/* - */

struct SSAPhiAssignmentStatement: SSAStatement {
    var name: SSAName
    var phis: [Int?]
        
    var phiNames: [String] {
        return phis
            .map { "\(name.name)_\($0.map { "\($0)" } ?? "nil")"}
    }
    
    var dump: String {
        let d = phiNames.joined(separator: ", ")
        return "\(name.dump) = phi(\(d))"
    }
    
    var variablesDefined: Set<SSAName> {
        [name]
    }
    
    var variablesReferenced: Set<SSAName> {
        Set(
            phis.map {
                var n = name
                n.index = $0
                return n
            }
        )
    }
    
    func renameDefinedVariables(name: String, index: Int) {
        fatalError()
    }

    func renameReferencedVariables(name: String, index: Int) {
        fatalError()
    }
}

struct SSAVariableAssignmentStatement: SSAStatement {
    var name: SSAName
    var value: SSAName
    
    var dump: String { "\(name.dump) = \(value.dump)" }
    
    var variablesReferenced: Set<SSAName> { [value] }
    var variablesDefined:    Set<SSAName> { [name] }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        self.value.reindex(name: name, index: index)
    }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
}

struct SSAConstAssignmentStatement: SSAStatement, SSANoVariablesReferenced {
    var name: SSAName
    let const: Int
    
    var dump: String { "\(name.dump) = \(String(format: "%x", const))" }
    
    var variablesDefined:    Set<SSAName> { [name] }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
}

struct SSAFlagsAssignmentStatement: SSAStatement {
    static let flagsName = SSAName(name: "flags")
    
    var name = SSAFlagsAssignmentStatement.flagsName
    
    var value: SSAName
    
    init(value: SSAName) {
        self.value = value
    }
    
    var dump: String { "\(name.dump) = flags(\(value.dump))" }
    
    var variablesDefined: Set<SSAName> {
        [name]
    }
    
    var variablesReferenced: Set<SSAName> {
        [value]
    }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }

    mutating func renameReferencedVariables(name: String, index: Int) {
        self.value.reindex(name: name, index: index)
    }
}

struct SSABinaryOpStatement: SSAStatement {
    enum Operation: String {
        case sum  = "+"
        case diff = "-"
        case mul  = "*"
        case shr  = ">>"
        case shl  = "<<"
        case ror  = "(ror)"
        case rol  = "(rol)"

        case and  = "&"
        case or   = "|"
        case xor  = "^"
    }

    enum Operand {
        case reg(Register)
        case name
        case int(Int)
    }
    
    var result: SSAName
    let op: Operation
    
    let lhs: Operand
    let rhs: Operand
    
    var lhsName: SSAName?
    var rhsName: SSAName?
    
    init(result: SSAName, op: Operation, lhs: Register, rhs: Int) {
        self.result = result
        self.op = op
        self.lhs = .reg(lhs)
        self.lhsName = SSAName(register: lhs)
        self.rhs = .int(rhs)
        self.rhsName = nil
    }
    
    init(result: SSAName, op: Operation, lhs: Register, rhs: Register) {
        self.result = result
        self.op = op
        self.lhs = .reg(lhs)
        self.lhsName = SSAName(register: lhs)
        self.rhs = .reg(rhs)
        self.rhsName = SSAName(register: rhs)
    }
    
    init(result: SSAName, op: Operation, lhs: Register, rhs: SSAName) {
        self.result = result
        self.op = op
        self.lhs = .reg(lhs)
        self.lhsName = SSAName(register: lhs)
        self.rhs = .name
        self.rhsName = rhs
    }

    init(result: SSAName, op: Operation, lhs: SSAName, rhs: Int) {
        self.result = result
        self.op = op
        self.lhs = .name
        self.lhsName = lhs
        self.rhs = .int(rhs)
        self.rhsName = nil
    }

    init(result: SSAName, op: Operation, lhs: SSAName, rhs: Register) {
        self.result = result
        self.op = op
        self.lhs = .name
        self.lhsName = lhs
        self.rhs = .reg(rhs)
        self.rhsName = SSAName(register: rhs)
    }

    var dump: String {
        let lhsDump: String
        let rhsDump: String
        
        if case .int(let i) = lhs {
            lhsDump = String(format: "%x", i)
        }
        else {
            lhsDump = lhsName?.dump ?? "[DIOCAN]"
        }

        if case .int(let i) = rhs {
            rhsDump = String(format: "%x", i)
        }
        else {
            rhsDump = rhsName?.dump ?? "[DIOCAN]"
        }

        return "\(result.dump) = \(lhsDump) \(op.rawValue) \(rhsDump)"
    }
    
    var variablesDefined: Set<SSAName> { [result] }
        
    mutating func renameDefinedVariables(name: String, index: Int) {
        result.reindex(name: name, index: index)
    }
    
    var variablesReferenced: Set<SSAName> {
        var v = Set<SSAName>()
        _ = lhsName.map { v.insert($0) }
        _ = rhsName.map { v.insert($0) }
        return v
    }

    mutating func renameReferencedVariables(name: String, index: Int) {
        lhsName?.reindex(name: name, index: index)
        rhsName?.reindex(name: name, index: index)
    }

}

struct SSARegisterSplit16to8Statement: SSAStatement {
    var name: SSAName
    var other: SSAName

    var dump: String {
        return "\(name.dump) = conversion16to8(\(other.dump))"
    }
    
    var variablesDefined: Set<SSAName> { [name] }
    
    var variablesReferenced: Set<SSAName> { [other] }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        self.other.reindex(name: name, index: index)
    }
}

struct SSARegisterJoin8to16Statement: SSAStatement {
    var name: SSAName
    var otherLow: SSAName
    var otherHigh: SSAName

    var dump: String {
        return "\(name.dump) = conversion8to16(\(otherHigh.dump), \(otherLow.dump))"
    }
    
    var variablesDefined: Set<SSAName> { [name] }
    
    var variablesReferenced: Set<SSAName> { [otherLow, otherHigh] }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        self.otherLow.reindex(name: name, index: index)
        self.otherHigh.reindex(name: name, index: index)
    }
}

/* - */

struct SSALabel {
    let target: String
    
    init(pc: UInt64, offset: Int64) {
        let offset = UInt64(Int64(pc) + offset)
        target = String(format: "loc_%x", offset)
    }
    
    init(seg: UInt16, offset: UInt32) {
        let so = String(format: "%x:%x", seg, offset)
        target = so
    }
}

struct SSAJmpStatement: SSAStatement, SSANoVariablesDefined, SSANoVariablesReferenced {
    let target: SSALabel
    var dump: String { "jmp \(target.target)" }
}

struct SSAJccStatement: SSAStatement, SSANoVariablesDefined {
    let type: String
    let target: SSALabel
    var flags = SSAFlagsAssignmentStatement.flagsName
    
    var dump: String { "\(type)(\(flags.dump)) \(target.target)" }
    
    var variablesReferenced: Set<SSAName> { [flags] }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        flags.reindex(name: name, index: index)
    }
}

struct SSAIntStatement: SSAStatement, SSANoVariablesDefined, SSANoVariablesReferenced {
    let interrupt: Int
    var dump: String { String(format: "int(%x)", interrupt) }
}

struct SSACliStatement: SSAStatement, SSANoVariablesDefined, SSANoVariablesReferenced {
    var dump: String { "cli" }
}

struct SSAStiStatement: SSAStatement, SSANoVariablesDefined, SSANoVariablesReferenced {
    var dump: String { "sti" }
}

struct SSACallStatement: SSAStatement, SSANoVariablesDefined, SSANoVariablesReferenced {
    let target: SSALabel
    var dump: String { "call(\(target.target))" }
}

struct SSAOutStatement: SSAStatement, SSANoVariablesDefined {
    var port: SSAName
    var data: SSAName
    
    var dump: String { "out(\(port.dump), \(data.dump))" }
    
    var variablesReferenced: Set<SSAName> { [port, data] }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        port.reindex(name: name, index: index)
        data.reindex(name: name, index: index)
    }
}

/* - */

struct SSAMemoryAddressResolver: SSAStatement {
    var name: SSAName
    let addressing: Addressing
    
    var baseVariable:  SSAName?
    var indexVariable: SSAName?
    
    init(name: SSAName, addressing: Addressing) {
        self.name = name
        self.addressing = addressing
        
        self.baseVariable  = addressing.base.map  { SSAName(register: $0) }
        self.indexVariable = addressing.index.map { SSAName(register: $0) }
    }
    
    var variablesDefined: Set<SSAName> {
        [name]
    }

    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
    
    var variablesReferenced: Set<SSAName> {
        var v = Set<SSAName>()
        _ = baseVariable.map  { v.insert($0) }
        _ = indexVariable.map { v.insert($0) }
        return v
    }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        baseVariable?.reindex(name: name, index: index)
        indexVariable?.reindex(name: name, index: index)
    }
    
    var dump: String {
        let regs = "// \(baseVariable?.dump ?? "") \(indexVariable?.dump ?? "")"
        return "\(name.dump) = memory_address(\(addressing)) \(regs)"
    }
}

struct SSAMemoryReadStatement: SSAStatement {
    var name: SSAName
    var address: SSAName
        
    var variablesDefined: Set<SSAName> { [name] }
    var variablesReferenced: Set<SSAName> { [address] }

    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        self.address.reindex(name: name, index: index)
    }
    
    var dump: String {
        return "\(name.dump) = memory_read(\(address.dump))"
    }
    
    /*
    var dump: String {
        return "\(name.dump) = \(variant)(\(address.dump))"
    }
    
    var size: Size {
        name.size
    }
    
    var variant: String {
        switch size {
        case .byte:  return "memory_write_8"
        case .word:  return "memory_write_16"
        case .dword: return "memory_write_32"
        }
    }
     */
}

struct SSAMemoryWriteStatement: SSAStatement, SSANoVariablesDefined {
    var address: SSAName
    var value: SSAName

    var variablesReferenced: Set<SSAName> { [address, value] }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        address.reindex(name: name, index: index)
        value.reindex(name: name, index: index)
    }
    
    var dump: String {
        return "memory_write(\(address.dump)) = \(value.dump)"
    }
    
    /*
     var dump: String {
         return "\(variant)(\(address.dump)) = \(expression.dump)"
     }
     
     var size: Size {
         expression.size
     }
     
     var variant: String {
         switch size {
         case .byte:  return "memory_write_8"
         case .word:  return "memory_write_16"
         case .dword: return "memory_write_32"
         }
     }
     */
}

/* - */

struct SSAPrologueStatement: SSAStatement, SSANoVariablesReferenced {
    var register: SSAName
    var dump: String { "prologue(\(register.dump))" }

    var variablesDefined: Set<SSAName> {
        [register]
    }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        register.reindex(name: name, index: index)
    }
}

struct SSAEpilogueStatement: SSAStatement, SSANoVariablesDefined {
    var register: SSAName
    var dump: String { "epilogue(\(register.dump))" }

    var variablesReferenced: Set<SSAName> {
        [register]
    }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        register.reindex(name: name, index: index)
    }
}

struct SSAEndStatement: SSAStatement, SSANoVariablesDefined, SSANoVariablesReferenced {
    var dump: String { "end" }
}
