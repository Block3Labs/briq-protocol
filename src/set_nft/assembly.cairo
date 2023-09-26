use starknet::{ContractAddress, get_caller_address, get_contract_address};

use core::pedersen::pedersen;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

use briq_protocol::erc::erc1155::components::{
    ERC1155OperatorApproval, ERC1155Balance,
    increase_balance as increase_balance_1155, decrease_balance as decrease_balance_1155
};
use dojo_erc::token::erc1155::interface::{IERC1155DispatcherTrait, IERC1155Dispatcher};

use briq_protocol::erc::erc721::components::{
    ERC721Balance, ERC721Owner, ERC721TokenApproval, ERC721OperatorApproval, increase_balance, decrease_balance
};

use briq_protocol::world_config::{WorldConfig, get_world_config};
use briq_protocol::cumulative_balance::{CUM_BALANCE_TOKEN, CB_BRIQ, CB_ATTRIBUTES, CB_TOTAL_SUPPLY_1155};
use briq_protocol::attributes::attributes::{assign_attributes, remove_attributes};
use briq_protocol::attributes::attribute_group::AttributeGroupTrait;
use briq_protocol::types::{FTSpec, PackedShapeItem, AttributeItem};
use briq_protocol::felt_math::FeltBitAnd;

use debug::PrintTrait;

//###########
//###########
// Assembly/Disassembly

fn transfer_briqs(
    world: IWorldDispatcher,
    sender: ContractAddress,
    recipient: ContractAddress,
    mut fts: Span<FTSpec>
) {
    let briq_address = get_world_config(world).briq;

    loop {
        match fts.pop_front() {
            Option::Some(ftspec) => {
                IERC1155Dispatcher { contract_address: briq_address }.safe_transfer_from(
                    sender,
                    recipient,
                    (*ftspec).token_id.into(),
                    (*ftspec).qty.into(),
                    array![]
                );
            },
            Option::None => {
                break;
            }
        };
    }
}


// https://github.com/xJonathanLEI/starknet-rs/blob/master/starknet-accounts/src/factory/mod.rs#L36
// 2 ** 251 - 256   
// = 0x800000000000000000000000000000000000000000000000000000000000000 - 0x100
// = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00
const ADDR_BOUND: u256 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00;
const TOKEN_ID_MASK: u256 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000;

// To prevent people from generating collisions, we need the token_id to be random.
// However, we need it to be predictable for good UI.
// The solution adopted is to hash a hint. Our security becomes the chain hash security.
// Hash on the # of briqs to avoid people being able to 'game' off-chain latency,
// we had issues where people regenerated sets with the wrong # of briqs shown on marketplaces before a refresh.
// The set will take ownership of briqs/booklet/attributes therefore we use a ContractAddress.
// To ensure there are no collisions with 1155 sets (or for that matter official sets)
// reserve some bytes at the end.
fn get_token_id(owner: ContractAddress, token_id_hint: felt252, nb_briqs: u32, attribute_group_id: u64) -> ContractAddress {
    let hash = pedersen(0, owner.into());
    let hash = pedersen(hash, token_id_hint);
    let hash = pedersen(hash, nb_briqs.into());
    let two_power_32 = 0x100000000;
    let mut hash_256: u256 = hash.into();
    hash_256 = (hash_256 & TOKEN_ID_MASK) + attribute_group_id.into();
    let hash_252: felt252 = (hash_256 % ADDR_BOUND).try_into().unwrap();

    hash_252.try_into().unwrap()
}

fn get_1155_token_id(attrib: AttributeItem) -> ContractAddress {
    let two_power_32 = 0x100000000_u256;
    assert(attrib.attribute_group_id.into() < two_power_32, 'Attribute group too large');
    let token_256: u256 = (attrib.attribute_id.into() * two_power_32 + attrib.attribute_group_id.into());
    let token_252: felt252 = (token_256 % ADDR_BOUND).try_into().unwrap();

    token_252.try_into().unwrap()
}

fn get_target_contract_from_attributes(
    world: IWorldDispatcher, arr: @Array<AttributeItem>
) -> (ContractAddress, Option::<AttributeItem>) {
    let mut token = get_world_config(world).generic_sets;
    let mut attrib = Option::<AttributeItem>::None;
    let mut span = arr.span();
    loop {
        match span.pop_front() {
            Option::Some(attribute_item) => {
                let attribute_group = AttributeGroupTrait::get_attribute_group(
                    world, *attribute_item.attribute_group_id
                );
                if attribute_group.target_set_contract_address.is_non_zero() {
                    token = attribute_group.target_set_contract_address;
                    attrib = Option::<AttributeItem>::Some(*attribute_item);
                    break;
                }
            },
            Option::None => {
                break;
            }
        };
    };
    (token, attrib)
}

