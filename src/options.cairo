// Handles adding new options to the AMM and linking them to the liquidity pool.
// I have chosen this perhaps rather complex type layout in expectation of generating the options soon –
// – first generating FutureOption, then generating everything from Pragma data

mod Options {
    use governance::contract::IGovernance;
    use traits::{Into, TryInto};
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;

    use starknet::SyscallResultTrait;
    use starknet::SyscallResult;
    use starknet::class_hash;
    use starknet::ClassHash;
    use starknet::contract_address::{
        ContractAddress, Felt252TryIntoContractAddress, ContractAddressIntoFelt252
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::info::get_contract_address;

    use cubit::f128::types::{Fixed, FixedTrait};

    use governance::contract::Governance;
    use governance::contract::Governance::{
        amm_address, proposal_initializer_run, proposal_initializer_runContractMemberStateTrait
    };
    use governance::constants::{
        OPTION_CALL, OPTION_PUT, TRADE_SIDE_LONG, TRADE_SIDE_SHORT, OPTION_TOKEN_CLASS_HASH,
        LP_ETH_USDC_CALL, LP_ETH_USDC_PUT, LP_BTC_USDC_CALL, LP_BTC_USDC_PUT
    };
    use governance::traits::{
        IAMMDispatcher, IAMMDispatcherTrait, IOptionTokenDispatcher, IOptionTokenDispatcherTrait
    };
    use governance::types::{OptionSide, OptionType};

    fn add_options(mut options: Span<FutureOption>) {
        // TODO use block hash from block_hash syscall as salt // actually doable with the new syscall
        let governance_address = get_contract_address();
        let state = Governance::unsafe_new_contract_state();
        let amm_address = state.get_amm_address();
        loop {
            match options.pop_front() {
                Option::Some(option) => { add_option(governance_address, amm_address, option); },
                Option::None(()) => { break (); },
            };
        }
    }

    // TODO add auto generation of FutureOption structs once string contacenation exists
    #[derive(Copy, Drop, Serde)]
    struct FutureOption {
        name_long: felt252,
        name_short: felt252,
        maturity: felt252,
        strike_price: Fixed,
        option_type: OptionType,
        lptoken_address: ContractAddress,
        btc: bool,
        initial_volatility: Fixed
    }

    fn add_option(
        governance_address: ContractAddress, amm_address: ContractAddress, option: @FutureOption
    ) {
        let o = *option;

        // mainnet
        let USDC_addr: felt252 = 0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8;
        let ETH_addr: felt252 = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;
        let BTC_addr: felt252 = 0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac;
        let quote_token_address = USDC_addr;
        let base_token_address = if (o.btc) {
            BTC_addr
        } else {
            ETH_addr
        };

        // Yes, this 'overflows', but it's expected and wanted.
        let custom_salt: felt252 = 42
            + o.strike_price.mag.into()
            + o.maturity
            + o.option_type
            + o.lptoken_address.into();

        let opt_class_hash: ClassHash = OPTION_TOKEN_CLASS_HASH.try_into().unwrap();
        let mut optoken_long_calldata = array![];
        optoken_long_calldata.append(o.name_long);
        optoken_long_calldata.append('C-OPT');
        optoken_long_calldata.append(amm_address.into());
        optoken_long_calldata.append(quote_token_address);
        optoken_long_calldata.append(base_token_address);
        optoken_long_calldata.append(o.option_type);
        optoken_long_calldata.append(o.strike_price.mag.into());
        optoken_long_calldata.append(o.maturity);
        optoken_long_calldata.append(TRADE_SIDE_LONG);
        let deploy_retval = deploy_syscall(
            opt_class_hash, custom_salt + 1, optoken_long_calldata.span(), false
        );
        let (optoken_long_addr, _) = deploy_retval.unwrap_syscall();

        let mut optoken_short_calldata = array![];
        optoken_short_calldata.append(o.name_short);
        optoken_short_calldata.append('C-OPT');
        optoken_short_calldata.append(amm_address.into());
        optoken_short_calldata.append(quote_token_address);
        optoken_short_calldata.append(base_token_address);
        optoken_short_calldata.append(o.option_type);
        optoken_short_calldata.append(o.strike_price.mag.into());
        optoken_short_calldata.append(o.maturity);
        optoken_short_calldata.append(TRADE_SIDE_SHORT);
        let deploy_retval = deploy_syscall(
            opt_class_hash, custom_salt + 2, optoken_short_calldata.span(), false
        );
        let (optoken_short_addr, _) = deploy_retval.unwrap_syscall();

        IAMMDispatcher { contract_address: amm_address }
            .add_option_both_sides(
                o.maturity.try_into().unwrap(),
                o.strike_price,
                quote_token_address.try_into().unwrap(),
                base_token_address.try_into().unwrap(),
                o.option_type,
                o.lptoken_address,
                optoken_long_addr,
                optoken_short_addr,
                o.initial_volatility
            );
    }


    fn add_020224_options() {
        let eth_usdc_call_address = LP_ETH_USDC_CALL.try_into().unwrap();
        let eth_usdc_put_address = LP_ETH_USDC_PUT.try_into().unwrap();
        let btc_usdc_call_address = LP_BTC_USDC_CALL.try_into().unwrap();
        let btc_usdc_put_address = LP_BTC_USDC_PUT.try_into().unwrap();

        // Thu Feb 01 2024 23:59:59 GMT+0000
        let MATURITY: felt252 = 1706831999;

        let point_five = FixedTrait::ONE() / FixedTrait::from_unscaled_felt(2);

        let mut to_add = ArrayTrait::<FutureOption>::new();
        to_add
            .append(
                FutureOption {
                    name_long: 'ETHUSDC-02FEB24-2600-LONG-CALL',
                    name_short: 'ETHUSDC-02FEB24-2600-SHORT-CALL',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(2600),
                    option_type: OPTION_CALL,
                    lptoken_address: eth_usdc_call_address,
                    btc: false,
                    initial_volatility: FixedTrait::from_unscaled_felt(51)
                }
            );
        to_add
            .append(
                FutureOption {
                    name_long: 'ETHUSDC-02FEB24-2700-LONG-CALL',
                    name_short: 'ETHUSDC-02FEB24-2700-SHORT-CALL',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(2700),
                    option_type: OPTION_CALL,
                    lptoken_address: eth_usdc_call_address,
                    btc: false,
                    initial_volatility: FixedTrait::from_unscaled_felt(51)
                }
            );
        to_add
            .append(
                FutureOption {
                    name_long: 'ETHUSDC-02FEB24-2500-LONG-PUT',
                    name_short: 'ETHUSDC-02FEB24-2500-SHORT-PUT',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(2500),
                    option_type: OPTION_PUT,
                    lptoken_address: eth_usdc_put_address,
                    btc: false,
                    initial_volatility: FixedTrait::from_unscaled_felt(51) + point_five
                }
            );
        to_add
            .append(
                FutureOption {
                    name_long: 'ETHUSDC-02FEB24-2400-LONG-PUT',
                    name_short: 'ETHUSDC-02FEB24-2400-SHORT-PUT',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(2400),
                    option_type: OPTION_PUT,
                    lptoken_address: eth_usdc_put_address,
                    btc: false,
                    initial_volatility: FixedTrait::from_unscaled_felt(53)
                }
            );

        // BITCOIN

        to_add
            .append(
                FutureOption {
                    name_long: 'BTCUSD-02FEB24-43000-LONG-CALL',
                    name_short: 'BTCUSD-02FEB24-43000-SHORT-CALL',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(43000),
                    option_type: OPTION_CALL,
                    lptoken_address: btc_usdc_call_address,
                    btc: true,
                    initial_volatility: FixedTrait::from_unscaled_felt(48)
                }
            );
        to_add
            .append(
                FutureOption {
                    name_long: 'BTCUSD-02FEB24-44000-LONG-CALL',
                    name_short: 'BTCUSD-02FEB24-44000-SHORT-CALL',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(44000),
                    option_type: OPTION_CALL,
                    lptoken_address: btc_usdc_call_address,
                    btc: true,
                    initial_volatility: FixedTrait::from_unscaled_felt(48)
                }
            );
        to_add
            .append(
                FutureOption {
                    name_long: 'BTCUSD-02FEB24-45000-LONG-CALL',
                    name_short: 'BTCUSD-02FEB24-45000-SHORT-CALL',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(45000),
                    option_type: OPTION_CALL,
                    lptoken_address: btc_usdc_call_address,
                    btc: true,
                    initial_volatility: FixedTrait::from_unscaled_felt(48)
                }
            );
        to_add
            .append(
                FutureOption {
                    name_long: 'BTCUSD-02FEB24-42000-LONG-PUT',
                    name_short: 'BTCUSD-02FEB24-42000-SHORT-PUT',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(42000),
                    option_type: OPTION_PUT,
                    lptoken_address: btc_usdc_put_address,
                    btc: true,
                    initial_volatility: FixedTrait::from_unscaled_felt(49)
                }
            );
        to_add
            .append(
                FutureOption {
                    name_long: 'BTCUSD-02FEB24-41000-LONG-PUT',
                    name_short: 'BTCUSD-02FEB24-41000-SHORT-PUT',
                    maturity: MATURITY,
                    strike_price: FixedTrait::from_unscaled_felt(41000),
                    option_type: OPTION_PUT,
                    lptoken_address: btc_usdc_put_address,
                    btc: true,
                    initial_volatility: FixedTrait::from_unscaled_felt(50)
                }
            );

        add_options(to_add.span())
    }
}
