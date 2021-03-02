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

// Figure 3

func dominators<G: Graph>(graph: G) -> [G.NodeId : G.NodeId] {
    let reversePostorder = graph.depthFirsthPostOrderVisit(start: graph.start)
    var nodesToPostorderIndex = [G.NodeId : Int]()
    
    for (i, nodeId) in reversePostorder.enumerated() {
        nodesToPostorderIndex[nodeId] = i
    }
    
    var doms = [G.NodeId : G.NodeId]()
    doms[graph.start] = graph.start

    let intersect = { (b1: G.NodeId, b2: G.NodeId) -> G.NodeId in
        var finger1 = nodesToPostorderIndex[b1]!
        var finger2 = nodesToPostorderIndex[b2]!
        
        while finger1 != finger2 {
            while finger1 < finger2 {
                finger1 = nodesToPostorderIndex[doms[reversePostorder[finger1]]!]!
            }
            
            while finger2 < finger1 {
                finger2 = nodesToPostorderIndex[doms[reversePostorder[finger2]]!]!
            }
        }
        
        return reversePostorder[finger1]
    }

    var changed = true
    
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
                
                newIdom = intersect(p, newIdom!)
            }
            
            if doms[b] != newIdom {
                doms[b] = newIdom
                changed = true
            }
        }
    }
    
    return doms
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
