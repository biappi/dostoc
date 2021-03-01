//
//  SSAConverter.swift
//  
//
//  Created by Antonio Malara on 27/02/21.
//

import Foundation
import udis86

extension RegisterName {
    var ssa: SSAName { designation.ssa }
}

extension RegisterName.Designations {
    var ssa: SSAName { SSAName(name: "\(self)") }
}

struct SSABlock {
    var phiStatements: [SSAPhiAssignmentStatement]
    var statements: [(Instruction?, [SSAStatement])]
    
    init(cfgBlock: CFGBlock) {
        phiStatements = []
        statements = []
        
        statements = cfgBlock.instructions.map { insn in
            (insn, convert(insn: insn))
        }
    }
    
    var allVariables: Set<SSAName> {
        Set(
            statements
                .flatMap { $0.1 }
                .flatMap { $0.allVariables }
        )
    }
    
    var variablesModified: Set<SSAName> {
        Set(
            statements
                .flatMap { $0.1 }
                .compactMap { $0 as? SSAVariableAssignmentStatement }
                .compactMap { $0.name }
        )
    }
    
    func dump(deleted: Set<StatementIndex>, blockId: UInt64) {
        for (i, stmt) in phiStatements.enumerated() {
            let dead = deleted.contains(.phi(blockId: blockId, phiNr: i))
            let dood = dead ? "MORTO " : ""
            
            let dump = dood + stmt.dump
            let width = 80
            let spc2 = String(repeating: " ", count: width - dump.count)
            let vars = stmt.allVariables.map { $0.dump }.joined(separator: ", ")

            print("\t\(dump)\(spc2)\(vars)")
        }
        
        for (inNr, (insn, ssa)) in statements.enumerated() {
            for (i, stmt) in ssa.enumerated() {
                let dead = deleted.contains(.stmt(blockId: blockId, insn: inNr, stmt: i))
                let dood = dead ? "MORTO " : ""
                
                let dump = dood + stmt.dump
                
                if i == 0 {
                    let width = 40
                    let spc = String(repeating: " ", count: width - dump.count)
                    
                    let asm = insn?.asm ?? ""
                    let spc2 = String(repeating: " ", count: width - asm.count)
                    
                    let vars = stmt.allVariables.map { $0.dump }.joined(separator: ", ")
                    print("\t\(dump)\(spc)\(asm)\(spc2)\(vars)")
                }
                else {
                    let width = 80
                    let spc2 = String(repeating: " ", count: width - dump.count)
                    let vars = stmt.allVariables.map { $0.dump }.joined(separator: ", ")

                    print("\t\(dump)\(spc2)\(vars)")
                }
            }
        }
    }
}

enum StatementIndex :  Hashable {
    case phi(blockId: UInt64, phiNr: Int)
    case stmt(blockId: UInt64, insn: Int, stmt: Int)
   
    var blockId: UInt64 {
        switch self {
        case .phi(blockId: let blockId, _): return blockId
        case .stmt(blockId: let blockId, _, _): return blockId
        }
    }
    
    func dump() -> String {
        switch self {
        case .phi(blockId: let blockId, phiNr: let phiNr):
            return "phi at: \(blockId.hexString) \(phiNr)"
            
        case .stmt(blockId: let blockId, insn: let insn, stmt: let stmt):
            return "stmt at: \(blockId.hexString) \(insn) \(stmt)"
        }
    }
}


struct Converter {
    
    let cfg: CFGGraph
    
    var ssaBlocks = [UInt64 : SSABlock]()
    var doms = [UInt64 : UInt64]()
    var frontier = [UInt64 : [UInt64]]()
    
    func variablesModifiedForNodes() -> [CFGGraph.NodeId : Set<SSAName>] {
        var variablesModifiedInNodes = [CFGGraph.NodeId : Set<SSAName>]()
        
        for (nodeId, ssaBlock) in ssaBlocks {
            variablesModifiedInNodes[nodeId] = ssaBlock.variablesModified
        }
        
        return variablesModifiedInNodes
    }
    
    func allVariables() -> Set<SSAName> {
        return Set(
            ssaBlocks
                .compactMap { $0.value }
                .flatMap { $0.allVariables }
        )
    }
    
    mutating func insertPhiNode(for variable: SSAName, at node: UInt64) {
        let phi = SSAPhiAssignmentStatement(
            name: variable.name,
            phis: Array(
                repeating: 0,
                count: cfg.predecessors(of: node).count
            )
        )
        
        ssaBlocks[node]!.phiStatements.append(phi)
    }
    
