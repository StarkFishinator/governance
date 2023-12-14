# Scarb is ridiculously shit, it appends to an output file instead of replacing it. So target/ dir must be nuked before every run.
build:
	rm -rf target/
	scarb build

# Declares class hash, the hash is then printed into terminal.
# Following ENV variables must be set:
#		STARKNET_ACCOUNT	- path to account file
#		STARKNET_KEYSTORE	- path to keystore file
#		STARKNET_RPC			- RPC node URL - network will be selected based on RPC network
_declare:
	starkli declare target/dev/governance_Governance.contract_class.json


declare: build declare
