//
//  SSAConverter.swift
//  
//
//  Created by Antonio Malara on 27/02/21.
//

import Foundation
import udis86

/*
struct VariableName {
    let base: String
    let block: Int
    let index: Int
    
    var string: String { "\(base)_\(block)_\(index)" }
}
*/

struct MachineRegisters {
    let number: Int
    
    var unnbound = [SSAName]()
    var regIndexes = [String : Int]()

    private mutating func last(_ baseName: String) -> SSAName {
        let name = "\(baseName)_\(number)"
        
        if let index = regIndexes[name] {
            return SSAName(name: name, index: index)
        }
        else {
            let variable = SSAName(name: name, index: 0)
            unnbound.append(variable)
            regIndexes[name] = 1
            return variable
        }
    }
    
    private mutating func new(_ baseName: String) -> SSAName {
        let name = "\(baseName)_\(number)"

        let index = regIndexes[name, default: -1]
        regIndexes[name] = index + 1
        return SSAName(name: name, index: index + 1)
    }

    mutating func last(_ designation: RegisterName.Designations) -> SSAName {
        return last("\(designation)")
    }

    mutating func new(_ designation: RegisterName.Designations) -> SSAName {
        return new("\(designation)")
    }

    mutating func lastTemp() -> SSAName {
        return last("temp")
    }

    mutating func new() -> SSAName {
        return new("temp")
    }
    
}

struct Converter {
    
    let cfg: CFGGraph
    
    var registers  = MachineRegisters(number: 0)
    var statements = [SSAStatement]()

    mutating func convert() {
        
        for (blockNr, block) in cfg.sortedBlocks().enumerated() {
            registers = MachineRegisters(number: blockNr)
            let blockStatements = block.instructions.map { ($0, convert(insn:$0)) }
            
            let blockName = String(format: "loc_%x:", block.start)
                                   
            let unbound = registers.unnbound.map { $0.dump }.joined(separator: ", ")
            print("Block \(blockNr) -  \(blockName) -- Unbound: [\(unbound)]")
            print()
            
            for (insn, ssa) in blockStatements {
                for (i, stmt) in ssa.enumerated() {
                    let dump = stmt.dump
                    
                    if i == 0 {
                        let width = 30
                        let spc = String(repeating: " ", count: width - dump.count)
                        
                        print("\t\(dump)\(spc)\(insn.asm)")
                    }
                    else {
                        print("\t\(dump)")
                    }
                }
            }
        
            print()
            print("\t\(registers.regIndexes)")
            print()
        }
    }

    mutating func convert(insn: Instruction) -> [SSAStatement] {
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
