use starknet::{ContractAddress, contract_address_to_felt252, account::Call};
use traits::TryInto;
use array::{ArrayTrait, SpanTrait};
use result::ResultTrait;
use option::OptionTrait;
use integer::u256_from_felt252;
use cheatcodes::PreparedContract;
use forge_print::PrintTrait;

use TBA::account::account::IAccountDispatcher;
use TBA::account::account::IAccountDispatcherTrait;
use TBA::account::account::Account;

use TBA::test_helper::hello_starknet::IHelloStarknetDispatcher;
use TBA::test_helper::hello_starknet::IHelloStarknetDispatcherTrait;
use TBA::test_helper::hello_starknet::HelloStarknet;

use TBA::test_helper::account_upgrade::IUpgradedAccountDispatcher;
use TBA::test_helper::account_upgrade::IUpgradedAccountDispatcherTrait;
use TBA::test_helper::account_upgrade::UpgradedAccount;

use TBA::test_helper::erc721_helper::IERC721Dispatcher;
use TBA::test_helper::erc721_helper::IERC721DispatcherTrait;
use TBA::test_helper::erc721_helper::ERC721;

const PUBLIC_KEY: felt252 = 883045738439352841478194533192765345509759306772397516907181243450667673002;
const NEW_PUBKEY: felt252 = 927653455097593347819453319276534550975930677239751690718124346772397516907;
const SALT: felt252 = 123;
const ACCOUNT: felt252 = 1234;

#[derive(Drop)]
struct SignedTransactionData {
    private_key: felt252,
    public_key: felt252,
    transaction_hash: felt252,
    r: felt252,
    s: felt252
}

fn SIGNED_TX_DATA() -> SignedTransactionData {
    SignedTransactionData {
        private_key: 1234,
        public_key: 883045738439352841478194533192765345509759306772397516907181243450667673002,
        transaction_hash: 2717105892474786771566982177444710571376803476229898722748888396642649184538,
        r: 3068558690657879390136740086327753007413919701043650133111397282816679110801,
        s: 3355728545224320878895493649495491771252432631648740019139167265522817576501
    }
}

fn __setup__() -> (ContractAddress, ContractAddress) {
    // deploy erc721 helper contract
    let erc721_class_hash = declare('ERC721');
    let mut erc721_constructor_calldata = ArrayTrait::new();
    erc721_constructor_calldata.append('tokenbound');
    erc721_constructor_calldata.append('TBA');

    let erc721_prepared = PreparedContract { class_hash: erc721_class_hash, constructor_calldata: @erc721_constructor_calldata };
    let erc721_contract_address = deploy(erc721_prepared).unwrap();

    // mint a new token
    let dispatcher = IERC721Dispatcher { contract_address: erc721_contract_address };
    let recipient: ContractAddress = ACCOUNT.try_into().unwrap();
    dispatcher.mint(recipient, u256_from_felt252(1));

    // deploy account contract
    let account_class_hash = declare('Account');
    let mut acct_constructor_calldata = ArrayTrait::new();
    acct_constructor_calldata.append(PUBLIC_KEY);
    acct_constructor_calldata.append(contract_address_to_felt252(erc721_contract_address));
    acct_constructor_calldata.append(1);
    acct_constructor_calldata.append(0);

    let acct_prepared = PreparedContract { class_hash: account_class_hash, constructor_calldata: @acct_constructor_calldata };
    let acct_contract_address = deploy(acct_prepared).unwrap();
    (acct_contract_address, erc721_contract_address)
}

#[test]
fn test_constructor() {
    let (contract_address, erc721_contract_address) = __setup__();
    let dispatcher = IAccountDispatcher { contract_address };

    let pubkey = dispatcher.get_public_key();
    assert(pubkey == PUBLIC_KEY, 'invalid public key');

    let (token_contract, token_id) = dispatcher.token();
    assert(token_contract == erc721_contract_address, 'invalid token address');
    assert(token_id.low == 1.try_into().unwrap(), 'invalid token id');
}

#[test]
fn test_setting_getting_public_key() {
    let (contract_address, erc721_contract_address) = __setup__();
    let dispatcher = IAccountDispatcher { contract_address };

    start_prank(contract_address, contract_address);
    dispatcher.set_public_key(NEW_PUBKEY);

    let new_pub_key = dispatcher.get_public_key();
    assert(new_pub_key == NEW_PUBKEY, 'invalid public key');
}

