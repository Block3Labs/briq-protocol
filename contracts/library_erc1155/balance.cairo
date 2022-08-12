%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_nn_le, assert_lt, assert_le, assert_not_zero, assert_lt_felt, unsigned_div_rem, assert_not_equal
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc


from contracts.library_erc1155.balance_only import _balance

############
############
############
# Storage variables.

namespace ERC1155_balance:
    @view
    func balanceOf_{
            syscall_ptr: felt*,
            pedersen_ptr: HashBuiltin*,
            range_check_ptr
        } (owner: felt, token_id: felt) -> (balance: felt):
        let (balance) = _balance.read(owner, token_id)
        return (balance)
    end

    @view
    func balanceOfBatch_{
            syscall_ptr: felt*,
            pedersen_ptr: HashBuiltin*,
            range_check_ptr
        } (owners_len: felt, owners: felt*, token_ids_len: felt, token_ids: felt*) -> (balances_len: felt, balances: felt*):
        alloc_locals
        assert owners_len = token_ids_len
        
        let (balances: felt*) = alloc()
        let (b_end) = _balanceOfBatch(owners_len, owners, token_ids, balances)
        return (b_end - balances, balances)
    end

    func _balanceOfBatch{
            syscall_ptr: felt*,
            pedersen_ptr: HashBuiltin*,
            range_check_ptr
        } (owners_len: felt, owners: felt*, token_ids: felt*, balances: felt*) -> (balance: felt*):
        if owners_len == 0:
            return (balances)
        end
        let (balance) = _balance.read(owners[0], token_ids[0])
        balances[0] = balance
        return _balanceOfBatch(owners_len - 1, owners + 1, token_ids + 1, balances + 1)
    end
end