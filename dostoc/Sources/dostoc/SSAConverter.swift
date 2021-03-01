//
//  SSAConverter.swift
//  
//
//  Created by Antonio Malara on 27/02/21.
//

import Foundation
import udis86

struct VariableName {
    let base: String
    let block: Int
    let index: Int
    
    var string: String { "\(base)_\(index)" }
    
    var ssa: SSAName {
        SSAName(name: "\(base)", index: index)
    }

}

struct MachineRegisters {
    let number: Int
    
    var unnbound = [VariableName]()
    var regIndexes = [String : Int]()

    var defined = [String: Int]()
    
    mutating func last(_ name: String) -> VariableName {
        if let index = regIndexes[name] {
            return VariableName(base: name, block: number, index: index)
        }
        else {
            let variable = VariableName(base: name, block: number, index: 0)
            unnbound.append(variable)
            regIndexes[name] = 0
            return variable
        }
    }
    
    mutating func new(_ name: String) -> VariableName {
        let index = regIndexes[name, default: -1]
        regIndexes[name] = index + 1
        let v =  VariableName(base: name, block: number, index: index + 1)
        defined[name] = v.index
        return v
    }

    mutating func last(_ designation: RegisterName.Designations) -> SSAName {
        return last("\(designation)").ssa
    }

    mutating func new(_ designation: RegisterName.Designations) -> SSAName {
        return new("\(designation)").ssa
    }

    mutating func lastTemp() -> SSAName {
        return last("temp").ssa
    }

    mutating func new() -> SSAName {
        return new("temp").ssa
    }
    
}

extension RegisterName {
    var ssa: SSAName { designation.ssa }
}

extension RegisterName.Designations {
    var ssa: SSAName { SSAName(name: "\(self)") }
}

typealias SSAStatementBlock = [(Instruction?, [SSAStatement])]

struct Converter {
    
    let cfg: CFGGraph
    
    var ssaBlocks = [UInt64 : SSAStatementBlock]()
    var doms = [UInt64 : UInt64]()
    var frontier = [UInt64 : [UInt64]]()
    
    fileprivate func printBlockStatements(_ blockStatements: [(Instruction?, [SSAStatement])]) {
        for (insn, ssa) in blockStatements {
            for (i, stmt) in ssa.enumerated() {
                let dump = stmt.dump
                
                if i == 0 {
                    let width = 40
                    let spc = String(repeating: " ", count: width - dump.count)
                    
                    let asm = insn?.asm ?? ""
                    let spc2 = String(repeating: " ", count: width - asm.count)
                    
                    let vars = stmt.variables.map { $0.dump }.joined(separator: ", ")
                    print("\t\(dump)\(spc)\(asm)\(spc2)\(vars)")
                }
                else {
                    let width = 80
                    let spc2 = String(repeating: " ", count: width - dump.count)
                    let vars = stmt.variables.map { $0.dump }.joined(separator: ", ")

                    print("\t\(dump)\(spc2)\(vars)")
                }
            }
        }
    }
    
    func variablesModifiedForNodes() -> [CFGGraph.NodeId : Set<SSAName>] {
        let variablesModifiedIn = { (ssaBlock: SSAStatementBlock) -> Set<SSAName> in
            Set(
                ssaBlock
                    .flatMap { $0.1 }
                    .compactMap { $0 as? SSAVariableAssignmentStatement }
                    .compactMap { $0.name }
            )
        }

        
        var variablesModifiedInNodes = [CFGGraph.NodeId : Set<SSAName>]()
        
        for (nodeId, ssaBlock) in ssaBlocks {
            variablesModifiedInNodes[nodeId] = variablesModifiedIn(ssaBlock)
        }
        
        return variablesModifiedInNodes
    }
    
    func allVariables() -> Set<SSAName> {
        return Set(
            ssaBlocks
                .flatMap { $0.value }
                .flatMap { $0.1 }
                .flatMap { $0.variables }
        )
    }
    
    mutating func insertPhiNode(for variable: SSAName, at node: UInt64) {
        let phi = SSAPhiAssignmentStatement(
            name: variable.name,
            phis: Array(
                repeating: (0, 0),
                count: cfg.predecessors(of: node).count
            )
        )
        
        let oldBlock = ssaBlocks[node]!
        let newBlock = [(nil, [phi])] + oldBlock
        ssaBlocks[node] = newBlock
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
    
    mutating func convert() {
        
        doms = dominators(graph: cfg)
        frontier = dominanceFrontier(graph: cfg, doms: doms)
        
        //         at block  varname   from block, idx
//        var phis = [UInt64 : [String : [UInt64 : Int]]]()
        
        cfg.visit {
            block in
                                                
            ssaBlocks[block.start] = block.instructions.map { insn in
                (insn, convert(insn: insn))
            }
            
//            for frontierBlock in frontier[block.start] ?? [] {
//                for (variableName, variableIndex) in registers.defined {
//                    phis[frontierBlock, default: [:]][variableName, default: [:]][block.start] = variableIndex
//                }
//            }
        }
        
        placePhis()
        
        var i = 0
        cfg.visit {
            cfgblock in
            
            let backlinks = cfgblock.backlinks.map { $0.hexString }.joined(separator: ", ")
            let fwdlinks = cfgblock.end.map { $0.hexString }.joined(separator: ", ")

            print("Block \(i) [\(cfgblock.start.hexString)] - (\(backlinks)) --> (\(fwdlinks))")
            print()
            
//            print(phis[cfgblock.start])
            
            print()
            printBlockStatements(ssaBlocks[cfgblock.start]!)
            print()
            
//            print("    Variables:")
//            print("       ", varsDefined[cfgblock.start]!)
//            print("    Need to be in frontier")
//            print("       ", frontier[cfgblock.start] ?? [])
//            print()

            i += 1
        }
    }

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
            assert(op0.operandType == .reg)
            
            return [
                SSAVariableAssignmentStatement(
                    name: op0.registerName.ssa,
                    expression: SSAMulExpression(
                        lhs: SSARegExpression(name: op0.registerName.ssa),
                        rhs: SSARegExpression(name: op1.registerName.ssa)
                    )
                )
            ]

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
