require('dotenv').config();
const Moralis = require('moralis').default;
const { EvmApi } = require('@moralisweb3/evm-api');
const { ethers } = require('ethers');

// Network configurations
const NETWORKS = {
  arbitrumSepolia: {
    chainId: '0xa4ba',
    name: 'Arbitrum Sepolia',
    rpcUrl: process.env.ARBITRUM_SEPOLIA_RPC || 'https://sepolia-rollup.arbitrum.io/rpc',
    usdcAddress: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
    moralisChainId: '0xa4ba',
  },
  optimismSepolia: {
    chainId: '0xaa37dc',
    name: 'Optimism Sepolia',
    rpcUrl: process.env.OPTIMISM_SEPOLIA_RPC || 'https://sepolia.optimism.io',
    usdcAddress: '0x5fd84259d66Cd46123540766Be93DFE6D43130D7',
    moralisChainId: '0xaa37dc',
  },
  baseSepolia: {
    chainId: '0x14a34',
    name: 'Base Sepolia',
    rpcUrl: process.env.BASE_SEPOLIA_RPC || 'https://sepolia.base.org',
    usdcAddress: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
    moralisChainId: '0x14a34',
  }
};

// Contract ABI
const CONTRACT_ABI = [
  "event USDCDeposited(address indexed sender, uint256 amount, uint256 timestamp)",
  "event USDCForwarded(address indexed recipient, uint256 amount, uint256 timestamp)",
  "function forwardUSDC(uint256 amount) external",
  "function getBalance() external view returns (uint256)",
  "function setUSDCAddress(address _usdcToken) external"
];

class USDCForwarderService {
  constructor() {
    this.moralisApiKey = process.env.MORALIS_API_KEY;
    this.privateKey = process.env.PRIVATE_KEY;
    this.contractAddress = process.env.CONTRACT_ADDRESS;
    this.providers = {};
    this.wallets = {};
    this.contracts = {};
    this.lastProcessedBlocks = {};
    this.isRunning = false;
    this.pollingInterval = 10000; // 10 seconds
    this.processedTxHashes = new Set(); // Track processed transactions
  }

  async initialize() {
    try {
      console.log('🚀 Initializing USDC Auto Forwarder Service...');
      
      // Initialize Moralis
      await Moralis.start({
        apiKey: this.moralisApiKey,
      });
      console.log('✅ Moralis initialized');

      // Setup providers, wallets, and contracts for each network
      for (const [networkName, config] of Object.entries(NETWORKS)) {
        this.providers[networkName] = new ethers.JsonRpcProvider(config.rpcUrl);
        this.wallets[networkName] = new ethers.Wallet(this.privateKey, this.providers[networkName]);
        this.contracts[networkName] = new ethers.Contract(
          this.contractAddress,
          CONTRACT_ABI,
          this.wallets[networkName]
        );
        
        // Initialize last processed block
        const currentBlock = await this.providers[networkName].getBlockNumber();
        this.lastProcessedBlocks[networkName] = currentBlock - 100; // Start from 100 blocks ago
        
        console.log(`✅ ${config.name} initialized (current block: ${currentBlock})`);
        
        // Set USDC address for the contract if needed
        await this.setUSDCAddress(networkName, config.usdcAddress);
      }

      console.log('🎉 Service initialization complete!');
    } catch (error) {
      console.error('❌ Initialization failed:', error);
      throw error;
    }
  }

  async setUSDCAddress(networkName, usdcAddress) {
    try {
      const contract = this.contracts[networkName];
      
      // Check if USDC address is already set by trying to get balance
      try {
        await contract.getBalance();
        console.log(`✅ USDC already configured for ${NETWORKS[networkName].name}`);
        return;
      } catch (error) {
        // If getBalance fails, USDC might not be set
      }

      const tx = await contract.setUSDCAddress(usdcAddress, {
        gasLimit: 100000,
      });
      await tx.wait();
      console.log(`✅ USDC address set for ${NETWORKS[networkName].name}: ${usdcAddress}`);
    } catch (error) {
      console.log(`ℹ️  USDC address setting for ${NETWORKS[networkName].name}:`, error.message);
    }
  }

