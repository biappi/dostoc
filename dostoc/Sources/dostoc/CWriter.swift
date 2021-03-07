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

func rewrite(_ statement: SSAStatement) -> String? {
    if let s = statement as? SSAVariableAssignmentStatement {
        return "\(s.name.cDeclaration) = \(s.value.cName);"
    }
    if let s = statement as? SSAMemoryAddressResolver {
        switch s.addressing {
        case .base(_, _):
            guard let base = s.baseVariable else { break }
            return "\(s.name.cDeclaration) = \(base.cName);"

        case .baseOffset(_, _, let d):
            guard let base = s.baseVariable else { break }
            return "\(s.name.cDeclaration) = \(base.cName) \(d > 0 ? "+" : "-") \(String(format: "0x%x", abs(d)));"

        case .displacement(_, let d):
            return "\(s.name.cDeclaration) = 0x\(String(format: "%x", d));"
            
        default:
            fatalError()
        }
    }
    if let s = statement as? SSAMemoryWriteStatement {
        return "memory_write(\(s.address.cName), \(s.value.cName));"
    }
    if let s = statement as? SSAMemoryReadStatement {
        return "\(s.name.cDeclaration) = memory_read(\(s.address.cName));"
    }
    if let s = statement as? SSAFlagsAssignmentStatement {
        return "\(s.name.cDeclaration) = flags(\(s.value.cName));"
    }
    if let s = statement as? SSAJmpStatement {
        return "goto \(s.target.target);"
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
    if let s = statement as? SSABinaryOpStatement {
        let l: String
        let r: String

        let op: String
        
        if case .int(let i) = s.lhs { l = String(format: "0x%x", i) }
        else { l = s.lhsName?.cName ?? ""}
        
        if case .int(let i) = s.rhs { r = String(format: "0x%x", i) }
        else { r = s.rhsName?.cName ?? ""}

        switch s.op {
        
        case .ror:
            // WRONG and size
            op = "(\(l) >> \(r)) | (\(l) << (sizeof(\(l)-\(r))))"
            
        case .rol:
            // check and size
            op = "(\(l) >> \(r)) | (\(l) << (sizeof(\(l)-\(r))))"
            
        default:
            op = "\(l) \(s.op.rawValue) \(r)"
        }
        
        return "\(s.result.cDeclaration) = \(op);"
    }
    if let s = statement as? SSAConstAssignmentStatement {
        return "\(s.name.cDeclaration) = \(String(format: "0x%x", s.const));"
    }
    if let s = statement as? SSARegisterJoin8to16Statement {
        return "\(s.name.cDeclaration) = (\(s.otherHigh.cName) << 8) | \(s.otherLow.cName);"
    }
    if let s = statement as? SSARegisterSplit16to8Statement {
        let low: Bool
        
        if case .register(.gpr(_, let p)) = s.name.kind {
            low = p == .low8
        }
        else {
            low = true
        }
        
        let shift = low ? " >> 8" : ""
        return "\(s.name.cDeclaration) = (\(s.other.cName)\(shift)) & 0xff;"
    }
    if let s = statement as? SSAOutStatement {
        return "printf(\">> OUT port %x - data: %x\\n\", \(s.port.cName), \(s.data.cName));"
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

        let nonNullPhis = zip(s.phis, ssaGraph.cfg.predecessors(of: idx.blockId))
            .compactMap { t in t.0.map { ("\(s.name.name)_\($0)", t.1) } }
        
        for (phiName, block) in nonNullPhis {
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
    
    var allVariablesDefined = Set<SSAName>()
    var allVariablesReferenced = Set<SSAName>()
    
    ssaGraph.forEachSSAStatementIndex { idx in
        let stmt = ssaGraph.statementFor(idx)
    
        if deleted.contains(idx) {
            return
        }
        
        allVariablesDefined.formUnion(stmt.variablesDefined)

        if case .phi(_, _) = idx {
            return
        }
        
        allVariablesReferenced.formUnion(stmt.variablesReferenced)
    }
      
    let unboundVariables = allVariablesReferenced.subtracting(allVariablesDefined)
    let parameters = unboundVariables.map { "uint16_t \($0.cName)" }.joined(separator: ", ")
        
    print("#include <stdint.h>")
    print("#include <stdio.h>")
    print()
    print("uint16_t memory_read(int);")
    print("uint16_t memory_write(int, int);")
    print("void     do_int21h(int);")
    print()
    print("#define flags(x)    x")
    print("#define FLAGS(x, y) y")
    print()
    print("void sub_\(ssaGraph.cfg.start.hexString)(\(parameters))")
    print("{")
        
    for phiVariable in phiVariables {
        print("\tuint16_t \(phiVariable);")
    }
    
    print()
 
    let sortedBlocks = ssaGraph.cfg.blocks.keys.sorted()
    for blockId in sortedBlocks {
        let block = ssaGraph.cfg.blocks[blockId]!
                
        print("loc_\(block.start.hexString):;")
        
        var statementsToRewrite = [StatementIndex]()
        
        ssaGraph.forEachSSAStatementIndex(in: block.start) {
            if deleted.contains($0) { return }
            if case .phi = $0 { return }
            statementsToRewrite.append($0)
        }
        
        for (i, index) in statementsToRewrite.enumerated() {
            let stmt = ssaGraph.statementFor(index)
            let lastStatement = (i == (statementsToRewrite.count - 1))
                
            let isJump
                =  (stmt as? SSAJmpStatement) != nil
                || (stmt as? SSAJccStatement) != nil
            
            if lastStatement && isJump {
                printPhiAssignmentsForBlock(block.start)
            }

            rewrite(stmt).map { print("\t\($0)") }

            if lastStatement && !isJump {
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
