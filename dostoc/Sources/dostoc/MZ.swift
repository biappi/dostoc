//
//  File.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation

typealias MZHeader = (
    signature:         UInt16,
    extraBytes:        UInt16,
    pages:             UInt16,
    relocationItems:   UInt16,
    headerSize:        UInt16,
    minimumAllocation: UInt16,
    maximumAllocation: UInt16,
    initialSS:         UInt16,
    initialSP:         UInt16,
    checksum:          UInt16,
    initialIP:         UInt16,
    initialCS:         UInt16,
    relocationTable:   UInt16,
    overlay:           UInt16
)

func ParseMZ(data: Data) -> MZHeader {
    return data.withUnsafeBytes {
        $0.bindMemory(to: MZHeader.self).first!
    }

}