    mutating func placePhis() {
        let variablesModifiedInNodes = variablesModifiedForNodes()
        let allVariables = allVariables()
        
        for variable in allVariables {
            var placed   = Set<CFGGraph.NodeId>()
            var visited  = Set<CFGGraph.NodeId>()
            var worklist = Set<CFGGraph.NodeId>()
            
            for (nodeId, _) in ssaBlocks {
                if variablesModifiedInNodes[nodeId]!.contains(variable) {
                    visited.insert(nodeId)
                    worklist.insert(nodeId)
                }
            }
            
            while !worklist.isEmpty {
                let x = worklist.removeFirst()
                
                for y in frontier[x] ?? [] {
                    if !placed.contains(y) {
                        insertPhiNode(for: variable, at: y)
                        
                        placed.insert(y)
                        
                        if !visited.contains(y) {
                            visited.insert(y)
                            worklist.insert(y)
                        }
                    }
                }
            }
        }
    }
    
    mutating func rename() {
        var stacks   = [String : [Int]]()
        var counters = [String :  Int ]()
        
        let genName = { (variable: String) in
            let i = counters[variable, default: 0]
            stacks[variable, default: []].append(i)
            counters[variable] = i + 1
        }

        let getIndex = { (variable: String) -> Int in
            if stacks[variable] == nil {
                genName(variable)
            }
            
            return stacks[variable]!.last!
        }
        
        var visited = Set<UInt64>()
        func rename(_ block: UInt64) {
            if visited.contains(block) {
                return
            }
            
            visited.insert(block)
            
            for i in 0 ..< ssaBlocks[block]!.phiStatements.count {
                let name = ssaBlocks[block]!.phiStatements[i].name
                genName(name)
                ssaBlocks[block]!.phiStatements[i].index = getIndex(name)
            }
            
            for i in 0 ..< ssaBlocks[block]!.statements.count {
                for k in 0 ..< ssaBlocks[block]!.statements[i].1.count {
                    let rhsVariables = ssaBlocks[block]!.statements[i].1[k].rhsVariables
                    
                    for variable in rhsVariables {
                        ssaBlocks[block]!.statements[i].1[k].renameRHS(
                            name: variable.name,
                            index: getIndex(variable.name)
                        )
                    }
                    
                    let lhsVariables = ssaBlocks[block]!.statements[i].1[k].lhsVariables
                    
                    for variable in lhsVariables {
                        genName(variable.name)
                        ssaBlocks[block]!.statements[i].1[k].renameLHS(
                            name: variable.name,
                            index: getIndex(variable.name)
                        )
                    }
                }
            }
            
            for successor in cfg.successors(of: block) {
                for (p, phi) in ssaBlocks[successor]!.phiStatements.enumerated() {
                    let s = cfg.predecessors(of: successor).firstIndex(of: block)!
                    ssaBlocks[successor]!.phiStatements[p].phis[s] = getIndex(phi.name)
                }
            }
            
            var childs = [UInt64]()
            for (node, parent) in doms {
                if parent == block {
                    childs.append(node)
                }
            }
            
            for child in childs {
                rename(child)
            }
            
            for phi in ssaBlocks[block]!.phiStatements {
                stacks[phi.name]!.removeLast()
            }
            
            for stmt in ssaBlocks[block]!.statements.flatMap({ $0.1 }) {
                for variable in stmt.lhsVariables {
                    stacks[variable.name]!.removeLast()
                }
            }
        }
        
        rename(cfg.start)
    }
    
    func forEachSSAStatementIndex(visit: (StatementIndex) -> ()) {
        for (blockId, ssaBlock) in ssaBlocks {
            for (i, _) in ssaBlock.phiStatements.enumerated() {
                visit(StatementIndex.phi(blockId: blockId, phiNr: i))
            }
            
            for (blockId, ssaBlock) in ssaBlocks {
                for (i, (_, stmts)) in ssaBlock.statements.enumerated() {
                    for (s, _) in stmts.enumerated() {
                        visit(StatementIndex.stmt(blockId: blockId, insn: i, stmt: s))
                    }
                }
            }
        }
    }
    
    func statementFor(_ idx: StatementIndex) -> SSAStatement {
        switch idx {
        case .phi(blockId: let blockId, phiNr: let phiNr):
            return ssaBlocks[blockId]!.phiStatements[phiNr]
            
        case .stmt(blockId: let blockId, insn: let insn, stmt: let stmt):
            return ssaBlocks[blockId]!.statements[insn].1[stmt]
        }
    }

    func forEachSSAStatement(visit: (SSAStatement) -> ()) {
        forEachSSAStatementIndex { idx in
            visit(statementFor(idx))
        }
    }
    
    var deleted = Set<StatementIndex>()

    var logDeadCodeElimination = false
    
