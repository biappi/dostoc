//
//  CFA.swift
//  
//
//  Created by Antonio Malara on 13/03/21.
//

import Foundation

func structureCFG(cfg: CFGGraph) {
    let (preOrderId,    postOrderId   ) = visit(cfg: cfg, reverse: false)
    let (revPreOrderId, revPostOrderId) = visit(cfg: cfg, reverse: true)
    
    
}

typealias VisitResult = [CFGGraph.NodeId : Int]

func visit(cfg: CFGGraph, reverse: Bool) -> (preOrderId: VisitResult, postOrderId: VisitResult) {
    var preOrderId = [CFGGraph.NodeId : Int]()
    var postOrderId = [CFGGraph.NodeId : Int]()
    
    var time = 0
    
    var visited = Set<CFGGraph.NodeId>()
    
    func visit(node: CFGGraph.NodeId) {
        visited.insert(node)
        preOrderId[node] = time
        
        let successors = reverse
            ? cfg.successors(of: node)
            : cfg.successors(of: node).reversed()
        
        for succ in successors {
            if !visited.contains(succ) {
                time += 1
                visit(node: succ)
            }
        }
        
        time += 1
        postOrderId[node] = time
    }
    
    visit(node: cfg.start)
    return (preOrderId, postOrderId)
}
