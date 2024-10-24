use starknet::{ContractAddress, ClassHash, get_caller_address};
use array::{ArrayTrait, SpanTrait};
use debug::PrintTrait;

use dojo::world::{IWorldProvider, IWorldDispatcher, IWorldDispatcherTrait};

use briq_protocol::attributes::attribute_group::{AttributeGroupTrait};

use briq_protocol::world_config::{WorldConfig, AdminTrait, get_world_config};
use briq_protocol::types::{FTSpec, PackedShapeItem};
use briq_protocol::attributes::attributes::IAttributeHandler;

use briq_protocol::erc::erc1155::internal_trait::InternalTrait1155;

impl ClassHashPrint of PrintTrait<ClassHash> {
    fn print(self: ClassHash) {}
}

#[derive(Model, Copy, Drop, Serde)]
struct ShapeValidator {
    #[key]
    attribute_group_id: u64,
    #[key]
    attribute_id: u64,
    class_hash: ClassHash,
}

// Must be implemented by the class hash pointed to by ShapeValidator
#[starknet::interface]
trait IShapeChecker<ContractState> {
    fn verify_shape(
        self: @ContractState, attribute_id: u64, shape: Span<PackedShapeItem>, fts: Span<FTSpec>
    );
}

#[starknet::interface]
trait IRegisterShapeValidator<ContractState> {
    fn execute(
        ref self: ContractState,
        world: IWorldDispatcher,
        attribute_group_id: u64,
        attribute_id: u64,
        class_hash: ClassHash,
    );
}

#[dojo::contract]
mod register_shape_validator {
    use starknet::{ClassHash, get_caller_address};
    use briq_protocol::world_config::{WorldConfig, AdminTrait};
    use super::ShapeValidator;

    #[external(v0)]
    fn execute(
        ref self: ContractState,
        world: IWorldDispatcher,
        attribute_group_id: u64,
        attribute_id: u64,
        class_hash: ClassHash,
    ) {
        world.only_admins(@get_caller_address());
        set!(world, ShapeValidator { attribute_group_id, attribute_id, class_hash });
    }
}

// should panic if check fails, or no validator found
fn check_shape_via_validator(
    world: IWorldDispatcher,
    attribute_group_id: u64,
    attribute_id: u64,
    shape: Span<PackedShapeItem>,
    fts: Span<FTSpec>,
) {
    let shape_validator: ShapeValidator = get!(
        world, (attribute_group_id, attribute_id), ShapeValidator
    );
    if shape_validator.class_hash.is_zero() {
        panic(array!['no shape verifier']);
    }
    IShapeCheckerLibraryDispatcher { class_hash: shape_validator.class_hash }
        .verify_shape(attribute_id, shape, fts);
}

const two_power_64: felt252 = 0x10000000000000000;

fn calc_booklet_token_id(attribute_group_id: u64, attribute_id: u64) -> felt252 {
    attribute_group_id.into() * two_power_64 + attribute_id.into()
}

impl BookletAttributeHolder<ContractState,
    impl w: IWorldProvider<ContractState>,
    impl i: InternalTrait1155<ContractState>,
    impl drop: Drop<ContractState>,
> of IAttributeHandler<ContractState> {
    fn assign(
        ref self: ContractState,
        world: IWorldDispatcher,
        set_owner: ContractAddress,
        set_token_id: felt252,
        attribute_group_id: u64,
        attribute_id: u64,
        shape: Array<PackedShapeItem>,
        fts: Array<FTSpec>,
    ) {
        assert(world.contract_address == self.world().contract_address, 'bad world');
        assert(world.is_set_contract(get_caller_address()), 'Unauthorized');

        check_shape_via_validator(
            world,
            attribute_group_id,
            attribute_id,
            shape: shape.span(),
            fts: fts.span()
        );

        // Transfer booklet with corresponding attribute_id from set_owner to set_token_id
        self._safe_transfer_from(
            set_owner,
            set_token_id.try_into().unwrap(),
            calc_booklet_token_id(attribute_group_id, attribute_id).into(),
            1,
            array![],
        );
    }

    fn remove(
        ref self: ContractState,
        world: IWorldDispatcher,
        set_owner: ContractAddress,
        set_token_id: felt252,
        attribute_group_id: u64,
        attribute_id: u64
    ) {
        assert(world.contract_address == self.world().contract_address, 'bad world');
        assert(world.is_set_contract(get_caller_address()), 'Unauthorized');

        // Transfer booklet with corresponding attribute_id from set_token_id to set_owner
        self._safe_transfer_from(
            set_token_id.try_into().unwrap(),
            set_owner,
            calc_booklet_token_id(attribute_group_id, attribute_id).into(),
            1,
            array![],
        );
    }
}
