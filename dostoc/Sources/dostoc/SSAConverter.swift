//
//  SSAConverter.swift
//  
//
//  Created by Antonio Malara on 27/02/21.
//

import Foundation
import udis86

extension Register {
    var ssa: SSAName { SSAName(register: self) }
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
        let tabled = true
        
        let width = 50
        
        let dumpvars = { (stmt: SSAStatement) -> String in
            stmt.allVariables.map {
                "\($0.dump)" // ":\($0.size)"
            }.joined(separator: ", ")
        }
        
        for (i, stmt) in phiStatements.enumerated() {
            let dead = deleted.contains(.phi(blockId: blockId, phiNr: i))
            let dood = dead ? "MORTO " : "      "
            let dump = stmt.dump.padding(toLength: width + 30, withPad: " ", startingAt: 0)
            let vars = dumpvars(stmt)
            
            if tabled {
                print("\t\(dood)\(dump)\(vars)")
            }
            else {
                print("\t\(dood)stmt: \(stmt.dump)")
                print("\t      vars: \(vars)")
                print()
            }
        }
        
        for (inNr, (insn, ssa)) in statements.enumerated() {
            for (i, stmt) in ssa.enumerated() {
                if stmt as? SSAPrologueStatement != nil {
                    continue
                }
                
                if stmt as? SSAEpilogueStatement != nil {
                    continue
                }
                
                let dead = deleted.contains(.stmt(blockId: blockId, insn: inNr, stmt: i))
                let dood = dead ? "MORTO " : "      "
                let dump = stmt.dump
                
                let vars = dumpvars(stmt)
                let asm = i == 0 ? insn?.asm ?? "" : ""
                let d = dump.padding(toLength: width, withPad: " ", startingAt: 0)
                let a = asm .padding(toLength: 30,    withPad: " ", startingAt: 0)
                let v = vars
                
                if tabled {
                    print("\t\(dood)\(d)\(a)\(v)")
                }
                else {
                    print("\t\(dood)stmt: \(stmt.dump)")
                    print("\t      vars: \(vars)")
                    print("\t      asm:  \(a)")
                    print()
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
            name: variable,
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
                genName(name.name)
                ssaGraph.ssaBlocks[block]!.phiStatements[i].name.index = getIndex(name.name)
            }
            
            for i in 0 ..< ssaGraph.ssaBlocks[block]!.statements.count {
                for k in 0 ..< ssaGraph.ssaBlocks[block]!.statements[i].1.count {
                    let rhsVariables = ssaGraph.ssaBlocks[block]!.statements[i].1[k].variablesReferenced
                    
                    for variable in rhsVariables {
                        ssaGraph.ssaBlocks[block]!.statements[i].1[k].renameReferencedVariables(
                            name: variable.name,
                            index: getIndex(variable.name)
                        )
                    }
                    
                    let lhsVariables = ssaGraph.ssaBlocks[block]!.statements[i].1[k].variablesDefined
                    
                    for variable in lhsVariables {
                        genName(variable.name)
                        ssaGraph.ssaBlocks[block]!.statements[i].1[k].renameDefinedVariables(
                            name: variable.name,
                            index: getIndex(variable.name)
                        )
                    }
                }
            }
            
            for successor in cfg.successors(of: block) {
                for (p, phi) in ssaGraph.ssaBlocks[successor]!.phiStatements.enumerated() {
                    let s = cfg.predecessors(of: successor).firstIndex(of: block)!
                    ssaGraph.ssaBlocks[successor]!.phiStatements[p].phis[s] = getIndex(phi.name.name)
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
                stacks[phi.name.name]!.removeLast()
            }
            
            for stmt in ssaGraph.ssaBlocks[block]!.statements.flatMap({ $0.1 }) {
                for variable in stmt.variablesDefined {
                    stacks[variable.name]!.removeLast()
                }
            }
        }
        
        rename(cfg.start)
    }
        
    var deleted = Set<StatementIndex>()

    mutating func deadCodeElimination() {
        var definitions = [StatementIndex : SSAName]()
        var statementsUsing = [SSAName : Set<StatementIndex>]()
        var statementsDefining = [SSAName : Set<StatementIndex>]()
        
        ssaGraph.forEachSSAStatementIndex { idx in
            let stmt = ssaGraph.statementFor(idx)
            
            for v in stmt.variablesDefined {
                statementsDefining[v, default: Set()].insert(idx)
                definitions[idx] = v
                
                if statementsUsing[v] == nil {
                    statementsUsing[v] = []
                }
            }

            for v in stmt.variablesReferenced {
                statementsUsing[v, default: Set()].insert(idx)
            }
        }
        
        var worklist = Set(definitions.keys)

        while !worklist.isEmpty {
            let stmtIdx = worklist.removeFirst()
            let stmt = ssaGraph.statementFor(stmtIdx)
            
            if (stmt as? SSAJccStatement) != nil {
                continue
            }
            
            if deleted.contains(stmtIdx) {
                continue
            }
            
            guard let variable = definitions[stmtIdx] else {
                continue
            }
            
            if statementsUsing[variable, default: []].count != 0 {
                continue
            }
            
            let definingVariable = statementsDefining[variable] ?? []
            deleted.formUnion(definingVariable)
            
            for variable in stmt.variablesReferenced {
                worklist.formUnion(definingVariable)
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

        func TempName(_ insn: Instruction, _ x: Int? = nil) -> SSAName {
            return SSAName(name: "T_\(x.map {  "\($0)_"} ?? "")\(insn.offset.hexString)")
        }
        
        print(insn.asm)
        
        switch insn.mnemonic {
        
        case UD_Ipush:
            assert(op0.operandType == .reg)
            let tempName = TempName(insn)
            
            return [
                SSAMemoryAddressResolver(
                    name: tempName,
                    addressing: Addressing.stackPointer
                ),
                SSAMemoryWriteStatement(
                    address: tempName,
                    expression: SSAVariableExpression(name: op0.registerName.ssa)
                ),
                SSABinaryOpStatement(
                    result: Register.gpr(.sp, .low16).ssa,
                    op: .diff,
                    lhs: .gpr(.sp, .low16),
                    rhs: Int(2)
                )
            ]
            
        case UD_Ipop:
            assert(op0.operandType == .reg)
            let tempName = TempName(insn)
            
            return [
                SSABinaryOpStatement(
                    result: Register.gpr(.sp, .low16).ssa,
                    op: .sum,
                    lhs: .gpr(.sp, .low16),
                    rhs: Int(2)
                ),
                SSAMemoryAddressResolver(
                    name: tempName,
                    addressing: Addressing.stackPointer
                ),
                SSAMemoryReadStatement(
                    name: SSAName(register: .gpr(.sp, .low16)),
                    address: tempName
                ),
            ]
            
        case UD_Imov:
            if op0.operandType == .reg && op1.operandType == .reg {
                return [
                    SSAVariableAssignmentStatement(
                        name: op0.registerName.ssa,
                        expression: SSAVariableExpression(name: op1.registerName.ssa)
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .mem {
                print(op0.size, op1.size)
                let tempName = TempName(insn)
                
                return [
                    SSAMemoryAddressResolver(
                        name: tempName,
                        addressing: Addressing(insn, op1)
                    ),

                    SSAMemoryReadStatement(
                        name: op0.registerName.ssa,
                        address: tempName
                    ),
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
                print(op0.size, op1.size)
                let tempName = TempName(insn)
                
                return [
                    SSAMemoryAddressResolver(
                        name: tempName,
                        addressing: Addressing(insn, op0)
                    ),
                    SSAMemoryWriteStatement(
                        address: tempName,
                        expression: SSAVariableExpression(name: op1.registerName.ssa)
                    )
                ]
            }
            else if op0.operandType == .mem && op1.operandType == .imm {
                print(op0.size, op1.size)

                let tempName = TempName(insn)
                
                return [
                    SSAMemoryAddressResolver(
                        name: tempName,
                        addressing: Addressing(insn, op0)
                    ),
                    SSAMemoryWriteStatement(
                        address: tempName,
                        expression: SSAConstExpression(value: Int(op1.uint64value))
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
            
        case UD_Ijmp:
            return Jump(insn: insn)

        case UD_Ijae:
            return Jump(insn: insn, type: "jae")
            
        case UD_Ijns:
            return Jump(insn: insn, type: "jns")
            
        case UD_Ijnz:
            return Jump(insn: insn, type: "jnz")
            
        case UD_Ijz:
            return Jump(insn: insn, type: "jz")

        case UD_Iret:
            return EpilogueStatements()

        case UD_Iretf:
            return EpilogueStatements()
            
        case UD_Iadd:
            if op0.operandType == .reg && op1.operandType == .imm {
                return [
                    SSABinaryOpStatement(
                        result: op0.registerName.ssa,
                        op: .sum,
                        lhs: op0.registerName,
                        rhs: Int(op1.uint64value)
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .reg {
                return [
                   SSAVariableAssignmentStatement(
                       name: op0.registerName.ssa,
                       expression: SSAVariableExpression(name: op0.registerName.ssa)
                   )
               ]
            }
            else {
                fatalError()
            }
            
        case UD_Isub:
            if op0.operandType == .reg && op1.operandType == .imm {
                return [
                    SSABinaryOpStatement(
                        result: op0.registerName.ssa,
                        op: .diff,
                        lhs: op0.registerName,
                        rhs: Int(op1.uint64value)
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .reg {
                return [
                    SSABinaryOpStatement(
                        result: op0.registerName.ssa,
                        op: .diff,
                        lhs: op0.registerName,
                        rhs: op1.registerName
                    ),
                    SSAFlagsAssignmentStatement(
                        expression: SSAVariableExpression(name: op0.registerName.ssa)
                    )
                ]
            }
            else {
                fatalError()
            }
            
        case UD_Imul:
            if op0.operandType == .reg && op1.operandType == .reg {
                return [
                    SSABinaryOpStatement(
                        result: op0.registerName.ssa,
                        op: .mul,
                        lhs: op0.registerName,
                        rhs: op1.registerName
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == nil {
                return [
                    SSABinaryOpStatement(
                        result: Register.gpr(.ax, .low16).ssa,
                        op: .mul,
                        lhs: op0.registerName,
                        rhs: .gpr(.ax, .low16)
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
                SSABinaryOpStatement(
                    result: op0.registerName.ssa,
                    op: .shr,
                    lhs: op0.registerName,
                    rhs: Int(op1.uint64value)
                )
            ]
            
        case UD_Ishl:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .const)
            
            return [
                SSABinaryOpStatement(
                    result: op0.registerName.ssa,
                    op: .shl,
                    lhs: op0.registerName,
                    rhs: Int(op1.uint64value)
                )
            ]

        case UD_Iinc:
            assert(op0.operandType == .reg)
            
            return [
                SSABinaryOpStatement(
                    result: op0.registerName.ssa,
                    op: .sum,
                    lhs: op0.registerName,
                    rhs: Int(1)
                )
            ]

        case UD_Idec:
            assert(op0.operandType == .reg)
            
            return [
                SSABinaryOpStatement(
                    result: op0.registerName.ssa,
                    op: .diff,
                    lhs: op0.registerName,
                    rhs: Int(1)
                ),
                SSAFlagsAssignmentStatement(
                    expression: SSAVariableExpression(name: op0.registerName.ssa)
                )
            ]

        case UD_Iand:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .imm)

            return [
                SSABinaryOpStatement(
                    result: op0.registerName.ssa,
                    op: .and,
                    lhs: op0.registerName,
                    rhs: Int(op1.uint64value)
                )
            ]
        
        case UD_Iloop:
            assert(op0.operandType == .jimm)
            
            let label = SSALabel(
                pc: insn.pc,
                offset: op0.int64value
            )
            
            return [
                SSABinaryOpStatement(
                    result: Register.gpr(.cx, .low16).ssa,
                    op: .diff,
                    lhs: .gpr(.cx, .low16),
                    rhs: Int(1)
                ),
                SSAFlagsAssignmentStatement(
                    expression: SSAVariableExpression(name: SSAName(register: .gpr(.cx, .low16)))
                ),
                SSAJccStatement(type: "loop", target: label)
            ]
            
        case UD_Icall:
            if op0.operandType == .ptr {
                return [
                    SSACallStatement(
                        target: SSALabel(
                            seg:    op0.lval.ptr.seg,
                            offset: op0.lval.ptr.off
                        )
                    )
                ]
            }
            else {
                assert(op0.operandType == .jimm)
                
                return [
                    SSACallStatement(
                        target: SSALabel(
                            pc:     insn.pc,
                            offset: op0.int64value
                        )
                    )
                ]
            }
            
        case UD_Icmp:
            if op0.operandType == .mem && op1.operandType == .imm {
                let address = TempName(insn)
                let tempName = TempName(insn, 1)

                return [
                    SSAMemoryAddressResolver(
                        name: address,
                        addressing: Addressing(insn, op0)
                    ),
                    SSAMemoryReadStatement(
                        name: tempName,
                        address: address
                    ),
                    SSABinaryOpStatement(
                        result: tempName,
                        op: .diff,
                        lhs: tempName,
                        rhs: Int(op1.int64value)
                    ),
                    SSAFlagsAssignmentStatement(
                        expression: SSAVariableExpression(name: tempName)
                    )
                ]
            }
            if op0.operandType == .reg && op1.operandType == .imm {
                let tempName = TempName(insn)
                
                return [
                    SSABinaryOpStatement(
                        result: tempName,
                        op: .diff,
                        lhs: op0.registerName,
                        rhs: Int(op1.int64value)
                    ),

                    SSAFlagsAssignmentStatement(
                        expression: SSAVariableExpression(name: tempName)
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

func Jump(insn: Instruction, type: String? = nil) -> [SSAStatement] {
    assert(insn.operands.0.operandType == .jimm)
    
    let label = SSALabel(
        pc: insn.pc,
        offset: insn.operands.0.int64value
    )
    
    if let type = type {
        return [ SSAJccStatement(type: type, target: label) ]
    }
    else {
        return [ SSAJmpStatement(target: label) ]
    }
}

func PrologueStatements() -> [SSAStatement] {
    return [
        SSAPrologueStatement(register: SSAName(register: .gpr(.ax, .low16))),
        SSAPrologueStatement(register: SSAName(register: .gpr(.bx, .low16))),
        SSAPrologueStatement(register: SSAName(register: .gpr(.cx, .low16))),
        SSAPrologueStatement(register: SSAName(register: .gpr(.dx, .low16))),
        SSAPrologueStatement(register: SSAName(register: .gpr(.bp, .low16))),
        SSAPrologueStatement(register: SSAName(register: .gpr(.sp, .low16))),
        SSAPrologueStatement(register: SSAName(register: .gpr(.si, .low16))),
        SSAPrologueStatement(register: SSAName(register: .gpr(.di, .low16))),
        SSAPrologueStatement(register: SSAName(register: .segment(.es))),
        SSAPrologueStatement(register: SSAName(register: .segment(.cs))),
        SSAPrologueStatement(register: SSAName(register: .segment(.ss))),
        SSAPrologueStatement(register: SSAName(register: .segment(.ds))),
        SSAPrologueStatement(register: SSAName(register: .segment(.fs))),
        SSAPrologueStatement(register: SSAName(register: .segment(.gs))),
    ]
}

func EpilogueStatements() -> [SSAStatement] {
    return [
        SSAEndStatement(),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.ax, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.bx, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.cx, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.dx, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.bp, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.sp, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.si, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .gpr(.di, .low16))),
        SSAEpilogueStatement(register: SSAName(register: .segment(.es))),
        SSAEpilogueStatement(register: SSAName(register: .segment(.cs))),
        SSAEpilogueStatement(register: SSAName(register: .segment(.ss))),
        SSAEpilogueStatement(register: SSAName(register: .segment(.ds))),
        SSAEpilogueStatement(register: SSAName(register: .segment(.fs))),
        SSAEpilogueStatement(register: SSAName(register: .segment(.gs))),
    ]
}
