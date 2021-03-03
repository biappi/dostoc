//
//  SSA.swift
//  
//
//  Created by Antonio Malara on 27/02/21.
//

import Foundation
import udis86

struct SSAName: Hashable {
    let name:  String
    var index: Int?
    
    init(name: String) {
        self.name = name
        self.index = nil
    }
    
    init(name: String, index: Int?) {
        self.name = name
        self.index = index
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

protocol SSAExpression {
    var dump: String { get }
    var variables: Set<SSAName> { get }
    mutating func rename(name: String, index: Int)
}

struct SSAVariableExpression: SSAExpression {
    var name: SSAName
    var dump: String { name.dump }
    var variables: Set<SSAName> { Set([name]) }
    
    mutating func rename(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
}

struct SSAConstExpression: SSAExpression {
    let value: Int
    var dump: String { String(format: "%x", value) }
    var variables: Set<SSAName> { Set() }
    
    mutating func rename(name: String, index: Int) { }
}

struct SSABinaryOpExpression: SSAExpression {
    enum Operation: String {
        case sum  = "+"
        case diff = "-"
        case mul  = "*"
        case shr  = ">>"
        case shl  = "<<"
    }
    
    let op:  Operation
    var lhs: SSAExpression
    var rhs: SSAExpression
    
    var dump: String {
        "\(lhs.dump) \(op.rawValue) \(rhs.dump)"
    }
    
    var variables: Set<SSAName> {
        return lhs.variables.union(rhs.variables)
    }
    
    mutating func rename(name: String, index: Int) {
        lhs.rename(name: name, index: index)
        rhs.rename(name: name, index: index)
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
    let name: String
    var phis: [Int]
    
    var index = 0
    
    var myName: String {
        "\(name)_\(index)"
    }
    
    var phiNames: [String] {
        return phis
            .map { "\(name)_\($0)"}
    }
    
    var dump: String {
        let d = phiNames.joined(separator: ", ")
        return "\(myName) = phi(\(d))"
    }
    
    var variablesDefined: Set<SSAName> {
        Set([SSAName(name: name, index: index)])
    }
    
    var variablesReferenced: Set<SSAName> {
        Set(phis.map { SSAName(name: name, index: $0)})
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
    var expression: SSAExpression
    
    var dump: String { "\(name.dump) = \(expression.dump)" }
    
    var variablesReferenced: Set<SSAName> { expression.variables }
    var variablesDefined:    Set<SSAName> { [name] }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        expression.rename(name: name, index: index)
    }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }
}

struct SSAFlagsAssignmentStatement: SSAStatement {
    var name = SSAName(name: "flags")
    var expression: SSAExpression
    
    var dump: String { "\(name.dump) = flags(\(expression.dump))" }
    
    var variablesDefined: Set<SSAName> {
        [name]
    }
    
    var variablesReferenced: Set<SSAName> {
        expression.variables.union([name])
    }
    
    mutating func renameDefinedVariables(name: String, index: Int) {
        self.name.reindex(name: name, index: index)
    }

    mutating func renameReferencedVariables(name: String, index: Int) {
        expression.rename(name: name, index: index)
    }
}

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

struct SSAJccStatement: SSAStatement, SSANoVariablesDefined {
    let type: String
    let target: SSALabel
    var flags = SSAName(name: "flags")
    
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

struct SSACallStatement: SSAStatement, SSANoVariablesDefined, SSANoVariablesReferenced {
    let target: SSALabel
    var dump: String { "call(\(target.target))" }
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
        
        self.baseVariable  = addressing.base.map  { $0.designation.ssa }
        self.indexVariable = addressing.index.map { $0.designation.ssa }
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
}

struct SSAMemoryWriteStatement: SSAStatement, SSANoVariablesDefined {
    var address: SSAName
    var expression: SSAExpression

    var variablesReferenced: Set<SSAName> { expression.variables.union([address]) }
    
    mutating func renameReferencedVariables(name: String, index: Int) {
        address.reindex(name: name, index: index)
        expression.rename(name: name, index: index)
    }
    
    var dump: String {
        return "memory_write(\(address.dump)) = \(expression.dump)"
    }
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

/* - */

func SSASumExpression(lhs: SSAExpression, rhs: SSAExpression) -> SSABinaryOpExpression {
    return SSABinaryOpExpression(op: .sum, lhs: lhs, rhs: rhs)
}

func SSADiffExpression(lhs: SSAExpression, rhs: SSAExpression) -> SSABinaryOpExpression {
    return SSABinaryOpExpression(op: .diff, lhs: lhs, rhs: rhs)
}

func SSAMulExpression(lhs: SSAExpression, rhs: SSAExpression) -> SSABinaryOpExpression {
    return SSABinaryOpExpression(op: .mul, lhs: lhs, rhs: rhs)
}

func SSAShiftRight(lhs: SSAExpression, rhs: SSAExpression) -> SSABinaryOpExpression {
    return SSABinaryOpExpression(op: .shr, lhs: lhs, rhs: rhs)
}

