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
    
//    var string: String { "\(base)_\(block)_\(index)" }
//    var ssa: SSAName { SSAName(name: "\(base)_\(block)", index: index) }

    var string: String { "\(base)_\(index)" }
    var ssa: SSAName { SSAName(name: "\(base)", index: index) }

}

struct MachineRegisters {
    let number: Int
    
    var unnbound = [VariableName]()
    var regIndexes = [String : Int]()

    var defined = [VariableName]()
    
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
        defined.append(v)
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

struct Converter {
    
    let cfg: CFGGraph
    
    var statements = [SSAStatement]()

    fileprivate func printBlockStatements(_ blockStatements: [(Instruction?, [SSAStatement])]) {
        for (insn, ssa) in blockStatements {
            for (i, stmt) in ssa.enumerated() {
                let dump = stmt.dump
                
                if i == 0 {
                    let width = 40
                    let spc = String(repeating: " ", count: width - dump.count)
                    
                    print("\t\(dump)\(spc)\(insn?.asm ?? "")")
                }
                else {
                    print("\t\(dump)")
                }
            }
        }
    }
    
    mutating func convert() {
        
        var blockNr = 0

        struct SSABlock {
            var blockNr: Int
            var blockName: String
            var blockStart: UInt64
            
            var cfgBlockBacklinks: [UInt64]
            var cfgBlockForwardlinks: [UInt64]
            var ssaBlockBacklinks: [Int]
            var ssaBlockForwardlinks: [Int]
            
            var blockStatements: [(Instruction?, [SSAStatement])]
        }
        
        var ssaBlocks = [Int : SSABlock]()
        var cfgToSsa = [UInt64 : Int]()
        var ssaToCfg = [Int : UInt64]()
            
        var registers = MachineRegisters(number: blockNr)

        var phisForDescendants = [Int : [Int : [VariableName] ]]()
        
        cfg.visit {
            block in
            
            // variablename -> [(parent, parentidx) ...]
            var variables = [String : [(Int, Int)]]()
            
            if let myPhis = phisForDescendants[block.index] {
                for (parent, parentVariables) in myPhis {
                    for parentVariable in parentVariables {
                        variables[parentVariable.base, default: []]
                            .append((parent, parentVariable.index))
                    }
                }
            }
            
            var phiStats = [SSAStatement]()
            
            for (name, parentvars) in variables {
                phiStats.append(
                    SSAAssignmentStatement(
                        assign: SSAPhiExpression(name: name, variables: parentvars),
                        to: SSARegVariable(name: registers.new(name).ssa)
                    )
                )
            }
            
            registers.defined = []

            let insnsStatements = block.instructions.map { insn in
                (insn, convert(insn: insn, registers: &registers))
            }
            
            let blockStatements = [(nil, phiStats)] + insnsStatements
            
            ssaBlocks[blockNr] = SSABlock(
                blockNr: blockNr,
                blockName: String(format: "loc_%x:", block.start),
                blockStart: block.start,
                
                cfgBlockBacklinks: block.backlinks,
                cfgBlockForwardlinks: block.end,
                ssaBlockBacklinks: [],
                ssaBlockForwardlinks: [],
                                
                blockStatements: blockStatements
            )
                        
            for i in cfg.blocks[block.start]!.end {
                let idx = cfg.blocks[i]!.index
                phisForDescendants[idx, default: [:]][block.index] = registers.defined
            }
            
            ssaToCfg[blockNr] = block.start
            cfgToSsa[block.start] = blockNr
            
            blockNr += 1
        }
        
        for blockNr in ssaBlocks.keys {
            ssaBlocks[blockNr]!.ssaBlockBacklinks
                = ssaBlocks[blockNr]!.cfgBlockBacklinks.map { cfgToSsa[$0]! }
            
            ssaBlocks[blockNr]!.ssaBlockForwardlinks
                = ssaBlocks[blockNr]!.cfgBlockForwardlinks.map { cfgToSsa[$0]! }
        }
        
        
        Visit(
            root: 0,
            edges: { ssaBlocks[$0]!.ssaBlockForwardlinks }
        ) { ssaNode in
            
            let ssaBlock = ssaBlocks[ssaNode]!
            
            let backlinks = ssaBlock.cfgBlockBacklinks.map { $0.hexString }.joined(separator: ", ")
            
            print("Block \(ssaBlock.blockNr) - \(ssaBlock.blockName) (\(backlinks))")
            print()
            printBlockStatements(ssaBlock.blockStatements)
            print()

//            for (p, phis) in zip(ssaBlock.ssaBlockBacklinks, ssaBlock.phis) {
//                print("\t\(p): \(phis)")
//            }
            
//            print("Variables defined here")
            
//            ssaBlock
//                .blockStatements
//                .flatMap { $0.1 }
//                .compactMap { $0 as? SSAAssignmentStatement}
//                .compactMap { $0.variable as? SSARegVariable }
//                .map { $0.name }
//                .forEach {
//                    print($0)
//                }
            
//            print()
//            print("\t\(ssaBlock.registers.regIndexes)")
//            print()
        }
    }

