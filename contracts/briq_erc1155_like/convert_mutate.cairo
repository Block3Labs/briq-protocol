%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.math import assert_nn_le, assert_lt, assert_le, assert_not_zero, assert_lt_felt, assert_le_felt
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc

from contracts.types import (
    NFTSpec,
)

from contracts.utilities.authorization import (
    _onlyAdmin,
)

from contracts.briq_erc1155_like.balance_enumerability import (
    _owner,
    _balance,
    _total_supply,
    _setTokenByOwner,
    _unsetTokenByOwner,
    _setMaterialByOwner,
    _maybeUnsetMaterialByOwner,
)

from contracts.briq_erc1155_like.transferability import (
    TransferSingle,
)

# When a NFT is mutated (FT are handled by Transfer)
@event
func Mutate(owner_: felt, old_id_: felt, new_id_: felt, from_material_: felt, to_material_: felt):
end

@event
func ConvertToFT(owner_: felt, material: felt, id_: felt):
end

@event
func ConvertToNFT(owner_: felt, material: felt, id_: felt):
end


@external
func mutateFT_{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (owner: felt, source_material: felt, target_material: felt, qty: felt):
    _onlyAdmin()
    
    assert_not_zero(qty * (source_material - target_material))

    let (balance) = _balance.read(owner, source_material)
    assert_le_felt(qty, balance)
    _balance.write(owner, source_material, balance - qty)
    
    let (balance) = _balance.read(owner, target_material)
    _balance.write(owner, target_material, balance + qty)

    let (res) = _total_supply.read(source_material)
    _total_supply.write(source_material, res - qty)

    let (res) = _total_supply.read(target_material)
    _total_supply.write(target_material, res + qty)

    _setMaterialByOwner(owner, target_material, 0)
    _maybeUnsetMaterialByOwner(owner, source_material)

    let (__addr) = get_contract_address()
    TransferSingle.emit(__addr, owner, 0, source_material, qty)
    TransferSingle.emit(__addr, 0, owner, target_material, qty)

    return ()
end

# The UI can potentially conflict. To avoid that situation, pass new_uid different from existing uid.
@external
func mutateOneNFT_{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (owner: felt, source_material: felt, target_material: felt, uid: felt, new_uid: felt):
    _onlyAdmin()

    assert_lt_felt(uid, 2**188)
    assert_lt_felt(new_uid, 2**188)
    assert_not_zero(source_material - target_material)

    # NFT conversion
    let (res) = _total_supply.read(source_material)
    _total_supply.write(source_material, res - 1)

    let briq_token_id = uid * 2**64 + source_material

    let (curr_owner) = _owner.read(briq_token_id)
    assert curr_owner = owner
    _owner.write(briq_token_id, 0)

    _unsetTokenByOwner(owner, source_material, briq_token_id)
    _maybeUnsetMaterialByOwner(owner, source_material) # Keep after unset token or it won't unset

    let (res) = _total_supply.read(target_material)
    _total_supply.write(target_material, res + 1)

    # briq_token_id is not the new ID
    let briq_token_id = new_uid * 2**64 + target_material

    let (curr_owner) = _owner.read(briq_token_id)
    assert curr_owner = 0
    _owner.write(briq_token_id, owner)

    _setMaterialByOwner(owner, target_material, 0)
    _setTokenByOwner(owner, target_material, briq_token_id, 0)

    let (__addr) = get_contract_address()
    TransferSingle.emit(__addr, owner, 0, uid * 2**64 + source_material, 1)
    TransferSingle.emit(__addr, 0, owner, new_uid * 2**64 + target_material, 1)
    Mutate.emit(owner, uid * 2**64 + source_material, new_uid * 2**64 + target_material, source_material, target_material)

    return ()
end

###############

@external
func convertOneToFT_{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (owner: felt, material: felt, token_id: felt):
    _onlyAdmin()
    
    assert_not_zero(owner)
    assert_not_zero(token_id)

    let (curr_owner) = _owner.read(token_id)
    if curr_owner == owner:
        assert curr_owner = owner
    else:
        assert token_id = curr_owner
    end
    # No need to change material
    _unsetTokenByOwner(owner, material, token_id)
    _owner.write(token_id, 0)

    let (balance) = _balance.read(owner, material)
    _balance.write(owner, material, balance + 1)

    let (__addr) = get_contract_address()
    TransferSingle.emit(__addr, owner, 0, token_id, 1)
    TransferSingle.emit(__addr, 0, owner, material, 1)
    ConvertToFT.emit(owner, material, token_id)
    return ()
end

func _convertToFT{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (owner: felt, index: felt, nfts: NFTSpec*):
    if index == 0:
        return ()
    end
    convertOneToFT_(owner, nfts[0].material, nfts[0].token_id)
    return _convertToFT(owner, index - 1, nfts + NFTSpec.SIZE)
end

@external
func convertToFT_{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (owner: felt, token_ids_len: felt, token_ids: NFTSpec*):
    _onlyAdmin()
    
    assert_not_zero(owner)
    assert_not_zero(token_ids_len)

    _convertToFT(owner, token_ids_len, token_ids)

    return ()
end


@external
func convertOneToNFT_{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (owner: felt, material: felt, uid: felt):
    _onlyAdmin()

    assert_not_zero(owner)
    assert_not_zero(material)
    assert_lt_felt(uid, 2**188)

    # NFT conversion
    let token_id = uid * 2**64 + material

    let (curr_owner) = _owner.read(token_id)
    assert curr_owner = 0
    _owner.write(token_id, owner)

    # No need to change material
    _setTokenByOwner(owner, material, token_id, 0)

    let (balance) = _balance.read(owner, material)
    _balance.write(owner, material, balance - 1)

    let (__addr) = get_contract_address()
    TransferSingle.emit(__addr, owner, 0, material, 1)
    TransferSingle.emit(__addr, 0, owner, token_id, 1)
    ConvertToNFT.emit(owner, material, token_id)

    return ()
end