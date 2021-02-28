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
    var ssa: SSAName { SSAName(name: "\(base)", index: index) }

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
        
        typealias SSAStatementBlock = [(Instruction?, [SSAStatement])]
        
        var registers = MachineRegisters(number: 0)
        
        var ssaBlocks = [UInt64 : SSAStatementBlock]()
        var varsDefined = [UInt64 : [String : Int]]()
        
        let doms = dominators(graph: cfg)
        let frontier = dominanceFrontier(graph: cfg, doms: doms)
        
        //         at block  varname   from block, idx
        var phis = [UInt64 : [String : [UInt64 : Int]]]()
        
        cfg.visit {
            block in
                                    
            registers.defined = [:]
            
            ssaBlocks[block.start] = block.instructions.map { insn in
                (insn, convert(insn: insn, registers: &registers))
            }
            
            varsDefined[block.start] = registers.defined
            
            for frontierBlock in frontier[block.start] ?? [] {
                for (variableName, variableIndex) in registers.defined {
                    phis[frontierBlock, default: [:]][variableName, default: [:]][block.start] = variableIndex
                }
            }
        }
        
        var i = 0
        cfg.visit {
            cfgblock in
            
            let backlinks = cfgblock.backlinks.map { $0.hexString }.joined(separator: ", ")

            print("Block \(i) - (\(backlinks))")
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

    mutating func convert(insn: Instruction, registers: inout MachineRegisters) -> [SSAStatement] {
        let op0 = insn.operands.0
        let op1 = insn.operands.1

//        print(insn.asm)
        
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
                assert(insn.prefixSegment == nil)
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
            else if op0.operandType == .mem && op1.operandType == .reg {
                let seg  = insn.prefixSegment.map { "\($0):"} ?? ""
                let name = "\(seg)\(op0.registerName.designation)"
                
                return [
                    SSAAssignmentStatement(
                        assign: SSARegExpression(name: registers.last(op1.registerName.designation)),
                        to: SSASegmentedMemoryVariable(address: name)
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
                SSAAssignmentStatement(
                    assign: SSASumExpression(
                        lhs: SSARegExpression(name: registers.last(op0.registerName.designation)),
                        rhs: SSAConstExpression(value: Int(op1.uint64value))
                    ),
                    to: SSARegVariable(name: registers.new(op0.registerName.designation))
                )
            ]

        case UD_Isub:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .reg)
            
            return [
                SSAAssignmentStatement(
                    assign: SSADiffExpression(
                        lhs: SSARegExpression(name: registers.last(op0.registerName.designation)),
                        rhs: SSARegExpression(name: registers.last(op1.registerName.designation))
                    ),
                    to: SSARegVariable(name: registers.new(op0.registerName.designation))
                )
            ]
            
        case UD_Imul:
            assert(op0.operandType == .reg)
            
            return [
                SSAAssignmentStatement(
                    assign: SSAMulExpression(
                        lhs: SSARegExpression(name: registers.last(op0.registerName.designation)),
                        rhs: SSARegExpression(name: registers.last(op1.registerName.designation))
                    ),
                    to: SSARegVariable(name: registers.new(op0.registerName.designation))
                )
            ]

        case UD_Ishr:
            assert(op0.operandType == .reg)
            assert(op1.operandType == .const)
            
            return [
                SSAAssignmentStatement(
                    assign: SSAShiftRight(
                        lhs: SSARegExpression(name: registers.last(op0.registerName.designation)),
                        rhs: SSAConstExpression(value: Int(op1.uint64value))
                    ),
                    to: SSARegVariable(name: registers.new(op0.registerName.designation))
                )
            ]

        case UD_Iinc:
            assert(op0.operandType == .reg)
            
            return [
                SSAAssignmentStatement(
                    assign: SSASumExpression(
                        lhs: SSARegExpression(name: registers.last(op0.registerName.designation)),
                        rhs: SSAConstExpression(value: 1)
                    ),
                    to: SSARegVariable(name: registers.new(op0.registerName.designation))
                )
            ]

        case UD_Idec:
            assert(op0.operandType == .reg)
            
            return [
                SSAAssignmentStatement(
                    assign: SSADiffExpression(
                        lhs: SSARegExpression(name: registers.last(op0.registerName.designation)),
                        rhs: SSAConstExpression(value: 1)
                    ),
                    to: SSARegVariable(name: registers.new(op0.registerName.designation))
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
