use starknet::SyscallResult;
use starknet::syscalls::storage_read_syscall;
use starknet::syscalls::storage_write_syscall;
use starknet::storage_address_from_base_and_offset;
use core::serde::Serde;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct PropDetails {
    payload: felt252,
    to_upgrade: u8,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct VoteCount {
    yay: u128,
    nay: u128
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct PropStatus {
    // text description of what happened
    status: felt252,
    // 0 - rejected, 1 - accepted, 2 - in progress
    code: u8,
}

type BlockNumber = felt252;

#[derive(Drop, Destruct, PanicDestruct, starknet::Store)]
enum VoteStatus {
    Yay,
    Nay,
}
type ContractType =
    u8; // for Carmine 0 = amm, 1 = governance, 2 = CARM token, 3 = merkle tree root, 4 = no-op/signal vote
type OptionSide = felt252;
type OptionType = felt252;
