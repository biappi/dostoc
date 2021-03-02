//
//  CFG.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

extension UInt64 {
    var hexString: String {
        return String(format: "%x", self)
    }
}

extension FlowType {
    var shouldBreakBasicBlock: Bool { self == .jmp || self == .jcc }
}

struct CFGBlock {
    var instructions = [Instruction]()
    
    mutating func add(instruction: Instruction) {
        instructions.append(instruction)
    }
    
    var startInstruction: Instruction {
        return instructions.first!
    }

    var endInstruction: Instruction {
        return instructions.last!
    }
    
    var start: UInt64 {
        startInstruction.offset
    }
    
    var end: [UInt64] {
        endInstruction.branches.asList
    }
}

struct CFGGraph: Graph {
    let start:  UInt64
    let blocks: [UInt64 : CFGBlock]
    let predecessors: [UInt64 : [UInt64]]
    
    var nodes: [UInt64] { Array(blocks.keys) }
    
    init(from xrefAnalisys: InstructionXrefs) {
        var blocks = [UInt64 : CFGBlock]()
        var currentBlock: UInt64? = xrefAnalisys.start
        
        for addr in xrefAnalisys.insns.keys.sorted() {
            let insn = xrefAnalisys.insns[addr]!
                        
            if xrefAnalisys.xrefs[addr] != nil {
                currentBlock = addr
            }
            
            if currentBlock == nil {
                currentBlock = addr
            }
            
            blocks[currentBlock!, default: CFGBlock()].add(instruction: insn)
            
            if insn.flowType.shouldBreakBasicBlock {
                currentBlock = nil
            }
        }
        
        var predecessors = [UInt64 : [UInt64]]()
        
        for (addr, block) in blocks {
            for end in block.end {
                predecessors[end, default: []].append(addr)
            }
        }
        
        self.start = xrefAnalisys.start
        self.blocks = blocks
        self.predecessors = predecessors
    }

    func predecessors(of node: UInt64) -> [UInt64] {
        return predecessors[node] ?? []
    }
    
    func successors(of node: UInt64) -> [UInt64] {
        return blocks[node]!.end
    }
    
    func dump() {
        print("CFG")
        print("    start: \(start.hexString)")
        print("    blocks: \(blocks.count)")
        
        let sortedBlocks = blocks
            .sorted { $0.key < $1.key }
            .map { $0.value }
        
        for block in sortedBlocks  {
            let forward = block.end.map { "\"\($0.hexString)\"" }.joined(separator: ", ")
            print("\t\t\"\(block.start.hexString)\" -> \(forward)")
        }
        
        print()
        
        for block in sortedBlocks  {
            let backwards = predecessors(of: block.start).map { $0.hexString }.joined(separator: ", ")
            print("\t\t\(block.start.hexString) <- \(backwards) ")
        }
        
        print()
        
        print("---")
        print("")
    }
    
    func visit(_ visit: (CFGBlock) -> ()) {
        for nodeId in breadthFirstInOrderVisit(start: start) {
            visit(blocks[nodeId]!)
        }
    }
}
