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
                .flatMap { $0.variablesDefined }
        )
    }
    
    func dump(deleted: Set<StatementIndex>, blockId: UInt64) {
        let tabled = true
        let showDead = true
        
        let width = 50
        
        let dumpvars = { (stmt: SSAStatement) -> String in
            let toString = { (vars: Set<SSAName>) -> String in
                vars
                    .map { "\($0.dump)" } // ":\($0.size)" }
                    .joined(separator: ", ")
            }
            
            let def = toString(stmt.variablesDefined)
            let ref = toString(stmt.variablesReferenced)
            
            return "\(def) = \(ref)"
        }
        
        for (i, stmt) in phiStatements.enumerated() {
            let dead = deleted.contains(.phi(blockId: blockId, phiNr: i))
            let dood = dead ? "MORTO " : "      "
            let dump = stmt.dump.padding(toLength: width + 30, withPad: " ", startingAt: 0)
            let vars = dumpvars(stmt)
            
            if !showDead && dead {
                continue
            }
            
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
                
                if !showDead && dead {
                    continue
                }

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
                repeating: nil,
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
            let fwdlinks = cfg.successors(of: cfgblock.start).map { $0.hexString }.joined(separator: ", ")

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

        let getIndex = { (variable: String) -> Int? in
            stacks[variable]?.last
        }

        let getIndexOrCreate = { (variable: String) -> Int in
            getIndex(variable) ?? (genName(variable), getIndex(variable)!).1
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
                            index: getIndexOrCreate(variable.name)
                        )
                    }
                    
                    let lhsVariables = ssaGraph.ssaBlocks[block]!.statements[i].1[k].variablesDefined
                    
                    for variable in lhsVariables {
                        genName(variable.name)
                        ssaGraph.ssaBlocks[block]!.statements[i].1[k].renameDefinedVariables(
                            name: variable.name,
                            index: getIndexOrCreate(variable.name)
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
        
    mutating func registersSizes() {
        struct Conversion {
            let index: StatementIndex
            let name: Register.GeneralPurpose
            let kind: Kind
            
            enum Kind {
                case wordToBytes
                case bytesToWord
            }
        }
        
        for (block, _) in ssaGraph.ssaBlocks {
            var lastSizeForRegister = [Register.GeneralPurpose : Int]()
            var conversions = [Conversion]()
            
            ssaGraph.forEachSSAStatementIndex(in: block) { idx in
                let stmt = ssaGraph.statementFor(idx)
                
                for variable in stmt.variablesReferenced {
                    if case .register(let r) = variable.kind,
                       case .gpr(let name, let part) = r
                    {
                        if let lastSize = lastSizeForRegister[name],
                           lastSize != part.byteSize
                        {
                            if lastSize == 2 {
                                conversions.append(
                                    Conversion(
                                        index: idx,
                                        name: name,
                                        kind: .wordToBytes
                                    )
                                )
                            }
                            else if lastSize == 1 {
                                conversions.append(
                                    Conversion(
                                        index: idx,
                                        name: name,
                                        kind: .bytesToWord
                                    )
                                )
                            }
                        }
                        
                        lastSizeForRegister[name] = part.byteSize
                    }
                }
                
                for variable in stmt.variablesDefined {
                    if case .register(let r) = variable.kind,
                       case .gpr(let name, let part) = r
                    {
                        lastSizeForRegister[name] = part.byteSize
                    }
                }
            }
            
            for conversion in conversions.reversed() {
                if case .stmt(let blockId, let insn, _) = conversion.index {
                    switch conversion.kind {
                    
                    case .wordToBytes:
                        let convLow = SSARegisterSplit16to8Statement(
                            name: Register.gpr(conversion.name, .low8).ssa,
                            other: Register.gpr(conversion.name, .low16).ssa
                        )
                        
                        let convHigh = SSARegisterSplit16to8Statement(
                            name: Register.gpr(conversion.name, .high8).ssa,
                            other: Register.gpr(conversion.name, .low16).ssa
                        )
                        
                        ssaGraph.ssaBlocks[blockId]!.statements.insert((nil, [convLow]), at: insn)
                        ssaGraph.ssaBlocks[blockId]!.statements.insert((nil, [convHigh]), at: insn)
                        
                    case .bytesToWord:
                        let conv = SSARegisterJoin8to16Statement(
                            name: Register.gpr(conversion.name, .low16).ssa,
                            otherLow: Register.gpr(conversion.name, .low8).ssa,
                            otherHigh: Register.gpr(conversion.name, .high8).ssa
                        )
                        
                        ssaGraph.ssaBlocks[blockId]!.statements.insert((nil, [conv]), at: insn)
                    }
                }
            }
        }
    }
    
    mutating func assignmentsToZero() {
        for (block, _) in ssaGraph.ssaBlocks {
            ssaGraph.forEachSSAStatementIndex(in: block) { idx in
                let stmt = ssaGraph.statementFor(idx)
                
                if
                    let assignment = stmt as? SSABinaryOpStatement,
                    assignment.op == .diff || assignment.op == .xor,
                    case .reg(let lhs) = assignment.lhs,
                    case .reg(let rhs) = assignment.rhs,
                    lhs == rhs,
                    case .stmt(let blockId, let insn, let s) = idx
                {
                    ssaGraph.ssaBlocks[blockId]!.statements[insn].1[s] =
                        SSAConstAssignmentStatement(
                            name: assignment.result,
                            const: 0
                        )
                }
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
        assignmentsToZero()
        placePhis()
        registersSizes()
        rename()
        deadCodeElimination()
        
        ssaGraph.dump(deleted: deleted)
    }
}

extension SSABlock {
    static var temper_i = 0
    
    mutating func convert(insn: Instruction) -> [SSAStatement] {
        let op0 = insn.operands.0
        let op1 = insn.operands.1
        
        let temper = { (n: String) -> SSAName in
            SSABlock.temper_i += 1
            return SSAName(name: n)// "T\(SSABlock.temper_i)_\(n)")
        }
        
        print(insn.asm)
        
        switch insn.mnemonic {
        
        case UD_Ipush:
            assert(op0.operandType == .reg)
            let tempName = temper("addr")
            
            return [
                SSAMemoryAddressResolver(
                    name: tempName,
                    addressing: Addressing.stackPointer
                ),
                SSAMemoryWriteStatement(
                    address: tempName,
                    value: op0.registerName.ssa
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
            let tempName = temper("addr")
            
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
                    name: op0.registerName.ssa,
                    address: tempName
                ),
            ]
            
        case UD_Imov:
            if op0.operandType == .reg && op1.operandType == .reg {
                return [
                    SSAVariableAssignmentStatement(
                        name: op0.registerName.ssa,
                        value: op1.registerName.ssa
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .mem {
                let tempName = temper("addr")
                
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
                    SSAConstAssignmentStatement(
                        name: op0.registerName.ssa,
                        const: Int(op1.uint64value)
                    )
                ]
            }
            else if op0.operandType == .mem && op1.operandType == .reg {
                let tempName = temper("addr")
                
                return [
                    SSAMemoryAddressResolver(
                        name: tempName,
                        addressing: Addressing(insn, op0)
                    ),
                    SSAMemoryWriteStatement(
                        address: tempName,
                        value: op1.registerName.ssa
                    )
                ]
            }
            else if op0.operandType == .mem && op1.operandType == .imm {
                let address = temper("addr")
                let val = temper("val")
                
                return [
                    SSAConstAssignmentStatement(
                        name: val,
                        const: Int(op1.uint64value)
                    ),
                    SSAMemoryAddressResolver(
                        name: address,
                        addressing: Addressing(insn, op0)
                    ),
                    SSAMemoryWriteStatement(
                        address: address,
                        value: val
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

        case UD_Ija:    return Jump(insn: insn, type: "ja")
        case UD_Ijae:   return Jump(insn: insn, type: "jae")
        case UD_Ijb:    return Jump(insn: insn, type: "jb")
        case UD_Ijbe:   return Jump(insn: insn, type: "jbe")
        case UD_Ijcxz:  return Jump(insn: insn, type: "jcxz")
        case UD_Ijecxz: return Jump(insn: insn, type: "jecxz")
        case UD_Ijg:    return Jump(insn: insn, type: "jg")
        case UD_Ijge:   return Jump(insn: insn, type: "jge")
        case UD_Ijl:    return Jump(insn: insn, type: "jl")
        case UD_Ijle:   return Jump(insn: insn, type: "jle")
        case UD_Ijmp:   return Jump(insn: insn, type: "jmp")
        case UD_Ijno:   return Jump(insn: insn, type: "jno")
        case UD_Ijnp:   return Jump(insn: insn, type: "jnp")
        case UD_Ijns:   return Jump(insn: insn, type: "jns")
        case UD_Ijnz:   return Jump(insn: insn, type: "jnz")
        case UD_Ijo:    return Jump(insn: insn, type: "jo")
        case UD_Ijp:    return Jump(insn: insn, type: "jp")
        case UD_Ijrcxz: return Jump(insn: insn, type: "jrcxz")
        case UD_Ijs:    return Jump(insn: insn, type: "js")
        case UD_Ijz:    return Jump(insn: insn, type: "jz")
            
        case UD_Iret:
            return EpilogueStatements()

        case UD_Iretf:
            return EpilogueStatements()
            
        case UD_Iadd:
            return BinaryOpStatements(insn: insn, op: .sum, temper: temper)
            
        case UD_Isub:
            return BinaryOpStatements(insn: insn, op: .diff, temper: temper)

        case UD_Imul:
            return BinaryOpStatements(insn: insn, op: .mul, temper: temper)

        case UD_Iand:
            return BinaryOpStatements(insn: insn, op: .and, temper: temper)
            
        case UD_Ior:
            return BinaryOpStatements(insn: insn, op: .or, temper: temper)
            
        case UD_Ixor:
            return BinaryOpStatements(insn: insn, op: .xor, temper: temper)

        case UD_Ishr:
            return BinaryOpStatements(insn: insn, op: .shr, temper: temper)

        case UD_Ishl:
            return BinaryOpStatements(insn: insn, op: .shl, temper: temper)
            
        case UD_Iror:
            return BinaryOpStatements(insn: insn, op: .ror, temper: temper)
            
        case UD_Irol:
            return BinaryOpStatements(insn: insn, op: .rol, temper: temper)

        case UD_Ineg:
            if op0.operandType == .reg  {
                return [
                    SSABinaryOpStatement(
                        result: op0.registerName.ssa,
                        op: .mul,
                        lhs: op0.registerName,
                        rhs: -1
                    ),
                    SSAFlagsAssignmentStatement(
                        value: op0.registerName.ssa
                    )
                ]
            }
            else {
                fatalError()
            }

        case UD_Iinc:
            if op0.operandType == .reg {
                return [
                    SSABinaryOpStatement(
                        result: op0.registerName.ssa,
                        op: .sum,
                        lhs: op0.registerName,
                        rhs: Int(1)
                    ),
                    SSAFlagsAssignmentStatement(
                        value: op0.registerName.ssa
                    )
                ]
            }
            else if op0.operandType == .mem {
                let addr = temper("addr")
                let val  = temper("val")
                return [
                    SSAMemoryAddressResolver(
                        name: addr,
                        addressing: insn.op0addressing
                    ),
                    SSAMemoryReadStatement(
                        name: val,
                        address: addr
                    ),
                    SSABinaryOpStatement(
                        result: val,
                        op: .sum,
                        lhs: val,
                        rhs: 1
                    ),
                    SSAMemoryWriteStatement(
                        address: addr,
                        value: val
                    )
                ]
            }
            else {
                fatalError()
            }

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
                    value: op0.registerName.ssa
                ),
                SSAFlagsAssignmentStatement(
                    value: op0.registerName.ssa
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
                    value: Register.gpr(.cx, .low16).ssa
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
                let address = temper("addr")
                let tempName = temper("val")

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
                        value: tempName
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .imm {
                let tempName = temper("val")
                
                return [
                    SSABinaryOpStatement(
                        result: tempName,
                        op: .diff,
                        lhs: op0.registerName,
                        rhs: Int(op1.int64value)
                    ),
                    SSAFlagsAssignmentStatement(
                        value: tempName
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .reg {
                let tempName = temper("val")
                
                return [
                    SSABinaryOpStatement(
                        result: tempName,
                        op: .diff,
                        lhs: op0.registerName,
                        rhs: op1.registerName
                    ),
                    SSAFlagsAssignmentStatement(
                        value: tempName
                    )
                ]
            }

            else if op0.operandType == .mem && op1.operandType == .reg {
                let val = temper("val")
                let addr = temper("addr")
                
                return [
                    SSAMemoryAddressResolver(
                        name: addr,
                        addressing: insn.op0addressing
                    ),
                    SSAMemoryReadStatement(
                        name: val,
                        address: addr
                    ),
                    SSABinaryOpStatement(
                        result: val,
                        op: .diff,
                        lhs: val,
                        rhs: op1.registerName
                    ),
                    SSAFlagsAssignmentStatement(
                        value: val
                    )
               ]
            }
            else if op0.operandType == .reg && op1.operandType == .mem {
                let val = temper("val")
                let addr = temper("addr")
                
                return [
                    SSAMemoryAddressResolver(
                        name: addr,
                        addressing: insn.op1addressing
                    ),
                    SSAMemoryReadStatement(
                        name: val,
                        address: addr
                    ),
                    SSABinaryOpStatement(
                        result: val,
                        op: .diff,
                        lhs: op0.registerName,
                        rhs: val
                    ),
                    SSAFlagsAssignmentStatement(
                        value: val
                    )
               ]
            }
            else {
                fatalError()
            }

        case UD_Iout:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .reg)
            
            return [
                SSAOutStatement(
                    port: op0.registerName.ssa,
                    data: op1.registerName.ssa
                )
            ]
            
        case UD_Ixchg:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .reg)
            
            let temp = temper("val")
            return [
                SSAVariableAssignmentStatement(
                    name: temp,
                    value: op0.registerName.ssa
                ),
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    value: op1.registerName.ssa
                ),
                SSAVariableAssignmentStatement(
                    name: op1.registerName.ssa,
                    value: temp
                ),
            ]
            
        case UD_Ilodsw:
            let addr = temper("addr")
            
            return [
                SSAMemoryAddressResolver(
                    name: addr,
                    addressing: .base(segment: .ds, base: .gpr(.si, .low16))
                ),
                SSAMemoryReadStatement(
                    name: Register.gpr(.ax, .low16).ssa,
                    address: addr
                ),
                SSABinaryOpStatement(
                    result: Register.gpr(.si, .low16).ssa,
                    op: .sum,
                    lhs: .gpr(.si, .low16),
                    rhs: 2
                )
            ]
            
        case UD_Istosw:
            let addr = temper("addr")
            
            return [
                SSAMemoryAddressResolver(
                    name: addr,
                    addressing: .base(segment: .es, base: .gpr(.di, .low16))
                ),
                SSAMemoryWriteStatement(
                    address: addr,
                    value: Register.gpr(.ax, .low16).ssa
                ),
                SSABinaryOpStatement(
                    result: Register.gpr(.si, .low16).ssa,
                    op: .sum,
                    lhs: .gpr(.di, .low16),
                    rhs: 2
                )
            ]
            
        case UD_Istosb:
            let addr = temper("addr")
            
            return [
                SSAMemoryAddressResolver(
                    name: addr,
                    addressing: .base(segment: .es, base: .gpr(.di, .low16))
                ),
                SSAMemoryWriteStatement(
                    address: addr,
                    value: Register.gpr(.ax, .low8).ssa
                ),
                SSABinaryOpStatement(
                    result: Register.gpr(.si, .low16).ssa,
                    op: .sum,
                    lhs: .gpr(.di, .low16),
                    rhs: 1
                )
            ]

            
        case UD_Icli:
            return [ SSACliStatement() ]

        case UD_Isti:
            return [ SSAStiStatement() ]

        case UD_Icld:
            // TODO: direction flag
            return []
            
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

func BinaryOpStatements(
    insn: Instruction,
    op: SSABinaryOpStatement.Operation,
    temper: (String) -> SSAName
) -> [SSAStatement]
{
    let op0 = insn.operands.0
    let op1 = insn.operands.1
    
    if op0.operandType == .reg && op1.operandType == nil {
        return [
            SSABinaryOpStatement(
                result: Register.gpr(.ax, .low16).ssa,
                op: op,
                lhs: op0.registerName,
                rhs: .gpr(.ax, .low16)
            ),
            SSAFlagsAssignmentStatement(
                value: op0.registerName.ssa
            )
        ]
    }
    else if op0.operandType == .reg && op1.operandType == .imm {
        return [
            SSABinaryOpStatement(
                result: op0.registerName.ssa,
                op: op,
                lhs: op0.registerName,
                rhs: Int(op1.uint64value)
            ),
            SSAFlagsAssignmentStatement(
                value: op0.registerName.ssa
            )
        ]
    }
    else if op0.operandType == .reg && op1.operandType == .reg {
        return [
            SSABinaryOpStatement(
                result: op0.registerName.ssa,
                op: op,
                lhs: op0.registerName,
                rhs: op1.registerName
            ),
            SSAFlagsAssignmentStatement(
                value: op0.registerName.ssa
            )
       ]
    }
    else if op0.operandType == .mem && op1.operandType == .reg {
        let val = temper("val")
        let addr = temper("addr")
        
        return [
            SSAMemoryAddressResolver(
                name: addr,
                addressing: insn.op0addressing
            ),
            SSAMemoryReadStatement(
                name: val,
                address: addr
            ),
            SSABinaryOpStatement(
                result: val,
                op: op,
                lhs: val,
                rhs: op1.registerName
            ),
            SSAMemoryWriteStatement(
                address: addr,
                value: val
            ),
            SSAFlagsAssignmentStatement(
                value: val
            )
       ]
    }
    else if op0.operandType == .mem && op1.operandType == .imm {
        let val = temper("val")
        let addr = temper("addr")
        
        return [
            SSAMemoryAddressResolver(
                name: addr,
                addressing: insn.op0addressing
            ),
            SSAMemoryReadStatement(
                name: val,
                address: addr
            ),
            SSABinaryOpStatement(
                result: val,
                op: op,
                lhs: val,
                rhs: Int(op1.uint64value)
            ),
            SSAMemoryWriteStatement(
                address: addr,
                value: val
            ),
            SSAFlagsAssignmentStatement(
                value: val
            )
       ]
    }
    else if op0.operandType == .reg && op1.operandType == .const {
        return [
            SSABinaryOpStatement(
                result: op0.registerName.ssa,
                op: op,
                lhs: op0.registerName,
                rhs: Int(op1.uint64value)
            ),
            SSAFlagsAssignmentStatement(
                value: op0.registerName.ssa
            )
        ]
    }
    else {
        fatalError()
    }
}

func PrologueStatements() -> [SSAStatement] {
    return []
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
    return [SSAEndStatement()]
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
