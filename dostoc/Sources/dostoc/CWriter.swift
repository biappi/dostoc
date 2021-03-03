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
    if let ex = expression as? SSABinaryOpExpression {
        return "\(rewrite(ex.lhs)) \(ex.op.rawValue) \(rewrite(ex.rhs))"
    }
    if let ex = expression as? SSAVariableExpression {
        return "\(ex.name.cName)"
    }
    if let ex = expression as? SSAConstExpression {
        return String(format: "0x%x", ex.value);
    }
    else {
        fatalError("\(expression)")
    }
}

func rewrite(_ statement: SSAStatement) -> String? {
    if let s = statement as? SSAVariableAssignmentStatement {
        return "\(s.name.cDeclaration) = \(rewrite(s.expression));"
    }
    if let s = statement as? SSAMemoryAddressResolver {
        switch s.addressing {
        case .base(_, _):
            guard let base = s.baseVariable else { break }
            return "\(s.name.cDeclaration) = \(base.cName);"

        case .baseOffset(_, _, let d):
            guard let base = s.baseVariable else { break }
            return "\(s.name.cDeclaration) = \(base.cName) \(d > 0 ? "+" : "-") \(String(format: "0x%x", abs(d)));"

        default:
            break
        }
    }
    if let s = statement as? SSAMemoryWriteStatement {
        return "memory_write(\(s.address.cName), \(rewrite(s.expression)));"
    }
    if let s = statement as? SSAMemoryReadStatement {
        return "\(s.name.cDeclaration) = memory_read(\(s.address.cName));"
    }
    if let s = statement as? SSAFlagsAssignmentStatement {
        return "\(s.name.cDeclaration) = flags(\(rewrite(s.expression)));"
    }
    if let s = statement as? SSAJccStatement {
        return "if (FLAGS(\"\(s.type)\", \(s.flags.cName)))\n\t\tgoto \(s.target.target);"
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
    if let s = statement as? SSAIntStatement {
        return "do_int21h(\(s.interrupt));"
    }
    if let _ = statement as? SSAPrologueStatement {
        return nil
    }
    if let _ = statement as? SSAEpilogueStatement {
        return nil
    }
    else {
        fatalError("\(statement)")
    }
}

func rewrite(ssaGraph: SSAGraph, deleted: Set<StatementIndex>)
{
    var phiVariables   = Set<String>()
    var phiAssignments = [UInt64 : [(String, String)]]()
    
    ssaGraph.forEachSSAStatementIndex { idx in
        guard
            !deleted.contains(idx),
            let s = ssaGraph.statementFor(idx) as? SSAPhiAssignmentStatement
            
        else {
            return
        }
    
        phiVariables.insert(s.name.cName)

        for (phiName, block) in zip(s.phiNames, ssaGraph.cfg.predecessors(of: idx.blockId)) {
            phiAssignments[block, default: []].append((s.name.cName, phiName))
        }
    }
 
    let printPhiAssignmentsForBlock = { (block: UInt64) in
        print()
        for phiVar in phiAssignments[block, default: []] {
            print("\t\(phiVar.0) = \(phiVar.1);")
        }
        print()
    }
    
    var prologues = [SSAPrologueStatement]()
    var epilogues = [SSAEpilogueStatement]()
    
    ssaGraph.forEachSSAStatementIndex { idx in
        let stmt = ssaGraph.statementFor(idx)
        
        if let p = stmt as? SSAPrologueStatement {
            prologues.append(p)
        }
        else if let e = stmt as? SSAEpilogueStatement {
            epilogues.append(e)
        }
    }
    
    let prologuesRegisters = Set(prologues.map { $0.register.cName })
    let epiloguesRegisters = Set(epilogues.map { $0.register.cName })
    
    let unboundVariables = prologuesRegisters.subtracting(epiloguesRegisters)
    
    print("#include <stdint.h>")
    print()
    print("uint16_t memory_read(int);")
    print("uint16_t memory_write(int, int);")
    print("void     do_int21h(int);")
    print()
    print("#define flags(x)    x")
    print("#define FLAGS(x, y) y")
    print()
    print("void sub_\(ssaGraph.cfg.start.hexString)()")
    print("{")
    
    for v in unboundVariables {
        print("\tuint16_t \(v) = 0;")
    }
    print()
    
    for phiVariable in phiVariables {
        print("\tuint16_t \(phiVariable);")
    }
    print()
 
    ssaGraph.cfg.visit {
        block in
        
        print("loc_\(block.start.hexString):;")
        
        var statementsToRewrite = [StatementIndex]()
        
        ssaGraph.forEachSSAStatementIndex(in: block.start) {
            if deleted.contains($0) { return }
            if case .phi = $0 { return }
            statementsToRewrite.append($0)
        }
        
        for (i, index) in statementsToRewrite.enumerated() {
            let lastStatement = (i == (statementsToRewrite.count - 1))
            let blockIsJump = ssaGraph.cfg.successors(of: block.start).count > 1
            
            if lastStatement && blockIsJump {
                printPhiAssignmentsForBlock(block.start)
            }
            
            let stmt = ssaGraph.statementFor(index)
            
            rewrite(stmt).map { print("\t\($0)") }

            if lastStatement && !blockIsJump {
                printPhiAssignmentsForBlock(block.start)
            }
        }
                
        print()
    }
    
    print("}")
    print()
    print("// pbpaste | cc -x c -")
    print()
}
