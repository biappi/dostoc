//
//  Graph.swift
//  
//
//  Created by Antonio Malara on 02/03/21.
//

import Foundation

protocol Graph
    where Nodes: Collection,
          Nodes.Element == NodeId,
          NodeId: Hashable
{
    associatedtype NodeId
    associatedtype Nodes
    
    var start: NodeId { get }
    var nodes: Nodes  { get }
    
    func predecessors (of node: NodeId) -> [NodeId]
    func successors   (of node: NodeId) -> [NodeId]
}

extension Graph {
    func breadthFirstInOrderVisit(start: NodeId) -> [NodeId] {
        var visited = Set<NodeId>()
        var queue = [start]
        var visit = [NodeId]()
        
        while !queue.isEmpty {
            let node = queue.removeFirst()
            
            if visited.contains(node) {
                continue
            }
            
            visited.insert(node)
            visit.append(node)
            queue.append(contentsOf: successors(of: node))
        }
        
        return visit
    }
    
    func depthFirsthPostOrderVisit(start: NodeId) -> [NodeId] {
        var visited = Set<NodeId>()
        var visit = [NodeId]()
        
        func dfs(node: NodeId) {
            visited.insert(node)
            
            for i in successors(of: node) {
                if !visited.contains(i) {
                    dfs(node: i)
                }
            }
            
            visit.append(node)
        }
        
        dfs(node: start)
        return visit
    }
}