    mutating func convert(insn: Instruction, registers: inout MachineRegisters) -> [SSAStatement] {
        let op0 = insn.operands.0
        let op1 = insn.operands.1

        switch insn.mnemonic {
        
        case UD_Ipush:
            assert(op0.operandType == .reg)
            
            return [
                SSAAssignmentStatement(
                    assign: SSARegExpression(name: registers.last(op0.registerName.designation)),
                    to:     SSAMemoryVariable(name: registers.last(.sp))
                ),
                SSAAssignmentStatement(
                    assign: SSADiffExpression(
                        lhs: SSARegExpression(name: registers.last(.sp)),
                        rhs: SSAConstExpression(value: 2)
                    ),
                    to:     SSARegVariable(name: registers.new(.sp))
                )
            ]
            
        case UD_Ipop:
            assert(op0.operandType == .reg)
            return [
                SSAAssignmentStatement(
                    assign: SSASumExpression(
                        lhs: SSARegExpression(name: registers.last(.sp)),
                        rhs: SSAConstExpression(value: 2)
                    ),
                    to: SSARegVariable(name: registers.new(.sp))
                ),
                SSAAssignmentStatement(
                    assign: SSAMemoryExpression(name: registers.last(.sp)),
                    to: SSARegVariable(name: registers.new(op0.registerName.designation))
                )
            ]
            
        case UD_Imov:
            if op0.operandType == .reg && op1.operandType == .reg {
                return [
                    SSAAssignmentStatement(
                        assign: SSARegExpression(name: registers.last(op1.registerName.designation)),
                        to: SSARegVariable(name: registers.new(op0.registerName.designation))
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .mem {
                assert(insn.pfx_seg == 0)
                let op1mem = MemoryOperand(op1)
                return [
                    SSAAssignmentStatement(
                        assign: SSASumExpression(
                            lhs: SSARegExpression(name: registers.last(op1mem.base.designation)),
                            rhs: SSAConstExpression(value: Int(op1mem.offset))
                        ),
                        to: SSARegVariable(name: registers.new())
                    ),
                    SSAAssignmentStatement(
                        assign: SSAMemoryExpression(name: registers.lastTemp()),
                        to: SSARegVariable(name: registers.new(op0.registerName.designation))
                    )
                ]
            }
            else if op0.operandType == .reg && op1.operandType == .imm {
                return [
                    SSAAssignmentStatement(
                        assign: SSAConstExpression(value: Int(op1.uint64value)),
                        to: SSARegVariable(name: registers.new(op0.registerName.designation))
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
            
            let offset = insn.pc + op0.int64value
            let label = SSALabel(target: String(format: "loc_%x", offset))
            
            return [
                SSAJmpStatement(type: "jae", target: label)
            ]
            
        case UD_Iretf:
            return [SSAEndStatement()]
            
        default:
            fatalError()
        }
    }
    
}