    mutating func deadCodeElimination() {
        var definitions = [StatementIndex : SSAName]()
        var statementsUsing = [SSAName : Set<StatementIndex>]()
        var statementsDefining = [SSAName : Set<StatementIndex>]()

        if logDeadCodeElimination { print() }
        if logDeadCodeElimination { print() }
        
        forEachSSAStatementIndex { idx in
            let stmt = statementFor(idx)
            if logDeadCodeElimination { print(stmt.dump, "    ", idx) }
            
            for v in stmt.lhsVariables {
                statementsDefining[v, default: Set()].insert(idx)
                if logDeadCodeElimination { print("     defining  \(v.dump)") }
                definitions[idx] = v
                
                if statementsUsing[v] == nil {
                    statementsUsing[v] = []
                    if logDeadCodeElimination { print("     using \(v.dump) -> []") }
                }
            }

            for v in stmt.rhsVariables {
                statementsUsing[v, default: Set()].insert(idx)
                if logDeadCodeElimination { print("     using  \(v.dump)") }
            }
            if logDeadCodeElimination { print() }
        }

        if logDeadCodeElimination { print() }
        if logDeadCodeElimination { print() }
        
        var worklist = Set(definitions.keys)

        while !worklist.isEmpty {
            let stmtIdx = worklist.removeFirst()
            if logDeadCodeElimination { print("\(stmtIdx) -- \(statementFor(stmtIdx).dump)") }
            
            if deleted.contains(stmtIdx) {
                if logDeadCodeElimination {  print(" > already deleted \(stmtIdx)") }
                continue
            }
            
            guard let variable = definitions[stmtIdx] else {
                if logDeadCodeElimination { print(" > no var in defs") }
                continue
            }
            
            if statementsUsing[variable, default: []].count != 0 {
                if logDeadCodeElimination { print(" > count != 0 -- \(variable.dump) - \(statementsUsing[variable] ?? [])") }
                continue
            }
            
            if logDeadCodeElimination { print("    WANT TO ELIMINATE \(variable.dump)") }

            deleted.formUnion(statementsDefining[variable] ?? [])
            
            let rhs = statementFor(stmtIdx).rhsVariables
            if logDeadCodeElimination { print("        >>", rhs.map { $0.dump }) }
            
            for variable in rhs {
                if logDeadCodeElimination { print("            >>", statementsDefining[variable, default: []].map { "\(statementFor($0).dump) - \($0)"}) }
                worklist.formUnion(statementsDefining[variable, default: []])
                
                statementsUsing[variable]?.remove(stmtIdx)
            }
            
        }
    }
        
    
    mutating func convert() {
        doms = dominators(graph: cfg)
        frontier = dominanceFrontier(graph: cfg, doms: doms)
        
        cfg.visit { block in
            ssaBlocks[block.start] = SSABlock(cfgBlock: block)
        }
        
        placePhis()
        rename()
        deadCodeElimination()
            
        var i = 0
        cfg.visit {
            cfgblock in
            
            let backlinks = cfgblock.backlinks.map { $0.hexString }.joined(separator: ", ")
            let fwdlinks = cfgblock.end.map { $0.hexString }.joined(separator: ", ")

            print("Block \(i) [\(cfgblock.start.hexString)] - (\(backlinks)) --> (\(fwdlinks))")
            print()
            
            ssaBlocks[cfgblock.start]?.dump(deleted: deleted, blockId: cfgblock.start)
            print()
            print()

            i += 1
        }
    }
}

