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
    let start: UInt64
    
    var instructions = [Instruction]()
    
    mutating func add(instruction: Instruction) {
        instructions.append(instruction)
    }
}

struct CFGGraph: Graph {
    let realStart:  UInt64
    let blocks: [UInt64 : CFGBlock]
    
    let successors:   [UInt64 : [UInt64]]
    let predecessors: [UInt64 : [UInt64]]
    
    var nodes: [UInt64] { Array(blocks.keys) }

    var start: UInt64 { CFGGraph.synteticStart }
    var end: UInt64 { CFGGraph.synteticEnd }

    static var synteticStart: UInt64 { 0xffffffffffffffff }
    static var synteticEnd: UInt64 { 0xfffffffffffffffe }
    
    init(from xrefAnalisys: InstructionXrefs) {
        var blocks = [UInt64 : CFGBlock]()
        var currentBlock: UInt64? = xrefAnalisys.start
        
        var predecessors = [UInt64 : [UInt64]]()
        var successors   = [UInt64 : [UInt64]]()
        
        for addr in xrefAnalisys.insns.keys.sorted() {
            let insn = xrefAnalisys.insns[addr]!
                        
            if xrefAnalisys.xrefs[addr] != nil {
                currentBlock = addr
            }
            
            if currentBlock == nil {
                currentBlock = addr
            }
            
            blocks[currentBlock!, default: CFGBlock(start: addr)].add(instruction: insn)
            
            if insn.flowType.shouldBreakBasicBlock {
                currentBlock = nil
            }
        }
        
        for (addr, block) in blocks {
            let tails = block.instructions.last!.branches.asList
            
            successors[addr] = tails
            
            for end in tails {
                predecessors[end, default: []].append(addr)
            }
        }
        
        successors[CFGGraph.synteticStart, default: []].append(xrefAnalisys.start)
        predecessors[xrefAnalisys.start, default: []].append(CFGGraph.synteticStart)

        for n in blocks.keys {
            if successors[n]?.isEmpty == false {
                successors[n, default: []].append(CFGGraph.synteticEnd)
                predecessors[CFGGraph.synteticEnd, default: []].append(n)
            }
        }
        
        blocks[CFGGraph.synteticStart] = CFGBlock(start: CFGGraph.synteticStart)
        blocks[CFGGraph.synteticEnd] = CFGBlock(start: CFGGraph.synteticEnd)
        
        self.realStart = xrefAnalisys.start
        self.blocks = blocks
        self.predecessors = predecessors
        self.successors = successors
    }

    func predecessors(of node: UInt64) -> [UInt64] {
        return predecessors[node] ?? []
    }
    
    func successors(of node: UInt64) -> [UInt64] {
        return successors[node] ?? []
    }
    
    func dump() {
        print("CFG")
        print("    start: \(start.hexString)")
        print("    blocks: \(blocks.count)")
        
        let sortedBlocks = blocks
            .sorted { $0.key < $1.key }
            .map { $0.value }
        
        for block in sortedBlocks  {
            let forward = successors(of: block.start).map { "\"\($0.hexString)\"" }.joined(separator: ", ")
            print("\t\t\"\(block.start.hexString)\" -> \(forward);")
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