fn create_token(
    world: IWorldDispatcher, token: ContractAddress, recipient: ContractAddress, token_id: felt252
) {
    assert(recipient.is_non_zero(), 'ERC721: mint to 0');
    increase_balance(world, token, recipient, 1);

    let set_token_contract = get_world_config(world).generic_sets;

    let token_owner = get!(world, (set_token_contract, token_id), ERC721Owner).address;
    assert(token_owner.is_zero(), 'ERC721: already minted');

    set!(world, ERC721Owner { token: set_token_contract, token_id, address: recipient });

    // TODO: events are currently emitted directly on the contract
}

fn destroy_token(
    world: IWorldDispatcher, token: ContractAddress, owner: ContractAddress, token_id: felt252
) {
    decrease_balance(world, token, owner, 1);

    let set_token_contract = get_world_config(world).generic_sets;
    let token_owner = get!(world, (set_token_contract, token_id), ERC721Owner).address;

    assert(token_owner.is_non_zero(), 'ERC721: invalid token_id');
    assert(token_owner == owner, 'SetNft: invalid owner');

    set!(world, ERC721Owner { token: set_token_contract, token_id, address: Zeroable::zero() });
    
    // TODO: events are currently emitted directly on the contract
}

fn check_briqs_and_attributes_are_zero(world: IWorldDispatcher, token_id: felt252) {
    // Check that we gave back all briqs (the user might attempt to lie).
    let balance = get!(world, (
        world, CUM_BALANCE_TOKEN(), token_id, CB_BRIQ()
    ), ERC1155Balance).amount;

    assert(balance == 0, 'Set still has briqs');

    // Check that we no longer have any attributes active.
    let balance = get!(world, (
        world, CUM_BALANCE_TOKEN(), token_id, CB_ATTRIBUTES()
    ), ERC1155Balance).amount;

    assert(balance == 0, 'Set still attributed');
}

#[starknet::interface]
trait ISetNftAssembly<ContractState> {
    fn assemble(
        ref self: ContractState,
        owner: ContractAddress,
        token_id_hint: felt252,
        name: Array<felt252>, // todo string
        description: Array<felt252>, // todo string
        fts: Array<FTSpec>,
        shape: Array<PackedShapeItem>,
        attributes: Array<AttributeItem>
    ) -> felt252;

    fn disassemble(
        ref self: ContractState,
        owner: ContractAddress,
        token_id: ContractAddress,
        fts: Array<FTSpec>,
        attributes: Array<AttributeItem>
    );
}

use briq_protocol::erc::get_world::GetWorldTrait;
use briq_protocol::erc::erc721::internal_trait::InternalTrait721;
use briq_protocol::erc::erc1155::internal_trait::InternalTrait1155;

// Default implementation for 721-like contracts
impl SetNftAssembly721<ContractState,
    impl w: GetWorldTrait<ContractState>,
    impl i: InternalTrait721<ContractState>,
    impl drop: Drop<ContractState>,
> of ISetNftAssembly<ContractState> {

    fn assemble(
        ref self: ContractState,
        owner: ContractAddress,
        token_id_hint: felt252,
        name: Array<felt252>, // todo string
        description: Array<felt252>, // todo string
        fts: Array<FTSpec>,
        shape: Array<PackedShapeItem>,
        attributes: Array<AttributeItem>
    ) -> felt252 {
        let world = self.world();
        let caller = get_caller_address();
        assert(owner == caller, 'Only Owner');
        assert(shape.len() != 0, 'Cannot mint empty set');

        let (token, attrib_option) = get_target_contract_from_attributes(world, @attributes);
        assert(token == get_contract_address(), 'Not the correct contract');

        let mut attribute_group_id = 0;
        if attrib_option.is_some() {
            attribute_group_id = attrib_option.unwrap().attribute_group_id;
        }

        let token_id = get_token_id(owner, token_id_hint, shape.len(), attribute_group_id);
        create_token(world, token, owner, token_id.into());
        transfer_briqs(world, owner, token_id, fts.span());

        assign_attributes(world, owner, token_id, @attributes, @shape, @fts,);
        
        return token_id.into();
    }

    fn disassemble(
        ref self: ContractState,
        owner: ContractAddress,
        token_id: ContractAddress,
        fts: Array<FTSpec>,
        attributes: Array<AttributeItem>
    ) {
        let world = self.world();
        let caller = get_caller_address();
        assert(owner == caller, 'Only Owner');

        let (token, _) = get_target_contract_from_attributes(world, @attributes);

        remove_attributes(world, owner, token_id, attributes.clone(),);

        transfer_briqs(world, token_id, owner, fts.span());
        check_briqs_and_attributes_are_zero(world, token_id.into());

        destroy_token(world, token, owner, token_id.into());
    }
}


