# Makefile for USDCAutoForwarder deployment

.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	forge clean

# Deploy using CREATE2
.PHONY: deploy-create2-arb
deploy-create2-arb:
	@echo "Building contracts..."
	@forge build
	@echo "Deploying to Arbitrum Sepolia using CREATE2..."
	@forge script script/DeployCreate2.s.sol:USDCForwarderFactory --rpc-url "https://rpc.ankr.com/arbitrum_sepolia/150aa8fab13e61e50ba49ac1cd0c06e26ae190e4c907691044886fdda314bfb6" --broadcast 

.PHONY: deploy-create2-op
deploy-create2-op:
	@echo "Building contracts..."
	@forge build
	@echo "Deploying to Optimism Sepolia using CREATE2..."
	@forge script script/DeployCreate2.s.sol:USDCForwarderFactory --rpc-url "https://rpc.ankr.com/optimism_sepolia/150aa8fab13e61e50ba49ac1cd0c06e26ae190e4c907691044886fdda314bfb6" --broadcast 

.PHONY: deploy-create2-base
deploy-create2-base:
	@echo "Building contracts..."
	@forge build
	@echo "Deploying to Base Sepolia using CREATE2..."
	@forge script script/DeployCreate2.s.sol:USDCForwarderFactory --rpc-url "https://rpc.ankr.com/base_sepolia/150aa8fab13e61e50ba49ac1cd0c06e26ae190e4c907691044886fdda314bfb6" --broadcast 

# Deploy to all chains
.PHONY: deploy-create2-all
deploy-create2-all:
	@echo "Deploying to all supported chains..."
	@$(MAKE) deploy-create2-arb
	@echo ""
	@$(MAKE) deploy-create2-op
	@echo ""
	@$(MAKE) deploy-create2-base
	@echo ""
	@echo "✅ Deployment complete on all chains!"
