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
}

/* - */

protocol SSAExpression {
    var dump: String { get }
    var variables: Set<SSAName> { get }
    mutating func rename(name: String, index: Int)
}

struct SSARegExpression: SSAExpression {
    var name: SSAName
    var dump: String { name.dump }
    var variables: Set<SSAName> { Set([name]) }
    
    mutating func rename(name: String, index: Int) {
        if self.name.name == name {
            self.name.index = index
        }
    }
}

struct SSAMemoryExpression: SSAExpression {
    var name: SSAName
    var dump: String { "memory(\(name.dump))"}
    var variables: Set<SSAName> { Set([name]) }
    
    mutating func rename(name: String, index: Int) {
        if self.name.name == name {
            self.name.index = index
        }
    }
}

struct SSAMemoryLabelExpression: SSAExpression {
    var label: String
    var dump: String { "memory(\(label))"}

    var variables: Set<SSAName> { [] }
    mutating func rename(name: String, index: Int) { }
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
    var allVariables: Set<SSAName> { get }
    
    var lhsVariables: Set<SSAName> { get }
    var rhsVariables: Set<SSAName> { get }
    
    mutating func renameRHS(name: String, index: Int)
    mutating func renameLHS(name: String, index: Int)
}

extension SSAStatement {
    var allVariables: Set<SSAName> { lhsVariables.union(rhsVariables) }
    var lhsVariables: Set<SSAName> { Set() }
    var rhsVariables: Set<SSAName> { Set() }
    
    func renameRHS(name: String, index: Int) { }
    func renameLHS(name: String, index: Int) { }
}

struct SSAPhiAssignmentStatement: SSAStatement {
    let name: String
    var phis: [Int]
    
    var index = 0
    
    var dump: String {
        let d = phis
            .map { "\(name)_\($0)"}
            .joined(separator: ", ")
        
        return "\(name)_\(index) = phi(\(d))"
    }
    
    var lhsVariables: Set<SSAName> {
        Set([SSAName(name: name, index: index)])
    }
    
    var rhsVariables: Set<SSAName> {
        Set(phis.map { SSAName(name: name, index: $0)})
    }
    
    func renameRHS(name: String, index: Int) {
        fatalError()
    }
    
    func renameLHS(name: String, index: Int) {
        fatalError()
    }
}

struct SSAVariableAssignmentStatement: SSAStatement {
    var name: SSAName
    var expression: SSAExpression
    
    var dump: String { "\(name.dump) = \(expression.dump)" }
    
    var allVariables: Set<SSAName> {
        return Set([name]).union(expression.variables)
    }
    
    var rhsVariables: Set<SSAName> {
        expression.variables
    }
    
    var lhsVariables: Set<SSAName> {
        Set([name])
    }
    
    mutating func renameRHS(name: String, index: Int) {
        expression.rename(name: name, index: index)
    }
    
    mutating func renameLHS(name: String, index: Int) {
        if self.name.name == name {
            self.name.index = index
        }
    }
}

struct SSAMemoryAssignmentStatement: SSAStatement {
    var name: SSAName
    var expression: SSAExpression
    
    var dump: String { "memory(\(name.dump)) = \(expression.dump)" }
    
    var lhsVariables: Set<SSAName> {
        Set()
    }
    
    var rhsVariables: Set<SSAName> {
        expression.variables.union([name])
    }
    
    mutating func renameLHS(name: String, index: Int) {
        if self.name.name == name {
            self.name.index = index
        }
    }

    mutating func renameRHS(name: String, index: Int) {
        expression.rename(name: name, index: index)
    }
}

struct SSAFlagsAssignmentStatement: SSAStatement {
    var name: SSAName
    var expression: SSAExpression
    
    var dump: String { "\(name.dump) = flags(\(expression.dump))" }
    
    var lhsVariables: Set<SSAName> {
        Set()
    }
    
    var rhsVariables: Set<SSAName> {
        expression.variables.union([name])
    }
    
    mutating func renameLHS(name: String, index: Int) {
        if self.name.name == name {
            self.name.index = index
        }
    }

    mutating func renameRHS(name: String, index: Int) {
        expression.rename(name: name, index: index)
    }
}


struct SSASegmentedMemoryRegAssignmentStatement: SSAStatement {
    var segment: SSARegExpression?
    var address: SSARegExpression
    var expression: SSAExpression
    
    var dump: String {
        if let segment = segment {
            return "memory(\(segment.dump):\(address.dump)) = \(expression.dump)"
        }
        else {
            return "memory(\(address.dump)) = \(expression.dump)"
        }
    }
    
    var rhsVariables: Set<SSAName> {
        if let segment = segment {
            return expression
                .variables
                .union(segment.variables)
                .union(address.variables)
        }
        else {
            return expression
                .variables
                .union(address.variables)
        }
    }
    
    mutating func renameRHS(name: String, index: Int) {
        segment?.rename(name: name, index: index)
        address.rename(name: name, index: index)
        expression.rename(name: name, index: index)
    }
}

struct SSAIntStatement: SSAStatement {
    let interrupt: Int
    var dump: String { String(format: "int(%x)", interrupt) }
}

struct SSALabel {
    let target: String
}

struct SSAJccStatement: SSAStatement {
    let type: String
    let target: SSALabel
    var flags = SSARegExpression(name: SSAName(name: "flags"))
    
    var dump: String { "jmp(\(type)) \(target.target)" }
    
    var rhsVariables: Set<SSAName> { flags.variables }
    
    mutating func renameRHS(name: String, index: Int) {
        flags.rename(name: name, index: index)
    }

}

struct SSACallStatement: SSAStatement {
    let target: SSALabel
    var dump: String { "call(\(target.target))" }
}

struct SSAEndStatement: SSAStatement {
    var sp = SSARegExpression(name: RegisterName.Designations.sp.ssa)
    var ax = SSARegExpression(name: RegisterName.Designations.ax.ssa)
    
    var dump: String { "end(\(sp.dump), \(ax.dump))" }
    
    var rhsVariables: Set<SSAName> {
        Set([sp.name, ax.name])
    }
    
    mutating func renameRHS(name: String, index: Int) {
        sp.rename(name: name, index: index)
        ax.rename(name: name, index: index)
    }
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

