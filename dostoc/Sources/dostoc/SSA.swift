//
//  SSA.swift
//  
//
//  Created by Antonio Malara on 27/02/21.
//

import Foundation
import udis86

struct SSAName {
    let name:  String
    let index: Int
    
    var dump: String { "\(name)_\(index)" }
}

/* - */

protocol SSAVariable {
    var dump: String { get }
}

struct SSARegVariable: SSAVariable {
    let name: SSAName
    
    var dump: String { name.dump }
}

struct SSAMemoryVariable: SSAVariable {
    let name: SSAName
    
    var dump: String { "memory(\(name.dump))"}
}

/* - */

protocol SSAExpression {
    var dump: String { get }
}

struct SSARegExpression: SSAExpression {
    let name: SSAName
    
    var dump: String { name.dump }
}

struct SSAMemoryExpression: SSAExpression {
    let name: SSAName
    
    var dump: String { "memory(\(name.dump))"}
}

struct SSAConstExpression: SSAExpression {
    let value: Int
    
    var dump: String { String(format: "%x", value) }
}

struct SSASumExpression: SSAExpression {
    let lhs: SSAExpression
    let rhs: SSAExpression
    
    var dump: String { "\(lhs.dump) + \(rhs.dump)" }
}

struct SSADiffExpression: SSAExpression {
    let lhs: SSAExpression
    let rhs: SSAExpression
    
    var dump: String { "\(lhs.dump) - \(rhs.dump)" }
}

/* - */

protocol SSAStatement {
    var dump: String { get }
}

struct SSAAssignmentStatement: SSAStatement {
    let variable: SSAVariable
    let expression: SSAExpression
    
    var dump: String { "\(variable.dump) = \(expression.dump)" }
}

struct SSAIntStatement: SSAStatement {
    let interrupt: Int
    
    var dump: String { String(format: "int(%x)", interrupt) }
}

struct SSALabel {
    let target: String
}

struct SSAJmpStatement: SSAStatement {
    let type: String
    let target: SSALabel
    
    var dump: String { "jmp(\(type)) \(target.target)" }
}

struct SSAEndStatement: SSAStatement {
    var dump: String { "end" }
}

/* - */

extension SSAAssignmentStatement {
    init(assign e: SSAExpression, to v: SSAVariable) {
        self.init(variable: v, expression: e)
    }
}
