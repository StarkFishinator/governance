mod Upgrades {
    use core::starknet::storage::StorageMemberAccessTrait;
    use governance::contract::IGovernance;
    use traits::TryInto;
    use option::OptionTrait;
    use traits::Into;
    use box::BoxTrait;

    use starknet::SyscallResultTrait;
    use starknet::SyscallResult;
    use starknet::syscalls;
    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::class_hash;
    use governance::proposals::Proposals;
    use governance::contract::Governance::{
        proposal_applied, amm_address, governance_token_address, proposal_details
    };

    use governance::types::{PropDetails, CustomProposal, CustomProposalList};
    use governance::contract::Governance;
    use governance::contract::Governance::unsafe_new_contract_state;
    use governance::contract::Governance::proposal_appliedContractMemberStateTrait;
    use governance::contract::Governance::proposal_detailsContractMemberStateTrait;
    use governance::contract::Governance::airdrop_component::UnsafeNewContractStateTraitForAirdropImpl;
    use governance::contract::Governance::airdrop_component;
    use governance::contract::Governance::airdrop_component::ComponentState;
    use governance::contract::Governance::ContractState;


    use governance::traits::IAMMDispatcher;
    use governance::traits::IAMMDispatcherTrait;
    use governance::traits::IGovernanceTokenDispatcher;
    use governance::traits::IGovernanceTokenDispatcherTrait;

    fn apply_passed_proposal(prop_id: felt252) {
        let mut state = Governance::unsafe_new_contract_state();
        let status = Proposals::get_proposal_status(prop_id);
        assert(status == 1, 'prop not passed');
        let applied: felt252 = state.proposal_applied.read(prop_id);
        assert(applied == 0, 'Proposal already applied');

        let prop_details: PropDetails = state.proposal_details.read(prop_id);
        let contract_type = prop_details.to_upgrade;

        Proposals::assert_correct_contract_type(contract_type);

        let impl_hash = prop_details.payload;

        // Apply the upgrade
        // TODO use full match/switch when supported
        match contract_type {
            0 => {
                let amm_addr: ContractAddress = state.get_amm_address();
                IAMMDispatcher { contract_address: amm_addr }
                    .upgrade(impl_hash.try_into().unwrap());
            },
            _ => {
                if (contract_type == 1) {
                    let impl_hash_classhash: ClassHash = impl_hash.try_into().unwrap();
                    syscalls::replace_class_syscall(impl_hash_classhash);
                } else if (contract_type == 2) {
                    let govtoken_addr = state.get_governance_token_address();
                    IGovernanceTokenDispatcher { contract_address: govtoken_addr }
                        .upgrade(impl_hash);
                } else if (contract_type == 3) {
                    let mut airdrop_component_state: ComponentState<ContractState> =
                        Governance::airdrop_component::unsafe_new_component_state();
                    airdrop_component_state.merkle_root.write(impl_hash);
                } else if (contract_type == 4) {
                    let entry_point_selector = selector!("execute_generic_proposal");
                    let class_hash: ClassHash = impl_hash.try_into().unwrap();
                    let calldata: Span<felt252> = ArrayTrait::<felt252>::new().span();
                    syscalls::library_call_syscall(class_hash, entry_point_selector, calldata);
                } else if (contract_type == 5) {
                    // see types.cairo. call the impl, get a list of all CustomProposal. iterate through them, check the contract type – do they match?
                    // if they match:
                    // library_call_syscall(
                    // class_hash, – from CustomProposal struct
                    // entry_point_selector, – from CustomProposal struct
                    // calldata, – this is stored in a storage var corresponding to the proposal ID. it should be retrieved from that storage var, see contract.cairo storage – custom_proposal_calldata
                // )

                }
            // else {
            //    assert(
            //        contract_type == 4, 'invalid contract_type'
            //    ); // type 4 is no-op, signal vote
            //}
            // TODO toufic
            // https://docs.starknet.io/documentation/architecture_and_concepts/Smart_Contracts/system-calls-cairo1/#library_call
            // This should be extended such that there are two more contract types – one for generic, one for custom.
            // I would expect generic to be prop type 4 and custom proposals to be prop types 5+.
            // If applying generic:
            // library_call_syscall(
            // class_hash – this is the payload,
            // entry_point_selector (probably literally the felt corresponding to 'execute_generic_proposal')))
            // calldata (empty Span)
            // );
            // If applying custom:
            // see types.cairo. call the impl, get a list of all CustomProposal. iterate through them, check the contract type – do they match?
            // if they match:
            // library_call_syscall(
            // class_hash, – from CustomProposal struct
            // entry_point_selector, – from CustomProposal struct
            // calldata, – this is stored in a storage var corresponding to the proposal ID. it should be retrieved from that storage var, see contract.cairo storage – custom_proposal_calldata
            // )
            }
        }
        state.proposal_applied.write(prop_id, 1); // Mark the proposal as applied
    // TODO emit event
    }
}