extension SSABlock {
    mutating func convert(insn: Instruction) -> [SSAStatement] {
        let op0 = insn.operands.0
        let op1 = insn.operands.1

        typealias regs = RegisterName.Designations
//        print(insn.asm)
        
        switch insn.mnemonic {
        
        case UD_Ipush:
            assert(op0.operandType == .reg)
            
            return [
                SSAMemoryAssignmentStatement(
                    name: regs.sp.ssa,
                    expression: SSARegExpression(name: op0.registerName.ssa)
                ),
                SSAVariableAssignmentStatement(
                    name: regs.sp.ssa,
                    expression: SSADiffExpression(
                        lhs: SSARegExpression(name: regs.sp.ssa),
                        rhs: SSAConstExpression(value: 2)
                    )
                )
            ]
            
        case UD_Ipop:
            assert(op0.operandType == .reg)
            return [
                SSAVariableAssignmentStatement(
                    name: regs.sp.ssa,
                    expression: SSASumExpression(
                        lhs: SSARegExpression(name: regs.sp.ssa),
                        rhs: SSAConstExpression(value: 2)
                    )
                ),
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSAMemoryExpression(name: regs.sp.ssa)
                )
            ]
            
        case UD_Imov:
            if op0.operandType == .reg && op1.operandType == .reg {
                return [
                    SSAVariableAssignmentStatement(
                        name: op0.registerName.ssa,
                        expression: SSARegExpression(name: op1.registerName.ssa)
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .mem {
                assert(insn.prefixSegment == nil)
                let op1mem = MemoryOperand(op1)
                let temp = SSAName(name: "TEMP") // XXX
                return [
                    SSAVariableAssignmentStatement(
                        name: temp,
                        expression: SSASumExpression(
                            lhs: SSARegExpression(name: op1mem.base.ssa),
                            rhs: SSAConstExpression(value: Int(op1mem.offset))
                        )
                    ),
                    SSAVariableAssignmentStatement(
                        name: op0.registerName.ssa,
                        expression: SSAMemoryExpression(name: temp)
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .imm {
                return [
                    SSAVariableAssignmentStatement(
                        name: op0.registerName.ssa,
                        expression: SSAConstExpression(value: Int(op1.uint64value))
                    )
                ]
            }
            else if op0.operandType == .mem && op1.operandType == .reg {
                let seg  = insn.prefixSegment.map { "\($0):"} ?? ""
                let name = "\(seg)\(op0.registerName.designation)"
                
                return [
                    SSASegmentedMemoryAssignmentStatement(
                        address:  name,
                        expression: SSARegExpression(name: op1.registerName.ssa)
                    )
                ]
            }
            else {
                fatalError()
            }
            
        case UD_Iint:
            assert(op0.operandType == .imm)
            
            return [
                SSAIntStatement(interrupt: Int(op0.uint64value))
            ]
            
        case UD_Ijae:
            assert(op0.operandType == .jimm)
            
            let offset = UInt64(Int64(insn.pc) + op0.int64value)
            let label = SSALabel(target: String(format: "loc_%x", offset))
            
            return [
                SSAJmpStatement(type: "jae", target: label)
            ]
        
        case UD_Ijns:
            assert(op0.operandType == .jimm)
            
            let offset = UInt64(Int64(insn.pc) + op0.int64value)
            let label = SSALabel(target: String(format: "loc_%x", offset))
            
            return [
                SSAJmpStatement(type: "jns", target: label)
            ]

        case UD_Iretf:
            return [SSAEndStatement()]
            
        case UD_Iadd:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .imm)
            
            return [
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSASumExpression(
                        lhs: SSARegExpression(name: op0.registerName.ssa),
                        rhs: SSAConstExpression(value: Int(op1.uint64value))
                    )
                )
            ]

        case UD_Isub:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .reg)
            
            return [
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSADiffExpression(
                        lhs: SSARegExpression(name: op0.registerName.ssa),
                        rhs: SSARegExpression(name: op1.registerName.ssa)
                    )
                )
            ]
            
        case UD_Imul:
            if op0.operandType == .reg && op1.operandType == .reg {
                return [
                    SSAVariableAssignmentStatement(
                        name: op0.registerName.ssa,
                        expression: SSAMulExpression(
                            lhs: SSARegExpression(name: op0.registerName.ssa),
                            rhs: SSARegExpression(name: op1.registerName.ssa)
                        )
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == nil {
                return [
                    SSAVariableAssignmentStatement(
                        name: regs.ax.ssa,
                        expression: SSAMulExpression(
                            lhs: SSARegExpression(name: op0.registerName.ssa),
                            rhs: SSARegExpression(name: regs.ax.ssa)
                        )
                    )
                ]
            }
            else {
                fatalError()
            }
            
        case UD_Ishr:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .const)
            
            return [
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSAShiftRight(
                        lhs: SSARegExpression(name: op0.registerName.ssa),
                        rhs: SSAConstExpression(value: Int(op1.uint64value))
                    )
                )
            ]

        case UD_Iinc:
            assert(op0.operandType == .reg)
            
            return [
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSASumExpression(
                        lhs: SSARegExpression(name: op0.registerName.ssa),
                        rhs: SSAConstExpression(value: 1)
                    )
                )
            ]

        case UD_Idec:
            assert(op0.operandType == .reg)
            
            return [
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSADiffExpression(
                        lhs: SSARegExpression(name: op0.registerName.ssa),
                        rhs: SSAConstExpression(value: 1)
                    )
                )
            ]

        case UD_Iloop:
            assert(op0.operandType == .jimm)
            
            let offset = UInt64(Int64(insn.pc) + op0.int64value)
            let label = SSALabel(target: String(format: "loc_%x", offset))

            return [
                SSAJmpStatement(type: "loop", target: label)
            ]
            
        case UD_Icall:
            assert(op0.operandType == .jimm)

            let offset = UInt64(Int64(insn.pc) + op0.int64value)
            let label = SSALabel(target: String(format: "loc_%x", offset))

            return [
                SSACallStatement(target: label)
            ]

            
        default:
            fatalError()
        }
    }
    
}
