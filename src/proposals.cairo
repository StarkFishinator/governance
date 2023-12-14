mod Proposals {
    use core::traits::Destruct;
    use governance::contract::IGovernance;
    use traits::TryInto;
    use option::OptionTrait;
    use traits::Into;
    use box::BoxTrait;
    use zeroable::Zeroable;

    use array::ArrayTrait;
    use array::SpanTrait;
    use clone::Clone;

    use hash::LegacyHash;

    use starknet::contract_address::ContractAddressZeroable;
    use starknet::get_block_info;
    use starknet::get_block_timestamp;
    use starknet::get_caller_address;
    use starknet::BlockInfo;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::event::EventEmitter;

    use starknet::class_hash::class_hash_try_from_felt252;
    use starknet::contract_address::contract_address_to_felt252;

    use governance::contract::Governance::proposal_totalContractMemberStateTrait;
    use governance::contract::Governance::proposal_vote_endsContractMemberStateTrait;
    use governance::contract::Governance::proposal_vote_end_timestampContractMemberStateTrait;
    use governance::contract::Governance::delegate_hashContractMemberStateTrait;
    use governance::contract::Governance::total_delegated_toContractMemberStateTrait;
    use governance::contract::Governance::proposal_voted_byContractMemberStateTrait;
    use governance::contract::Governance::proposal_detailsContractMemberStateTrait;
    use governance::contract::Governance::ContractState;
    use governance::contract::Governance::unsafe_new_contract_state;
    use governance::contract::Governance;
    use governance::types::{
        BlockNumber, ContractType, PropDetails, PropStatus, VoteCount, VoteStatus
    };
    use governance::traits::IERC20Dispatcher;
    use governance::traits::IERC20DispatcherTrait;
    use governance::constants;

    fn get_vote_counts(prop_id: u32) -> VoteCount {
        let state: ContractState = Governance::unsafe_new_contract_state();
        state.proposal_total.read(prop_id)
    }

    fn get_proposal_details(prop_id: u32) -> PropDetails {
        let state = Governance::unsafe_new_contract_state();
        state.proposal_details.read(prop_id)
    }

    fn assert_correct_contract_type(contract_type: u8) {
        assert(contract_type <= 4, 'invalid contract type')
    }

    fn assert_voting_in_progress(prop_id: u32) {
        let state = Governance::unsafe_new_contract_state();
        let end_timestamp: u64 = state.proposal_vote_end_timestamp.read(prop_id);
        assert(end_timestamp != 0, 'prop_id not found');

        let current_timestamp: u64 = get_block_timestamp();

        assert(end_timestamp > current_timestamp, 'voting concluded');
    }

    fn as_u256(high: u128, low: u128) -> u256 {
        u256 { low, high }
    }

    fn get_free_prop_id() -> u32 {
        _get_free_prop_id(0)
    }

    fn _get_free_prop_id(currid: u32) -> u32 {
        let state = Governance::unsafe_new_contract_state();
        let res = state.proposal_vote_ends.read(currid);
        if res == 0 {
            currid
        } else {
            _get_free_prop_id(currid + 1)
        }
    }

    fn get_free_prop_id_timestamp() -> u32 {
        _get_free_prop_id_timestamp(0)
    }

    fn _get_free_prop_id_timestamp(currid: u32) -> u32 {
        let state = Governance::unsafe_new_contract_state();
        let res = state.proposal_vote_end_timestamp.read(currid);
        if res == 0 {
            currid
        } else {
            _get_free_prop_id_timestamp(currid + 1)
        }
    }

    fn submit_proposal(payload: felt252, to_upgrade: u8) -> u32 {
        assert_correct_contract_type(to_upgrade);
        let mut state = Governance::unsafe_new_contract_state();
        let govtoken_addr = state.get_governance_token_address();
        let caller = get_caller_address();
        let caller_balance: u128 = IERC20Dispatcher { contract_address: govtoken_addr }
            .balanceOf(caller)
            .low;
        let total_supply = IERC20Dispatcher { contract_address: govtoken_addr }.totalSupply();
        let res: u256 = as_u256(
            0, caller_balance * constants::NEW_PROPOSAL_QUORUM
        ); // TODO use such multiplication that u128 * u128 = u256
        assert(total_supply < res, 'not enough tokens to submit');

        let prop_id = get_free_prop_id_timestamp();
        let prop_details = PropDetails { payload: payload, to_upgrade: to_upgrade };
        state.proposal_details.write(prop_id, prop_details);

        let current_timestamp: u64 = get_block_timestamp();
        let end_timestamp: u64 = current_timestamp + 600; // ten minutes
        state.proposal_vote_end_timestamp.write(prop_id, end_timestamp);

        state.emit(Governance::Proposed { prop_id, payload, to_upgrade });
        prop_id
    }


    fn hashing(
        hashed_data: felt252, calldata_span: Span<(ContractAddress, u128)>, index: u32
    ) -> felt252 {
        if index >= calldata_span.len() {
            return hashed_data;
        } else {
            let (a, b) = *calldata_span.at(index);
            let hashed_data = LegacyHash::hash(contract_address_to_felt252(a), b);
            return hashing(hashed_data, calldata_span, index + 1_usize);
        }
    }

    fn find_already_delegated(
        to_addr: ContractAddress, calldata_span: Span<(ContractAddress, u128)>, index: u32
    ) -> u128 {
        if index >= calldata_span.len() {
            return 0;
        } else {
            let (a, b) = *calldata_span.at(index);
            if a == to_addr {
                return b;
            } else {
                return find_already_delegated(to_addr, calldata_span, index + 1_usize);
            }
        }
    }


    fn update_calldata(
        to_addr: ContractAddress,
        new_amount: u128,
        calldata_span: Span<(ContractAddress, u128)>,
        mut new_list: Array<(ContractAddress, u128)>,
        index: u32
    ) -> Array<(ContractAddress, u128)> {
        if index >= calldata_span.len() {
            return new_list;
        } else {
            //let calldata_span: Span<(ContractAddress, u128)> = calldata.span();
            let (curr_addr, curr_amount) = *calldata_span.at(index);
            if curr_addr == to_addr {
                new_list.append((curr_addr, new_amount));
            } else {
                new_list.append((curr_addr, curr_amount));
            }
            return update_calldata(to_addr, new_amount, calldata_span, new_list, index + 1_usize);
        }
    }


    fn delegate_vote(
        to_addr: ContractAddress, calldata: Array<(ContractAddress, u128)>, amount: u128
    ) {
        let mut state = Governance::unsafe_new_contract_state();

        let caller_addr = get_caller_address();
        let stored_hash = state.delegate_hash.read(caller_addr);
        let calldata_span: Span<(ContractAddress, u128)> = calldata.span();
        assert(stored_hash == hashing(0, calldata_span, 0), 'incorrect delegate list');

        let curr_total_delegated_to = state.total_delegated_to.read(to_addr);
        let converted_addr = contract_address_to_felt252(caller_addr);

        let gov_token_addr = state.get_governance_token_address();
        let caller_balance_u256: u256 = IERC20Dispatcher { contract_address: gov_token_addr }
            .balanceOf(caller_addr);
        assert(caller_balance_u256.high == 0, 'CARM balance > u128');
        let caller_balance: u128 = caller_balance_u256.low;
        assert(caller_balance > 0, 'CARM balance is zero');

        let already_delegated = find_already_delegated(to_addr, calldata_span, 0);
        assert(caller_balance - already_delegated >= amount, 'Not enough funds');

        let updated_list: Array<(ContractAddress, u128)> = array![];
        let updated_list_span = updated_list.span();

        update_calldata(to_addr, already_delegated + amount, calldata_span, updated_list, 0);

        state.delegate_hash.write(caller_addr, hashing(0, updated_list_span, 0));
        state.total_delegated_to.write(to_addr, curr_total_delegated_to + amount);
    }

    fn withdraw_delegation(
        to_addr: ContractAddress, calldata: Array<(ContractAddress, u128)>, amount: u128
    ) {
        let mut state = Governance::unsafe_new_contract_state();
        let caller_addr = get_caller_address();
        let stored_hash = state.delegate_hash.read(caller_addr);
        let calldata_span: Span<(ContractAddress, u128)> = calldata.span();
        assert(stored_hash == hashing(0, calldata_span, 0), 'incorrect delegate list');

        let max_power_to_withdraw: u128 = find_already_delegated(to_addr, calldata_span, 0);
        assert(max_power_to_withdraw >= amount, 'amount has to be lower');

        let updated_list: Array<(ContractAddress, u128)> = ArrayTrait::new();
        let updated_list_span = updated_list.span();
        let minus_amount = 0 - amount;
        update_calldata(to_addr, minus_amount, calldata_span, updated_list, 0);

        state.delegate_hash.write(caller_addr, hashing(0, updated_list_span, 0));

        let curr_total_delegated_to = state.total_delegated_to.read(to_addr);
        state.total_delegated_to.write(to_addr, curr_total_delegated_to - amount);
    }


    fn vote(prop_id: u32, opinion: bool) {
        let mut state = Governance::unsafe_new_contract_state();
        let gov_token_addr = state.get_governance_token_address();
        let caller_addr = get_caller_address();
        let vote_status: Option<VoteStatus> = state.proposal_voted_by.read((prop_id, caller_addr));

        assert(vote_status.is_none(), 'already voted');

        let caller_balance_u256: u256 = IERC20Dispatcher { contract_address: gov_token_addr }
            .balanceOf(caller_addr);
        assert(caller_balance_u256.high == 0, 'CARM balance > u128');
        let caller_balance: u128 = caller_balance_u256.low;
        assert(caller_balance != 0, 'CARM balance is zero');

        let caller_voting_power = caller_balance + state.total_delegated_to.read(caller_addr);

        assert(caller_voting_power > 0, 'No voting power');

        assert_voting_in_progress(prop_id);

        let current_vote_count = state.proposal_total.read(prop_id);

        if opinion {
            // Vote YAY
            state.proposal_voted_by.write((prop_id, caller_addr), Option::Some(VoteStatus::Yay));
            let new_vote_count = VoteCount {
                yay: current_vote_count.yay + caller_voting_power, nay: current_vote_count.nay
            };
            assert(new_vote_count.yay >= 0, 'new_votes must be non-negative');
            state.proposal_total.write(prop_id, new_vote_count);
        } else {
            // Vote NAY
            state.proposal_voted_by.write((prop_id, caller_addr), Option::Some(VoteStatus::Nay));
            let new_vote_count = VoteCount {
                yay: current_vote_count.yay, nay: current_vote_count.nay + caller_voting_power
            };
            assert(current_vote_count.nay >= 0, 'new_votes must be non-negative');
            state.proposal_total.write(prop_id, new_vote_count);
        }

        state.emit(Governance::Voted { prop_id: prop_id, voter: caller_addr, opinion: opinion });
    }


    fn check_proposal_passed_express(prop_id: u32) -> PropStatus {
        let state = Governance::unsafe_new_contract_state();
        let gov_token_addr = state.get_governance_token_address();
        let total = state.proposal_total.read(prop_id);
        let total_eligible_votes_from_tokenholders_u256: u256 = IERC20Dispatcher {
            contract_address: gov_token_addr
        }
            .totalSupply();
        assert(total_eligible_votes_from_tokenholders_u256.high == 0, 'totalSupply weirdly high');
        let total_eligible_votes_from_tokenholders: u128 =
            total_eligible_votes_from_tokenholders_u256
            .low;

        // Not only tokenholders are eligible, but investors as well, they hold 1/4th of the voting power
        // However, their votes are currently stored in storage_var, not tokens
        // So we must calculate 4/3 of the total supply (additional supply will be 1/4th of new total)
        // and from that 1/2, because that's 50%, So (4/3) * (1/2) = 2/3 of the total supply
        // Multiply total votes by 2 and divide by 3
        // Currently, there are not investors because they haven't yet set up their wallets. For this reason, the minimum is now simply half.
        let minimum_for_express: u128 = total_eligible_votes_from_tokenholders / 2;

        // Check if yay_tally >= minimum_for_express
        if total.yay >= minimum_for_express {
            PropStatus { code: 1, status: 'accepted expressly' }
        } else {
            PropStatus { code: 2, status: 'voting still in progress' }
        }
    }

    fn get_proposal_status(prop_id: u32) -> PropStatus {
        let state = Governance::unsafe_new_contract_state();

        let end_timestamp: u64 = state.proposal_vote_end_timestamp.read(prop_id);
        let current_timestamp: u64 = get_block_timestamp();

        if current_timestamp <= end_timestamp {
            return check_proposal_passed_express(prop_id).into();
        }

        let gov_token_addr = state.get_governance_token_address();
        let vote_count = state.proposal_total.read(prop_id);
        let total_tally: u128 = vote_count.yay + vote_count.nay;

        // Here we multiply by 100 as the constant QUORUM is in percent.
        // If QUORUM = 10, quorum was not met if (total_tally*100) < (total_eligible * 10).
        let total_tally_multiplied = total_tally * 100;

        let total_eligible_votes_u256: u256 = IERC20Dispatcher { contract_address: gov_token_addr }
            .totalSupply();
        assert(total_eligible_votes_u256.high == 0, 'unable to check quorum');
        let total_eligible_votes: u128 = total_eligible_votes_u256.low;

        let quorum_threshold: u128 = total_eligible_votes * constants::QUORUM;

        if total_tally_multiplied < quorum_threshold {
            return PropStatus { status: 'did not meet quorum', code: 0 }; // didn't meet quorum
        }

        if vote_count.yay > vote_count.nay {
            return PropStatus { status: 'passed', code: 1 }; // didn't meet quorum
        } else {
            return PropStatus { status: 'rejected', code: 0 }; // didn't meet quorum
        }
    }
}
