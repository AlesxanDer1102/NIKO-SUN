include .env

.PHONY: build test deploy verify

build:
	forge build

test:
	forge test

deploy:
	forge script script/DeploySolarToken.s.sol --rpc-url $(SYSCOIN_RPC_URL) --account $(ACCOUNT) --broadcast  

deploy-fast:
	forge create src/SolarTokenV1.sol:SolarTokenV1  --rpc-url $(SYSCOIN_RPC_URL) --account $(ACCOUNT) --broadcast  --constructor-args "https://api.nikosun.com/" -vvvvv
verify:
	forge verify-contract \
  --rpc-url https://rpc.tanenbaum.io \
  --verifier blockscout \
  --verifier-url 'https://explorer.tanenbaum.io/api/' \
  $(ADDRESS) \
  [contractFile]:[contractName]