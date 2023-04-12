#[contract]
mod Attributes {
    struct Storage {
        _cumulative_balance: LegacyMap<felt252, felt252>
    }
    //@contract_interface
    #[abi]
    trait IDelegateContract {
        fn assign_attribute(
            owner: felt252,
            set_token_id: felt252,
            attribute_id: felt252,
            shape: Array<ShapeItem>,
            fts: Array<FTSpec>,
            nfts: Array<felt252>);

        fn remove_attribute(
            owner: felt252,
            set_token_id: felt252,
            attribute_id: felt252);

        fn balanceOf_(
            owner: felt252,
            attribute_id: felt252) -> felt252;
    }


    type FTSpec = felt252;
    type ShapeItem = felt252;

    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use starknet::ContractAddressIntoFelt252;
    use starknet::Felt252TryIntoContractAddress;

    use gas::withdraw_gas_all;
    use gas::get_builtin_costs;

    use traits::Into;
    use traits::TryInto;
    use option::OptionTrait;

    use array::SpanTrait;
    use array::ArrayTrait;
    use array::ArrayTCloneImpl;
    use clone::Clone;

    use briq_protocol::attributes_registry::collections::Collections::_get_admin_or_contract;
    use briq_protocol::attributes_registry::collections::Collections::_get_collection_id;
    use briq_protocol::ecosystem::to_set::ToSet::getSetAddress_;

    use briq_protocol::utils::feltOrd;
    use briq_protocol::utils::check_gas;

    #[event]
    fn AttributeAssigned(set_token_id: u256, attribute_id: felt252) {
    }

    #[event]
    fn AttributeRemoved(set_token_id: u256, attribute_id: felt252) {
    }
    
    //@external
    fn assign_attributes(
        set_owner: felt252,
        set_token_id: felt252,
        mut attributes: Array<felt252>,
        ref shape: Array<ShapeItem>,
        ref fts: Array<FTSpec>,
        ref nfts: Array<felt252>,
    ) {
        check_gas();
        if (attributes.len() == 0_u32) {
            return ();
        }
        assign_attribute(set_owner, set_token_id, attributes.pop_front().unwrap(), ref shape, ref fts, ref nfts);
        return assign_attributes(set_owner, set_token_id, attributes, ref shape, ref fts, ref nfts);
    }

    //@external
    fn assign_attribute(
        set_owner: felt252,
        set_token_id: felt252,
        attribute_id: felt252,
        ref shape: Array<ShapeItem>,
        ref fts: Array<FTSpec>,
        ref nfts: Array<felt252>,
    ) {
        assert(set_owner != 0, 'Bad input');
        assert(set_token_id != 0, 'Bad input');
        assert(attribute_id != 0, 'Bad input');

        let caller = get_caller_address();
        let set_addr = getSetAddress_();
        // TODO: Set permissions on the collection (owner / set) ? 
        assert (caller == set_addr, 'Bad caller');
        
        let (admin, delegate_contract) = _get_admin_or_contract(_get_collection_id(attribute_id));
        if (delegate_contract == 0) {
            //ERC1155_transferability._transfer_burnable(0, set_token_id, attribute_id, 1);
            assert(0 == 1, 'TODO');
        } else {
            IDelegateContractDispatcher { contract_address: delegate_contract.try_into().unwrap() }.assign_attribute(
                set_owner,
                set_token_id,
                attribute_id,
                shape.clone(),
                fts.clone(),
                nfts.clone()
            );
        }

        AttributeAssigned(set_token_id.into(), attribute_id);

        // Update the cumulative balance
        let balance = _cumulative_balance::read(set_token_id);
        //with_attr error_message("Would overflow balance") {
        //    assert_lt_felt(balance, balance + 1);
        //}
        assert(balance < balance + 1, 'Balance overflow');
        _cumulative_balance::write(set_token_id, balance + 1);
        return ();
    }

    //@external
    fn remove_attributes(
        set_owner: felt252,
        set_token_id: felt252,
        mut attributes: Array<felt252>
    ) {
        check_gas();

        if (attributes.len() == 0_u32) {
            return ();
        }
        remove_attribute(set_owner, set_token_id, attributes.pop_front().unwrap());
        return remove_attributes(set_owner, set_token_id, attributes);
    }

    //@external
    fn remove_attribute(
        set_owner: felt252,
        set_token_id: felt252,
        attribute_id: felt252,
    ) {
        withdraw_gas_all(get_builtin_costs()).expect('Out of gas');
        assert(set_owner != 0, 'Bad input');
        assert(set_token_id != 0, 'Bad input');
        assert(attribute_id != 0, 'Bad input');
        let caller = get_caller_address();
        let set_addr = getSetAddress_();
        assert (caller == set_addr, 'Bad caller');

        let (admin, delegate_contract) = _get_admin_or_contract(_get_collection_id(attribute_id));
        if (delegate_contract == 0) {
            //ERC1155_transferability._transfer_burnable(set_token_id, 0, attribute_id, 1);
        } else {
            IDelegateContractDispatcher { contract_address: delegate_contract.try_into().unwrap() }.remove_attribute(
                set_owner,
                set_token_id,
                attribute_id,
            );
        }

        AttributeRemoved(set_token_id.into(), attribute_id);

        // Update the cumulative balance
        let balance = _cumulative_balance::read(set_token_id);
        //with_attr error_message("Insufficient balance") {
        //    assert_lt_felt(balance - 1, balance);
        //}
        assert(balance - 1 < balance, 'Balance underflow');
        _cumulative_balance::write(set_token_id, balance - 1);
        return ();
    }


    //@view
    fn has_attribute(
        set_token_id: felt252, attribute_id: felt252
    ) -> bool {
        let (_, delegate_contract) = _get_admin_or_contract(_get_collection_id(attribute_id));
        if (delegate_contract == 0) {
            let balance = 0;//ERC1155_balance.balanceOf_(set_token_id, attribute_id);
            return balance > 0;
        } else {
            let balance = IDelegateContractDispatcher { contract_address: delegate_contract.try_into().unwrap() }.balanceOf_(set_token_id, attribute_id);
            return balance > 0;
        }
    }

    //@view
    fn total_balance(
        owner: felt252
    ) -> felt252 {
        return _cumulative_balance::read(owner);
    }

    // Maybe?
    //@view
    fn token_uri(
        set_token_id: felt252, attribute_id: felt252
    ) {
        return ();
    }

}