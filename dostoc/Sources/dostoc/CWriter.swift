//
//  CWriter.swift
//  
//
//  Created by Antonio Malara on 02/03/21.
//

import Foundation

extension SSAName {
    var cType: String { "uint16_t" }
    var cName: String { dump }
    var cDeclaration: String { "\(cType) \(cName)" }
}

func rewrite(_ expression: SSAExpression) -> String {
    if let ex = expression as? SSAMemoryExpression {
        return "memory_read(\(ex.name.cName))"
    }
    if let ex = expression as? SSAMemoryLabelExpression {
        return "memory_read(0x\(ex.label))"
    }
    if let ex = expression as? SSABinaryOpExpression {
        return "\(rewrite(ex.lhs)) \(ex.op.rawValue) \(rewrite(ex.rhs))"
    }
    if let ex = expression as? SSARegExpression {
        return "\(ex.name.cName)"
    }
    if let ex = expression as? SSAConstExpression {
        return String(format: "%x", ex.value);
    }
    else {
        fatalError("\(expression)")
    }
}

func rewrite(_ statement: SSAStatement) -> String {
    if let s = statement as? SSAVariableAssignmentStatement {
        return "\(s.name.cDeclaration) = \(rewrite(s.expression));"
    }
    if let s = statement as? SSAMemoryAssignmentStatement {
        return "memory_write(\(s.name.cName), \(rewrite(s.expression)));"
    }
    if let s = statement as? SSASegmentedMemoryRegAssignmentStatement {
        let x: String
        if let segment = s.segment {
            x = "\(segment.dump):\(s.address.dump)"
        }
        else {
            x = "\(s.address.dump)"
        }

        return "memory_write(\(x), \(rewrite(s.expression)));"
    }
    if let s = statement as? SSAFlagsAssignmentStatement {
        return "\(s.name.cDeclaration) = flags(\(rewrite(s.expression)));"
    }
    if let s = statement as? SSAJccStatement {
        return "if (FLAGS_\(s.type.uppercased())(\(s.flags.name.cName)))\n\t\tgoto \(s.target.target);"
    }
    if let s = statement as? SSACallStatement {
        return "sub_\(s.target.target)();"
    }
    if let _ = statement as? SSAEndStatement {
        return "return;"
    }
    if let s = statement as? SSAPhiAssignmentStatement {
        return "// phis \(s.name)"
    }
    else {
        fatalError("\(statement)")
    }
}

func rewrite(ssaGraph: SSAGraph, deleted: Set<StatementIndex>) {
    print("void sub_\(ssaGraph.cfg.start.hexString)()")
    print("{")

    cfg.visit {
        block in
        
        print("loc_\(block.start.hexString):")
        
        ssaGraph.forEachSSAStatementIndex(in: block.start) {
            let statement = ssaGraph.statementFor($0)
            
            if deleted.contains($0) {
                return
            }
            
            if (statement as? SSAPhiAssignmentStatement) != nil {
                return
            }
            print("\t\(rewrite(statement))")
        }

        print()
    }
    
    print("}")
}
