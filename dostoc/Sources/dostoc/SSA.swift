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
    let index: Int?
    
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
}

struct SSARegExpression: SSAExpression {
    let name: SSAName
    
    var dump: String { name.dump }
    
    var variables: Set<SSAName> {
        Set([name])
    }
}

struct SSAMemoryExpression: SSAExpression {
    let name: SSAName
    
    var dump: String { "memory(\(name.dump))"}
    
    var variables: Set<SSAName> {
        Set([name])
    }
}

struct SSAConstExpression: SSAExpression {
    let value: Int
    
    var dump: String { String(format: "%x", value) }
    
    var variables: Set<SSAName> {
        Set()
    }
}

struct SSABinaryOpExpression: SSAExpression {
    enum Operation: String {
        case sum  = "+"
        case diff = "-"
        case mul  = "*"
        case shr  = ">>"
    }
    
    let op:  Operation
    let lhs: SSAExpression
    let rhs: SSAExpression
    
    var dump: String { "\(lhs.dump) \(op.rawValue) \(rhs.dump)" }
    
    var variables: Set<SSAName> {
        return lhs.variables.union(rhs.variables)
    }
}

/* - */

protocol SSAStatement {
    var dump: String { get }
    var variables: Set<SSAName> { get }
}

struct SSAPhiAssignmentStatement: SSAStatement {
    let name: String
    let phis: [(Int, Int)]
    
    var dump: String {
        let d = phis
            .map { "\(name)_\($0.1) : \($0.0)"}
            .joined(separator: ", ")
        
        return "phi(\(d))"
    }
    
    var variables: Set<SSAName> {
        return Set()
    }
}


struct SSAVariableAssignmentStatement: SSAStatement {
    let name: SSAName
    let expression: SSAExpression
    
    var dump: String { "\(name.dump) = \(expression.dump)" }
    
    var variables: Set<SSAName> {
        return Set([name]).union(expression.variables)
    }
}

struct SSAMemoryAssignmentStatement: SSAStatement {
    let name: SSAName
    let expression: SSAExpression
    
    var dump: String { "memory(\(name.dump)) = \(expression.dump)" }

    var variables: Set<SSAName> {
        return Set([name]).union(expression.variables)
    }
}

struct SSASegmentedMemoryAssignmentStatement: SSAStatement {
    let address: String
    let expression: SSAExpression
    
    var dump: String { "memory(\(address)) = \(expression.dump)" }
    
    var variables: Set<SSAName> {
        return expression.variables
    }
}

struct SSAIntStatement: SSAStatement {
    let interrupt: Int
    
    var dump: String { String(format: "int(%x)", interrupt) }
    
    var variables: Set<SSAName> {
        return Set()
    }
}

struct SSALabel {
    let target: String
}

struct SSAJmpStatement: SSAStatement {
    let type: String
    let target: SSALabel
    
    var dump: String { "jmp(\(type)) \(target.target)" }
    
    var variables: Set<SSAName> {
        return Set()
    }

}

struct SSACallStatement: SSAStatement {
    let target: SSALabel
    
    var dump: String { "call(\(target.target))" }
    
    var variables: Set<SSAName> {
        return Set()
    }
}

struct SSAEndStatement: SSAStatement {
    var dump: String { "end" }
    
    var variables: Set<SSAName> {
        return Set()
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

