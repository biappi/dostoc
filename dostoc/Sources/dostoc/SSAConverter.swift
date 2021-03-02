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
        let width = 50
        
        for (i, stmt) in phiStatements.enumerated() {
            let dead = deleted.contains(.phi(blockId: blockId, phiNr: i))
            let dood = dead ? "MORTO " : "      "
            let dump = stmt.dump.padding(toLength: width + 30, withPad: " ", startingAt: 0)
            let vars = stmt.allVariables.map { $0.dump }.joined(separator: ", ")

            print("\t\(dood)\(dump)\(vars)")
        }
        
        for (inNr, (insn, ssa)) in statements.enumerated() {
            for (i, stmt) in ssa.enumerated() {
                let dead = deleted.contains(.stmt(blockId: blockId, insn: inNr, stmt: i))
                let dood = dead ? "MORTO " : "      "
                let dump = stmt.dump
                
                let d: String
                let a: String
                let v: String
                
                if i == 0 {
                    let asm = insn?.asm ?? ""
                    let vars = stmt.allVariables.map { $0.dump }.joined(separator: ", ")
                    
                    d = dump.padding(toLength: width, withPad: " ", startingAt: 0)
                    a = asm .padding(toLength: 30,    withPad: " ", startingAt: 0)
                    v = vars
                }
                else {
                    let vars = stmt.allVariables.map { $0.dump }.joined(separator: ", ")

                    d = dump.padding(toLength: width, withPad: " ", startingAt: 0)
                    a = ""  .padding(toLength: 30   , withPad: " ", startingAt: 0)
                    v = vars
                }
                
                print("\t\(dood)\(d)\(a)\(v)")
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

struct SSAGraph {
    let cfg: CFGGraph
    
    var ssaBlocks = [UInt64 : SSABlock]()

    init(from cfg: CFGGraph) {
        var blocks = [UInt64 : SSABlock]()
        
        cfg.visit { block in
            blocks[block.start] = SSABlock(cfgBlock: block)
        }
        
        blocks[cfg.start]!
            .statements
            .insert(
                (nil, PrologueStatements()),
                at: 0
            )
        
        self.cfg = cfg
        self.ssaBlocks = blocks
    }
    
    var allVariables: Set<SSAName> {
        return Set(
            ssaBlocks
                .compactMap { $0.value }
                .flatMap { $0.allVariables }
        )
    }
    
    var variablesModifiedForNodes: [CFGGraph.NodeId : Set<SSAName>] {
        var variablesModifiedInNodes = [CFGGraph.NodeId : Set<SSAName>]()
        
        for (nodeId, ssaBlock) in ssaBlocks {
            variablesModifiedInNodes[nodeId] = ssaBlock.variablesModified
        }
        
        return variablesModifiedInNodes
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

    func forEachSSAStatementIndex(in blockId: UInt64, visit: (StatementIndex) -> ()) {
        let ssaBlock = ssaBlocks[blockId]!
        
        for (i, _) in ssaBlock.phiStatements.enumerated() {
            visit(StatementIndex.phi(blockId: blockId, phiNr: i))
        }
        
        for (i, (_, stmts)) in ssaBlock.statements.enumerated() {
            for (s, _) in stmts.enumerated() {
                visit(StatementIndex.stmt(blockId: blockId, insn: i, stmt: s))
            }
        }
        
    }
    
    func forEachSSAStatementIndex(visit: (StatementIndex) -> ()) {
        for (blockId, _) in ssaBlocks {
            forEachSSAStatementIndex(in: blockId, visit: visit)
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
    
    func dump(deleted: Set<StatementIndex>) {
        var i = 0
        cfg.visit {
            cfgblock in
            
            let backlinks = cfg.predecessors(of: cfgblock.start).map { $0.hexString }.joined(separator: ", ")
            let fwdlinks = cfgblock.end.map { $0.hexString }.joined(separator: ", ")

            print("Block \(i) [\(cfgblock.start.hexString)] - (\(backlinks)) --> (\(fwdlinks))")
            print()
            
            ssaBlocks[cfgblock.start]?.dump(deleted: deleted, blockId: cfgblock.start)
            print()

            i += 1
        }
    }
}

struct Converter {
    let cfg: CFGGraph
    var ssaGraph: SSAGraph
    
    var doms = [UInt64 : UInt64]()
    var frontier = [UInt64 : [UInt64]]()
    
    mutating func placePhis() {
        let variablesModifiedInNodes = ssaGraph.variablesModifiedForNodes
        let allVariables = ssaGraph.allVariables
        
        for variable in allVariables {
            var placed   = Set<CFGGraph.NodeId>()
            var visited  = Set<CFGGraph.NodeId>()
            var worklist = Set<CFGGraph.NodeId>()
            
            for (nodeId, _) in ssaGraph.ssaBlocks {
                if variablesModifiedInNodes[nodeId]!.contains(variable) {
                    visited.insert(nodeId)
                    worklist.insert(nodeId)
                }
            }
            
            while !worklist.isEmpty {
                let x = worklist.removeFirst()
                
                for y in frontier[x] ?? [] {
                    if !placed.contains(y) {
                        ssaGraph.insertPhiNode(for: variable, at: y)
                        
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
            
            for i in 0 ..< ssaGraph.ssaBlocks[block]!.phiStatements.count {
                let name = ssaGraph.ssaBlocks[block]!.phiStatements[i].name
                genName(name)
                ssaGraph.ssaBlocks[block]!.phiStatements[i].index = getIndex(name)
            }
            
            for i in 0 ..< ssaGraph.ssaBlocks[block]!.statements.count {
                for k in 0 ..< ssaGraph.ssaBlocks[block]!.statements[i].1.count {
                    let rhsVariables = ssaGraph.ssaBlocks[block]!.statements[i].1[k].rhsVariables
                    
                    for variable in rhsVariables {
                        ssaGraph.ssaBlocks[block]!.statements[i].1[k].renameRHS(
                            name: variable.name,
                            index: getIndex(variable.name)
                        )
                    }
                    
                    let lhsVariables = ssaGraph.ssaBlocks[block]!.statements[i].1[k].lhsVariables
                    
                    for variable in lhsVariables {
                        genName(variable.name)
                        ssaGraph.ssaBlocks[block]!.statements[i].1[k].renameLHS(
                            name: variable.name,
                            index: getIndex(variable.name)
                        )
                    }
                }
            }
            
            for successor in cfg.successors(of: block) {
                for (p, phi) in ssaGraph.ssaBlocks[successor]!.phiStatements.enumerated() {
                    let s = cfg.predecessors(of: successor).firstIndex(of: block)!
                    ssaGraph.ssaBlocks[successor]!.phiStatements[p].phis[s] = getIndex(phi.name)
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
            
            for phi in ssaGraph.ssaBlocks[block]!.phiStatements {
                stacks[phi.name]!.removeLast()
            }
            
            for stmt in ssaGraph.ssaBlocks[block]!.statements.flatMap({ $0.1 }) {
                for variable in stmt.lhsVariables {
                    stacks[variable.name]!.removeLast()
                }
            }
        }
        
        rename(cfg.start)
    }
        
    var deleted = Set<StatementIndex>()

    var logDeadCodeElimination = false
    
    mutating func deadCodeElimination() {
        var definitions = [StatementIndex : SSAName]()
        var statementsUsing = [SSAName : Set<StatementIndex>]()
        var statementsDefining = [SSAName : Set<StatementIndex>]()

        if logDeadCodeElimination { print() }
        if logDeadCodeElimination { print() }
        
        ssaGraph.forEachSSAStatementIndex { idx in
            let stmt = ssaGraph.statementFor(idx)
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
            let stmt = ssaGraph.statementFor(stmtIdx)
            
            if logDeadCodeElimination { print("\(stmtIdx) -- \(stmt)") }
            
            if (stmt as? SSAJccStatement) != nil {
                continue
            }
            
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
            
            let rhs = stmt.rhsVariables
            if logDeadCodeElimination { print("        >>", rhs.map { $0.dump }) }
            
            for variable in rhs {
                if logDeadCodeElimination { print("            >>", statementsDefining[variable, default: []].map { "\(ssaGraph.statementFor($0).dump) - \($0)"}) }
                worklist.formUnion(statementsDefining[variable, default: []])
                
                statementsUsing[variable]?.remove(stmtIdx)
            }
            
        }
    }
        
    init(cfg: CFGGraph) {
        self.cfg = cfg
        ssaGraph = SSAGraph(from: cfg)
        doms = dominators(graph: cfg)
        frontier = dominanceFrontier(graph: cfg, doms: doms)
    }
    
    mutating func convert() {
        placePhis()
        rename()
        deadCodeElimination()
        
        ssaGraph.dump(deleted: deleted)
    }
}

extension SSABlock {
    mutating func convert(insn: Instruction) -> [SSAStatement] {
        let op0 = insn.operands.0
        let op1 = insn.operands.1

        print(insn.asm)
        
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
                assert(op1mem.base != nil)
                
                let temp = SSAName(name: "TEMP_\(insn.offset.hexString)")
                return [
                    SSAVariableAssignmentStatement(
                        name: temp,
                        expression: SSASumExpression(
                            lhs: SSARegExpression(name: op1mem.base!.ssa),
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
                let segment = insn
                    .prefixSegment
                    .flatMap { SSAName(name: "\($0)")}
                    .flatMap { SSARegExpression(name: $0)}
                
                return [
                    SSASegmentedMemoryRegAssignmentStatement(
                        segment: segment,
                        address: SSARegExpression(name: op0.registerName.ssa),
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
                SSAJccStatement(type: "jae", target: label)
            ]
        
        case UD_Ijns:
            assert(op0.operandType == .jimm)
            
            let offset = UInt64(Int64(insn.pc) + op0.int64value)
            let label = SSALabel(target: String(format: "loc_%x", offset))
            
            return [
                SSAJccStatement(type: "jns", target: label)
            ]

        case UD_Ijnz:
            assert(op0.operandType == .jimm)
            
            let offset = UInt64(Int64(insn.pc) + op0.int64value)
            let label = SSALabel(target: String(format: "loc_%x", offset))
            
            return [
                SSAJccStatement(type: "jnz", target: label)
            ]

        case UD_Iret:
            return EpilogueStatements()

        case UD_Iretf:
            return EpilogueStatements()
            
        case UD_Iadd:
            if op0.operandType == .reg && op1.operandType == .imm {
                return [
                    SSAVariableAssignmentStatement(
                        name: op0.registerName.ssa,
                        expression: SSASumExpression(
                            lhs: SSARegExpression(name: op0.registerName.ssa),
                            rhs: SSAConstExpression(value: Int(op1.uint64value))
                        )
                    )
                ]
            }
            if op0.operandType == .reg && op1.operandType == .reg {
                return [
                   SSAVariableAssignmentStatement(
                       name: op0.registerName.ssa,
                       expression: SSARegExpression(name: op0.registerName.ssa)
                   )
               ]
            }
            else {
                fatalError()
            }
            
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
                ),
                SSAFlagsAssignmentStatement(
                    name: SSAName(name: "flags"),
                    expression: SSARegExpression(name: op0.registerName.ssa)

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
            
            
        case UD_Ishl:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .const)
            
            return [
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSABinaryOpExpression(
                        op: .shl,
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
                ),
                SSAFlagsAssignmentStatement(
                    name: SSAName(name: "flags"),
                    expression: SSARegExpression(name: op0.registerName.ssa)
                )
            ]

        case UD_Iloop:
            assert(op0.operandType == .jimm)
            
            let offset = UInt64(Int64(insn.pc) + op0.int64value)
            let label = SSALabel(target: String(format: "loc_%x", offset))

            return [
                SSAVariableAssignmentStatement(
                    name: regs.cx.ssa,
                    expression: SSADiffExpression(
                        lhs: SSARegExpression(name: regs.cx.ssa),
                        rhs: SSAConstExpression(value: 1)
                    )
                ),
//                SSAFlagsAssignmentStatement(
//                    name: SSAName(name: "flags"),
//                    expression: SSARegExpression(name: op0.registerName.ssa)
//                ),

                SSAVariableAssignmentStatement(
                    name: SSAName(name: "flags"),
                    expression: SSARegExpression(name: regs.cx.ssa)
                ),
                SSAJccStatement(type: "loop", target: label)
            ]
            
        case UD_Icall:
            if op0.operandType == .ptr {
                let so = String(format: "%x:%x", op0.lval.ptr.seg, op0.lval.ptr.off)
                let label = SSALabel(target: so)
                return [
                    SSACallStatement(target: label)
                ]
            }
            else {
                assert(op0.operandType == .jimm)
                
                let offset = UInt64(Int64(insn.pc) + op0.int64value)
                let label = SSALabel(target: String(format: "loc_%x", offset))
                
                return [
                    SSACallStatement(target: label)
                ]
            }
            
        case UD_Icmp:
            if op0.operandType == .mem && op1.operandType == .imm {
                assert(insn.prefixSegment == nil)
                
                
                assert(op0.offset == 16)
                assert(op0.base == UD_NONE)
                
                let offset = UInt64(op0.uint64value)
                let temp_mem = SSAName(name: "TEMP_\(insn.offset.hexString)")
                
                return [
                    SSAVariableAssignmentStatement(
                        name: temp_mem,
                        expression: SSAMemoryLabelExpression(label: "\(offset.hexString)")
                    ),
                    SSAFlagsAssignmentStatement(
                        name: SSAName(name: "flags"),
                        expression: SSADiffExpression(
                            lhs: SSARegExpression(name: temp_mem),
                            rhs: SSAConstExpression(value: Int(op1.int64value))
                        )
                    )

                ]
            }
            else {
                fatalError()
            }

            
        default:
            fatalError()
        }
    }
    
}

func PrologueStatements() -> [SSAStatement] {
    return [
        SSAPrologueStatement(register: SSARegExpression(name: regs.ax.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.bx.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.cx.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.dx.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.bp.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.sp.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.si.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.di.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.ip.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.es.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.cs.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.ss.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.ds.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.fs.ssa)),
        SSAPrologueStatement(register: SSARegExpression(name: regs.gs.ssa)),
    ]
}

func EpilogueStatements() -> [SSAStatement] {
    return [
        SSAEndStatement(),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.ax.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.bx.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.cx.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.dx.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.bp.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.sp.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.si.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.di.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.ip.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.es.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.cs.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.ss.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.ds.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.fs.ssa)),
        SSAEpilogueStatement(register: SSARegExpression(name: regs.gs.ssa)),
    ]
}
