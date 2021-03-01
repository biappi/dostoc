//
//  File.swift
//  
//
//  Created by Antonio Malara on 28/02/21.
//

import Foundation

// A Simple, Fast Dominance Algorithm
// Keith D. Cooper, Timothy J. Harvey, and Ken Kennedy

// https://www.cs.rice.edu/~keith/EMBED/dom.pdf

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

func postorderVisit<G: Graph>(graph: G, start: G.NodeId) -> [G.NodeId] {
    var visited = Set<G.NodeId>()

    var visit = [G.NodeId]()
    
    func dfs(node: G.NodeId) {
        visited.insert(node)
        
        for i in graph.successors(of: node) {
            if !visited.contains(i) {
                dfs(node: i)
            }
        }
        
        visit.append(node)
    }
    
    dfs(node: start)
    return visit
}

// Figure 3

func dominators<G: Graph>(graph: G) -> [G.NodeId : G.NodeId] {
    var doms = [G.NodeId : G.NodeId]()

    doms[graph.start] = graph.start
    var changed = true
    
    let reversePostorder = postorderVisit(graph: graph, start: graph.start)
    var nodesToPostorderIndex = [G.NodeId : Int]()
    
    for (i, nodeId) in reversePostorder.enumerated() {
        nodesToPostorderIndex[nodeId] = i
    }
    
    while changed {
        changed = false
                
        for b in reversePostorder {
            if b == graph.start {
                continue
            }
            
            var newIdom: G.NodeId? = nil
            
            for p in graph.predecessors(of: b) {
                if doms[p] == nil {
                    continue
                }
                
                if newIdom == nil {
                    newIdom = p
                }
                
                newIdom = intersect(
                    graph: graph,
                    b1: p,
                    b2: newIdom!,
                    doms: doms,
                    nodesToIndexes: nodesToPostorderIndex,
                    indexesToNodes: reversePostorder
                )
            }
            
            if doms[b] != newIdom {
                doms[b] = newIdom
                changed = true
            }
        }
    }
    
    return doms
}

func intersect<G: Graph>(
    graph: G,
    b1: G.NodeId,
    b2: G.NodeId,
    doms: [G.NodeId : G.NodeId],
    nodesToIndexes: [G.NodeId : Int],
    indexesToNodes: [G.NodeId]
) -> G.NodeId
{
    var finger1 = nodesToIndexes[b1]!
    var finger2 = nodesToIndexes[b2]!
    
    while finger1 != finger2 {
        while finger1 < finger2 {
            finger1 = nodesToIndexes[doms[indexesToNodes[finger1]]!]!
        }
        
        while finger2 < finger1 {
            finger2 = nodesToIndexes[doms[indexesToNodes[finger2]]!]!
        }
    }
    
    return indexesToNodes[finger1]
}

// Figure 5

func dominanceFrontier<G: Graph>(
    graph: G,
    doms: [G.NodeId : G.NodeId]
) -> [G.NodeId : [G.NodeId]]
{
    var frontiers = [G.NodeId : [G.NodeId]]()
    
    for b in graph.nodes {
        let preds = graph.predecessors(of: b)
        if preds.count >= 2 {
            for p in preds {
                var runner = p
                
                while runner != doms[b] {
                    frontiers[runner, default:[]].append(b)
                    runner = doms[runner]!
                }
            }
        }
    }
    
    return frontiers
}