// Default implementation for 1155-like contracts
impl SetNftAssembly1155<ContractState,
    impl w: GetWorldTrait<ContractState>,
    impl i: InternalTrait1155<ContractState>,
    impl drop: Drop<ContractState>,
> of ISetNftAssembly<ContractState> {

    fn assemble(
        ref self: ContractState,
        owner: ContractAddress,
        token_id_hint: felt252,
        name: Array<felt252>, // todo string
        description: Array<felt252>, // todo string
        fts: Array<FTSpec>,
        shape: Array<PackedShapeItem>,
        attributes: Array<AttributeItem>
    ) -> felt252 {
        let world = self.world();
        let caller = get_caller_address();
        assert(owner == caller, 'Only Owner');
        assert(shape.len() != 0, 'Cannot mint empty set');

        // Check that we are asking for the attribute group that matches this contract
        // (could be hardcoded instead?)
        let (token, attrib_option) = get_target_contract_from_attributes(world, @attributes);
        let attrib = attrib_option.unwrap().into();
        assert(token == get_contract_address(), 'Not the correct contract');

        // Token ID is the attribute ID for simplicity, and attribute group as bitpacking marker.
        let token_id: felt252 = get_1155_token_id(attrib).into();

        self._safe_transfer_from(
            Zeroable::zero(), owner, token_id.into(), 1, array![]
        );

        transfer_briqs(world, owner, token_id.try_into().unwrap(), fts.span());

        // no events
        increase_balance_1155(
            world, CUM_BALANCE_TOKEN(), token_id.try_into().unwrap(), CB_TOTAL_SUPPLY_1155(), 1
        );

        assign_attributes(world, owner, token_id.try_into().unwrap(), @attributes, @shape, @fts,);

        return token_id;
    }

    fn disassemble(
        ref self: ContractState,
        owner: ContractAddress,
        token_id: ContractAddress,
        fts: Array<FTSpec>,
        attributes: Array<AttributeItem>
    ) {
        let world = self.world();
        let caller = get_caller_address();
        assert(owner == caller, 'Only Owner');

        // Check that we are asking for the attribute group that matches this contract
        // (could be hardcoded instead?)
        let (token, o_attribute_id) = get_target_contract_from_attributes(world, @attributes);
        assert(token == get_caller_address(), 'Not the correct caller');

        let nb_briq_tokens = get!(world, (
            world, CUM_BALANCE_TOKEN(), token_id, CB_BRIQ()
        ), ERC1155Balance).amount;

        assert(fts.len().into() == nb_briq_tokens, 'not enough fts');
        let mut prev_briqs = ArrayTrait::<FTSpec>::new();
        let mut ftsp = fts.span();
        loop {
            if ftsp.len() == 0 {
                break;
            }
            let ftspec = *ftsp.pop_front().unwrap();
            prev_briqs.append(FTSpec { token_id: ftspec.token_id, qty: get!(world, (
                world, get_world_config(world).briq, token_id, ftspec.token_id
            ), ERC1155Balance).amount });
        };

        let prev_attrib = get!(world, (
            world, CUM_BALANCE_TOKEN(), token_id, CB_ATTRIBUTES()
        ), ERC1155Balance).amount;

        transfer_briqs(world, token_id, owner, fts.span());

        let token_id_felt: felt252 = token_id.into();
        self._safe_transfer_from(owner, Zeroable::zero(), token_id_felt.into(), 1, array![]);

        decrease_balance_1155(
            world, CUM_BALANCE_TOKEN(), token_id, CB_TOTAL_SUPPLY_1155(), 1
        );

        remove_attributes(world, owner, token_id, attributes.clone(),);

        let post_attrib = get!(world, (
            world, CUM_BALANCE_TOKEN(), token_id, CB_ATTRIBUTES()
        ), ERC1155Balance).amount;

        let remaining_supply = get!(world, (
            world, CUM_BALANCE_TOKEN(), token_id, CB_TOTAL_SUPPLY_1155()
        ), ERC1155Balance).amount;

        assert(post_attrib / (prev_attrib - post_attrib) == remaining_supply, 'Set still has attribs');

        loop {
            if prev_briqs.len() == 0 {
                break;
            }
            let pre_briq = prev_briqs.pop_front().unwrap();
            let post_briq = get!(world, (
                world, get_world_config(world).briq, token_id, pre_briq.token_id
            ), ERC1155Balance).amount;
            assert(post_briq / (pre_briq.qty - post_briq) == remaining_supply, 'Set still has briqs');
        };
    }
}
