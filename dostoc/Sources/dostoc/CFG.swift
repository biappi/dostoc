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


class CFGBlock {
    var index = 0
    var instructions = [Instruction]()
    
    func add(instruction: Instruction) {
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
        switch endInstruction.branches {
        case .none:                             return []
        case .jmp (             target: let t): return [t]
        case .jcc (next: let n, target: let t): return [n, t]
        case .call(next: let n, target: _    ): return [n]
        case .seq (next: let n               ): return [n]
        }
    }
    
    var backlinks = [UInt64]()
}


class CFGGraph: Graph {
    var blocks: [UInt64 : CFGBlock]
    var startBlock: CFGBlock
 
    var start:  UInt64  { startBlock.start   }
    var nodes: [UInt64] { Array(blocks.keys) }
    
    init(from insns: InstructionXrefs) {
        blocks = [:]
        startBlock = CFGBlock()
        
        construct(from: insns)
    }
    
    func construct(from insns: InstructionXrefs) {
        blocks[insns.start] = startBlock
        
        var currentBlock: CFGBlock? = startBlock
        
        for addr in anals.insns.keys.sorted() {
            let insn = anals.insns[addr]!
                        
            if insns.xrefs[addr] != nil {
                let newBlock = CFGBlock()
                currentBlock = newBlock
                blocks[addr] = newBlock
            }
            
            if currentBlock == nil {
                let newBlock = CFGBlock()
                currentBlock = newBlock
                blocks[addr] = newBlock
            }

            currentBlock?.add(instruction: insn)
            
            let flow = FlowType(for: insn)
            if flow == .jmp || flow == .jcc {
                currentBlock = nil
            }
        }
        
        var idx = 0
        visit {
            $0.index = idx
            idx += 1
            
            for node in $0.end {
                blocks[node]?.backlinks.append($0.start)
            }
        }

    }

    func predecessors(of node: UInt64) -> [UInt64] {
        return blocks[node]!.backlinks
    }
    
    func successors(of node: UInt64) -> [UInt64] {
        return blocks[node]!.end
    }
    
    func dump() {
        print("CFG")
        print("    start: \(startBlock.start.hexString)")
        print("    blocks: \(blocks.count)")
        
        let sortedBlocks = blocks
            .sorted { $0.key < $1.key }
            .map { $0.value }
        
        for block in sortedBlocks  {
            let forward = block.end.map { "\"\($0)\"" }.joined(separator: ", ")
            print("\t\t\"\(block.start)\" -> \(forward)")
        }
        
        print()
        
        for block in sortedBlocks  {
            let backwards = block.backlinks.map { $0.hexString }.joined(separator: ", ")
            print("\t\t\(block.start.hexString) <- \(backwards) ")
        }
        
        print()
        
        print("---")
        print("")
    }
    
    func visit(_ visit: (CFGBlock) -> ()) {
        for nodeId in breadthFirstInOrderVisit(start: startBlock.start) {
            visit(blocks[nodeId]!)
        }
    }
}
