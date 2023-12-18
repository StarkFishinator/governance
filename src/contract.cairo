// This file if possible calls out to Proposals or Upgrades or other files where actual logic resides.
// When Components arrive in Cairo 2.?, it will be refactored to take advantage of them. Random change to rerun CI

use starknet::ContractAddress;
use governance::types::{ContractType, PropDetails, PropStatus, VoteCount};

#[starknet::interface]
trait IGovernance<TContractState> {
    // PROPOSALS

    fn vote(ref self: TContractState, prop_id: u32, opinion: bool);
    fn get_proposal_details(self: @TContractState, prop_id: u32) -> PropDetails;
    fn get_vote_counts(self: @TContractState, prop_id: u32) -> VoteCount;
    fn submit_proposal(ref self: TContractState, impl_hash: felt252, to_upgrade: u8) -> u32;
    fn get_proposal_status(self: @TContractState, prop_id: u32) -> PropStatus;
    fn get_live_proposals(self: @TContractState) -> Array<u32>;

    // UPGRADES

    fn get_governance_token_address(self: @TContractState) -> ContractAddress;
    fn get_amm_address(self: @TContractState) -> ContractAddress;
    fn apply_passed_proposal(ref self: TContractState, prop_id: u32);

    // AIRDROPS

    // in component

    // OPTIONS

    fn add_0911_1611_options(ref self: TContractState);
}


#[starknet::contract]
mod Governance {
    use governance::types::{
        BlockNumber, ContractType, PropDetails, PropStatus, VoteStatus, VoteCount
    };
    use governance::proposals::Proposals;
    use governance::proposals::Proposals::get_free_prop_id_timestamp;
    use governance::upgrades::Upgrades;
    use governance::options::Options;
    use governance::airdrop::airdrop as airdrop_component;

    use starknet::ContractAddress;


    component!(path: airdrop_component, storage: airdrop, event: AirdropEvent);

    #[abi(embed_v0)]
    impl Airdrop = airdrop_component::AirdropImpl<ContractState>;

    #[storage]
    struct Storage {
        proposal_details: LegacyMap::<u32, PropDetails>,
        proposal_vote_ends: LegacyMap::<u32, BlockNumber>,
        proposal_vote_end_timestamp: LegacyMap::<u32, u64>,
        proposal_voted_by: LegacyMap::<(u32, ContractAddress), Option<VoteStatus>>,
        proposal_total: LegacyMap::<u32, VoteCount>,
        proposal_applied: LegacyMap::<u32, felt252>, // should be Bool after migration
        proposal_initializer_run: LegacyMap::<u64, bool>,
        investor_voting_power: LegacyMap::<ContractAddress, felt252>,
        total_investor_distributed_power: felt252,
        governance_token_address: ContractAddress,
        amm_address: ContractAddress,
        delegate_hash: LegacyMap::<ContractAddress, felt252>,
        total_delegated_to: LegacyMap::<ContractAddress, u128>,
        #[substorage(v0)]
        airdrop: airdrop_component::Storage
    }

    // PROPOSALS

    #[derive(starknet::Event, Drop)]
    struct Proposed {
        prop_id: u32,
        payload: felt252,
        to_upgrade: u8,
    }

    #[derive(starknet::Event, Drop)]
    struct Voted {
        prop_id: u32,
        voter: ContractAddress,
        opinion: bool
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Proposed: Proposed,
        Voted: Voted,
        AirdropEvent: airdrop_component::Event
    }

    #[constructor]
    fn constructor(ref self: ContractState, govtoken_address: ContractAddress) {
        // This is not used in production on mainnet, because the governance token is already deployed (and distributed).
        self.governance_token_address.write(govtoken_address);
    }

    #[external(v0)]
    impl Governance of super::IGovernance<ContractState> {
        // PROPOSALS

        fn get_proposal_details(self: @ContractState, prop_id: u32) -> PropDetails {
            Proposals::get_proposal_details(prop_id)
        }

        // This should ideally return VoteCounts, but it seems like structs can't be returned from 
        // C1.0 external fns as they can't be serialized
        // Actually it can, TODO do the same as I did with PropDetails for this
        fn get_vote_counts(self: @ContractState, prop_id: u32) -> VoteCount {
            Proposals::get_vote_counts(prop_id)
        }

        fn submit_proposal(ref self: ContractState, impl_hash: felt252, to_upgrade: u8) -> u32 {
            Proposals::submit_proposal(impl_hash, to_upgrade)
        }

        fn vote(ref self: ContractState, prop_id: u32, opinion: bool) {
            Proposals::vote(prop_id, opinion)
        }

        fn get_proposal_status(self: @ContractState, prop_id: u32) -> PropStatus {
            Proposals::get_proposal_status(prop_id)
        }

        fn get_live_proposals(self: @ContractState) -> Array<u32> {
            Proposals::get_live_proposals()
        }

        // UPGRADES

        fn get_governance_token_address(self: @ContractState) -> ContractAddress {
            self.governance_token_address.read()
        }

        fn get_amm_address(self: @ContractState) -> ContractAddress {
            self.amm_address.read()
        }

        fn apply_passed_proposal(ref self: ContractState, prop_id: u32) {
            Upgrades::apply_passed_proposal(prop_id)
        }

        fn add_0911_1611_options(ref self: ContractState) {
            Options::run_add_0911_1611_options()
        }
    }
}