  async startService() {
    if (this.isRunning) {
      console.log('⚠️  Service is already running');
      return;
    }

    this.isRunning = true;
    console.log('🔄 Starting USDC Auto Forwarder Service...');
    console.log(`📊 Polling interval: ${this.pollingInterval / 1000} seconds`);

    // Start polling for each network
    for (const networkName of Object.keys(NETWORKS)) {
      this.startNetworkPolling(networkName);
    }

    // Display initial balances
    await this.getContractBalances();
    console.log('\n🎯 Service is now running and monitoring for deposits!');
  }

  startNetworkPolling(networkName) {
    const pollNetwork = async () => {
      if (!this.isRunning) return;

      try {
        await this.checkForNewDeposits(networkName);
      } catch (error) {
        console.error(`❌ Error polling ${NETWORKS[networkName].name}:`, error.message);
      }

      // Schedule next poll
      if (this.isRunning) {
        setTimeout(pollNetwork, this.pollingInterval);
      }
    };

    // Start polling
    setTimeout(pollNetwork, Math.random() * 5000); // Stagger initial polls
  }

  async checkForNewDeposits(networkName) {
    try {
      const provider = this.providers[networkName];
      const contract = this.contracts[networkName];
      const config = NETWORKS[networkName];

      // Get current block number
      const currentBlock = await provider.getBlockNumber();
      const fromBlock = this.lastProcessedBlocks[networkName] + 1;

      if (fromBlock > currentBlock) {
        return; // No new blocks to process
      }

      // Query for USDCDeposited events using getLogs
      const eventSignature = ethers.id("USDCDeposited(address,uint256,uint256)");
      
      const logs = await provider.getLogs({
        address: this.contractAddress,
        topics: [eventSignature],
        fromBlock: fromBlock,
        toBlock: currentBlock
      });

      if (logs.length > 0) {
        console.log(`\n🔍 Found ${logs.length} deposit event(s) on ${config.name} (blocks ${fromBlock}-${currentBlock})`);

        for (const log of logs) {
          // Skip if we've already processed this transaction
          if (this.processedTxHashes.has(log.transactionHash)) {
            continue;
          }

          try {
            // Parse the log
            const iface = new ethers.Interface(CONTRACT_ABI);
            const parsedLog = iface.parseLog({
              topics: log.topics,
              data: log.data
            });

            const { sender, amount, timestamp } = parsedLog.args;

            console.log(`\n💰 USDC Deposit detected on ${config.name}:`);
            console.log(`   Sender: ${sender}`);
            console.log(`   Amount: ${ethers.formatUnits(amount, 6)} USDC`);
            console.log(`   Timestamp: ${new Date(Number(timestamp) * 1000).toISOString()}`);
            console.log(`   Transaction: ${log.transactionHash}`);
            console.log(`   Block: ${log.blockNumber}`);

            // Mark transaction as processed
            this.processedTxHashes.add(log.transactionHash);

            // Forward the deposited USDC
            await this.forwardUSDC(networkName, amount);

          } catch (parseError) {
            console.error(`❌ Error parsing log on ${config.name}:`, parseError.message);
          }
        }
      }

      // Update last processed block
      this.lastProcessedBlocks[networkName] = currentBlock;

    } catch (error) {
      console.error(`❌ Error checking deposits on ${networkName}:`, error.message);
      
      // Don't update lastProcessedBlock on error to retry this range
      if (error.code === 'NETWORK_ERROR' || error.code === 'TIMEOUT') {
        console.log(`🔄 Will retry ${NETWORKS[networkName].name} on next poll`);
      }
    }
  }

  async forwardUSDC(networkName, amount) {
    try {
      const contract = this.contracts[networkName];
      const config = NETWORKS[networkName];

      console.log(`🔄 Forwarding ${ethers.formatUnits(amount, 6)} USDC on ${config.name}...`);

      // Check contract balance first
      const balance = await contract.getBalance();
      if (balance < amount) {
        console.error(`❌ Insufficient contract balance. Required: ${ethers.formatUnits(amount, 6)}, Available: ${ethers.formatUnits(balance, 6)}`);
        return;
      }

      // Estimate gas
      let gasEstimate;
      try {
        gasEstimate = await contract.forwardUSDC.estimateGas(amount);
        gasEstimate = gasEstimate * 120n / 100n; // Add 20% buffer
      } catch (error) {
        gasEstimate = 150000n; // Fallback gas limit
      }

      // Execute forward transaction
      const tx = await contract.forwardUSDC(amount, {
        gasLimit: gasEstimate,
      });

      console.log(`⏳ Forward transaction submitted: ${tx.hash}`);
      
      const receipt = await tx.wait();
      console.log(`✅ USDC forwarded successfully on ${config.name}`);
      console.log(`   Transaction: ${receipt.transactionHash}`);
      console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
      console.log(`   Status: ${receipt.status === 1 ? 'Success' : 'Failed'}`);

    } catch (error) {
      console.error(`❌ Failed to forward USDC on ${networkName}:`, error.message);
      
      // Retry logic for certain errors
      if (error.code === 'NETWORK_ERROR' || error.code === 'TIMEOUT' || error.message.includes('nonce')) {
        console.log('🔄 Will retry forwarding on next deposit detection...');
      }
    }
  }

