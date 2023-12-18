# Scarb is ridiculously shit, it appends to an output file instead of replacing it. So target/ dir must be nuked before every run.
build:
	rm -rf target/
	scarb build

# Declares class hash, the hash is then printed into terminal.
# Following ENV variables must be set:
#		STARKNET_ACCOUNT	- path to account file
#		STARKNET_KEYSTORE	- path to keystore file
#		STARKNET_RPC			- RPC node URL - network will be selected based on RPC network
declare:
	@FILE_PATH=$(shell find target/dev -type f -name "*.contract_class.json"); \
	echo $${FILE_PATH}; \
	starkli declare $${FILE_PATH}
