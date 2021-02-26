//
//  UDis.swift
//  
//
//  Created by Antonio Malara on 26/02/21.
//

import Foundation
import udis86

struct Instruction {
    let pc: UInt64
    let mnemonic: ud_mnemonic_code
    let operands: (ud_operand, ud_operand, ud_operand, ud_operand)
    let pfx_seg: UInt8
    
    let offset: UInt64
    let asm: String
}

class UDis86 {
    var ud: ud_t
    let baseAddress: UInt64
    var userData: UserData

    class UserData {
        let data: Data
        var current: UInt64 = 0
        
        init(data: Data) {
            self.data = data
        }
        
        func inputHook() -> Int32 {
            if current == data.count {
                return UD_EOI
            }
            
            let input = data[Int(current)]
            current += 1
            
            return Int32(input)
        }
    }
    
    init(data: Data, base: UInt64 = 0) {
        ud = ud_t()
        baseAddress = base
        userData = UserData(data: data)
        
        ud_init(&ud)
        ud_set_syntax(&ud, ud_translate_intel)
        ud_set_user_opaque_data(&ud, &userData)
    }
    
    func disassemble(addr: UInt64) -> Instruction? {
        ud_set_input_hook(&ud) { (ptr) -> Int32 in
            ud_get_user_opaque_data(ptr)
                .bindMemory(to: UserData.self, capacity: 1)
                .pointee
                .inputHook()
        }
        
        userData.current = addr - baseAddress
        ud_set_pc(&ud, addr)

        if ud_disassemble(&ud) == 0 {
            return nil
        }
        
        return Instruction(
            pc: ud.pc,
            mnemonic: ud_insn_mnemonic(&ud),
            operands: ud.operand,
            pfx_seg: ud.pfx_seg,
            offset: ud_insn_off(&ud),
            asm: String(cString: ud_insn_asm(&ud), encoding: .utf8)!
        )
    }
    
}

