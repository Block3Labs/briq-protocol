use traits::{Into, TryInto};
use option::OptionTrait;
use array::{ArrayTrait, SpanTrait};
use starknet::ContractAddress;

use dojo::world::IWorldDispatcher;
use briq_protocol::world_config::{get_world_config};
use briq_protocol::attributes::attribute_group::{AttributeGroup, AttributeGroupTrait};

// starknet planets : attribute_group_id: 1
// briqmas          : attribute_group_id: 2
// ducks            : attribute_group_id: 
// lil ducks        : attribute_group_id: 

#[derive(Drop, Copy, Serde)]
struct BoxInfo {
    briq_1: u128, // nb of briqs of material 0x1
    attribute_group_id: u64,
    attribute_id: u64,
}

fn get_box_infos(box_id: felt252) -> BoxInfo {
    // starknet planets
    if box_id == 1 {
        return BoxInfo { briq_1: 434, attribute_group_id: 1, attribute_id: 1 };
    } else if box_id == 2 {
        return BoxInfo { briq_1: 1252, attribute_group_id: 1, attribute_id: 2 };
    } else if box_id == 3 {
        return BoxInfo { briq_1: 2636, attribute_group_id: 1, attribute_id: 3 };
    } else if box_id == 4 {
        return BoxInfo { briq_1: 431, attribute_group_id: 1, attribute_id: 4 };
    } else if box_id == 5 {
        return BoxInfo { briq_1: 1246, attribute_group_id: 1, attribute_id: 5 };
    } else if box_id == 6 {
        return BoxInfo { briq_1: 2287, attribute_group_id: 1, attribute_id: 6 };
    } else if box_id == 7 {
        return BoxInfo { briq_1: 431, attribute_group_id: 1, attribute_id: 7 };
    } else if box_id == 8 {
        return BoxInfo { briq_1: 1286, attribute_group_id: 1, attribute_id: 8 };
    } else if box_id == 9 {
        return BoxInfo { briq_1: 2392, attribute_group_id: 1, attribute_id: 9 };
    } else if box_id == 10 {
        // briqmas
        return BoxInfo { briq_1: 60, attribute_group_id: 2, attribute_id: 1 };
    }

    assert(false, 'invalid box id');
    BoxInfo { briq_1: 0, attribute_group_id: 0, attribute_id: 0 }
}


use briq_protocol::erc::mint_burn::{MintBurnDispatcher, MintBurnDispatcherTrait};
use briq_protocol::erc::erc1155::internal_trait::InternalTrait1155;
fn unbox<
    T, impl TR: InternalTrait1155<T>, impl TD: Drop<T>
>(ref self: T, world: IWorldDispatcher, box_contract: ContractAddress, owner: ContractAddress, box_id: felt252) {
    let box_infos = get_box_infos(box_id);
    let attribute_group = AttributeGroupTrait::get_attribute_group(
        world, box_infos.attribute_group_id
    );

    // Burn the box
    self._safe_transfer_from(
        owner, Zeroable::zero(),
        box_id.into(),
        1,
        array![],
    );

    // Mint a booklet
    MintBurnDispatcher { contract_address: attribute_group.booklet_contract_address }.mint(
        owner, box_infos.attribute_id.into(), 1
    );

    // Mint briqs
    MintBurnDispatcher { contract_address: get_world_config(world).briq }.mint(
        owner, 1, box_infos.briq_1
    );
}