  async getContractBalances() {
    console.log('\n💼 Current contract balances:');
    for (const [networkName, config] of Object.entries(NETWORKS)) {
      try {
        const balance = await this.contracts[networkName].getBalance();
        const formattedBalance = ethers.formatUnits(balance, 6);
        console.log(`   ${config.name}: ${formattedBalance} USDC`);
        
        // If there's a balance, consider forwarding it
        if (balance > 0n) {
          console.log(`   ⚠️  Found existing balance, forwarding...`);
          await this.forwardUSDC(networkName, balance);
        }
      } catch (error) {
        console.log(`   ${config.name}: Error fetching balance - ${error.message}`);
      }
    }
  }

  async getServiceStatus() {
    console.log('\n📊 Service Status:');
    console.log(`   Running: ${this.isRunning}`);
    console.log(`   Polling Interval: ${this.pollingInterval / 1000}s`);
    console.log(`   Processed Transactions: ${this.processedTxHashes.size}`);
    console.log(`   Last Processed Blocks:`);
    
    for (const [networkName, config] of Object.entries(NETWORKS)) {
      try {
        const currentBlock = await this.providers[networkName].getBlockNumber();
        const lastProcessed = this.lastProcessedBlocks[networkName];
        const lag = currentBlock - lastProcessed;
        console.log(`     ${config.name}: ${lastProcessed} (lag: ${lag} blocks)`);
      } catch (error) {
        console.log(`     ${config.name}: Error getting block info`);
      }
    }
  }

  async stop() {
    console.log('🛑 Stopping USDC Auto Forwarder Service...');
    this.isRunning = false;
    console.log('✅ Service stopped');
  }
}

// Environment validation
function validateEnvironment() {
  const required = [
    'MORALIS_API_KEY',
    'PRIVATE_KEY', 
    'CONTRACT_ADDRESS'
  ];

  const missing = required.filter(key => !process.env[key]);
  
  if (missing.length > 0) {
    console.error('❌ Missing required environment variables:');
    missing.forEach(key => console.error(`   - ${key}`));
    process.exit(1);
  }

  // Validate contract address format
  if (!ethers.isAddress(process.env.CONTRACT_ADDRESS)) {
    console.error('❌ Invalid CONTRACT_ADDRESS format');
    process.exit(1);
  }
}

// Main execution
async function main() {
  try {
    // Validate environment
    validateEnvironment();
    
    // Create and initialize service
    const service = new USDCForwarderService();
    await service.initialize();
    
    // Start the service
    await service.startService();
    
    // Setup status reporting
    setInterval(async () => {
      await service.getServiceStatus();
      await service.getContractBalances();
    }, 60000); // Every minute
    
    // Setup graceful shutdown
    process.on('SIGINT', async () => {
      console.log('\n🛑 Received SIGINT, shutting down gracefully...');
      await service.stop();
      process.exit(0);
    });
    
    process.on('SIGTERM', async () => {
      console.log('\n🛑 Received SIGTERM, shutting down gracefully...');
      await service.stop();
      process.exit(0);
    });
    
    console.log('\n🎯 USDC Auto Forwarder Service is running!');
    console.log('💡 Press Ctrl+C to stop the service');
    console.log('📊 Status updates every 60 seconds');

  } catch (error) {
    console.error('❌ Service failed to start:', error);
    process.exit(1);
  }
}

// Export for testing
module.exports = { USDCForwarderService, NETWORKS };

// Run if this file is executed directly
if (require.main === module) {
  main();
}