#[test]
fn test_is_valid_signature() {
    let (contract_address, erc721_contract_address) = __setup__();
    let dispatcher = IAccountDispatcher { contract_address };
    let data = SIGNED_TX_DATA();
    let hash = data.transaction_hash;

    let mut good_signature = ArrayTrait::new();
    good_signature.append(data.r);
    good_signature.append(data.s);

    let mut bad_signature = ArrayTrait::new();
    bad_signature.append(0x284);
    bad_signature.append(0x492);

    let is_valid = dispatcher.isValidSignature(hash, good_signature.span());
    assert(is_valid == true, 'should accept valid signature');

    let is_valid = dispatcher.isValidSignature(hash, bad_signature.span());
    assert(is_valid == false, 'should reject invalid signature');
}

#[test]
fn test_execute() {
    let (contract_address, erc721_contract_address) = __setup__();
    let dispatcher = IAccountDispatcher { contract_address };
    let data = SIGNED_TX_DATA();

    // deploy `HelloStarknet` contract for testing
    let class_hash = declare('HelloStarknet');
    let prepared = PreparedContract { class_hash: class_hash, constructor_calldata: @ArrayTrait::new() };
    let test_address = deploy(prepared).unwrap();

    // craft calldata for call array
    let mut calldata = ArrayTrait::new();
    calldata.append(100);
    let call = Call {
        to: test_address, 
        selector: 1530486729947006463063166157847785599120665941190480211966374137237989315360,
        calldata: calldata
    };

    // construct call array
    let mut calls = ArrayTrait::new();
    calls.append(call);
    
    // start prank
    let caller_address: ContractAddress = 0.try_into().unwrap();
    start_prank(contract_address, caller_address);

    // make calls
    dispatcher.__execute__(calls);
    
    // check test contract state was updated
    let test_dispatcher = IHelloStarknetDispatcher { contract_address: test_address };
    let balance = test_dispatcher.get_balance();
    assert(balance == 100, 'execute was not successful');
}

#[test]
fn test_execute_multicall() {
    let (contract_address, erc721_contract_address) = __setup__();
    let dispatcher = IAccountDispatcher { contract_address };
    let data = SIGNED_TX_DATA();

    // deploy `HelloStarknet` contract for testing
    let class_hash = declare('HelloStarknet');
    let prepared = PreparedContract { class_hash: class_hash, constructor_calldata: @ArrayTrait::new() };
    let test_address = deploy(prepared).unwrap();

    // craft calldata and create call array
    let mut calldata = ArrayTrait::new();
    calldata.append(100);
    let call1 = Call {
        to: test_address, 
        selector: 1530486729947006463063166157847785599120665941190480211966374137237989315360,
        calldata: calldata
    };
    let mut calldata2 = ArrayTrait::new();
    calldata2.append(200);
    let call2 = Call {
        to: test_address, 
        selector: 1157683809588496510300162709548024577765603117833695133799390448986300456129,
        calldata: calldata2
    };

    // construct call array
    let mut calls = ArrayTrait::new();
    calls.append(call1);
    calls.append(call2);

    // start prank
    let caller_address: ContractAddress = 0.try_into().unwrap();
    start_prank(contract_address, caller_address);

    // make calls
    dispatcher.__execute__(calls);
    
    // check test contract state was updated
    let test_dispatcher = IHelloStarknetDispatcher { contract_address: test_address };
    let balance = test_dispatcher.get_balance();
    assert(balance == 500, 'execute was not successful');
}

#[test]
fn test_token() {
    let (contract_address, erc721_contract_address) = __setup__();
    let dispatcher = IAccountDispatcher { contract_address };

    let (token_contract, token_id) = dispatcher.token();
    assert(token_contract == erc721_contract_address, 'invalid token address');
    assert(token_id.low == 1.try_into().unwrap(), 'invalid token id');
}

#[test]
fn test_owner() {
    let (contract_address, erc721_contract_address) = __setup__();
    let acct_dispatcher = IAccountDispatcher { contract_address: contract_address };
    let token_dispatcher = IERC721Dispatcher { contract_address: erc721_contract_address };   

    let owner = acct_dispatcher.owner(erc721_contract_address, u256_from_felt252(1));
    let token_owner = token_dispatcher.owner_of(u256_from_felt252(1));
    assert(owner == token_owner, 'invalid owner');
}

#[test]
fn test_upgrade() {
    let (contract_address, erc721_contract_address) = __setup__();
    let dispatcher = IAccountDispatcher { contract_address };

    let new_class_hash = declare('UpgradedAccount');

    // call the upgrade function
    start_prank(contract_address, contract_address);
    dispatcher.upgrade(new_class_hash);

    // try to call the version function
    let dispatcher = IUpgradedAccountDispatcher { contract_address };
    let version = dispatcher.version();
    assert(version == 1_u8, 'upgrade unsuccessful');
}