const { ethers } = require("hardhat");

async function main() {
  console.log("Starting deployment of Procrastination Tax contract...");

  // Get the contract factory
  const ProcrastinationTax = await ethers.getContractFactory("ProcrastinationTax");

  // Deployment parameters - adjust these as needed
  const deploymentParams = {
    initialTaxRate: ethers.utils.parseEther("0.01"), // 0.01 ETH base tax
    maxTaxRate: ethers.utils.parseEther("1.0"),      // 1 ETH maximum tax
    taxIncreaseRate: 200, // 2% increase per day (200 basis points)
    gracePeriod: 86400,   // 24 hours grace period (in seconds)
    beneficiary: "0x0000000000000000000000000000000000000000" // Replace with actual beneficiary address
  };

  console.log("Deployment parameters:");
  console.log("- Initial Tax Rate:", ethers.utils.formatEther(deploymentParams.initialTaxRate), "ETH");
  console.log("- Max Tax Rate:", ethers.utils.formatEther(deploymentParams.maxTaxRate), "ETH");
  console.log("- Tax Increase Rate:", deploymentParams.taxIncreaseRate / 100, "% per day");
  console.log("- Grace Period:", deploymentParams.gracePeriod / 3600, "hours");
  console.log("- Beneficiary:", deploymentParams.beneficiary);

  // Deploy the contract
  console.log("\nDeploying contract...");
  const procrastinationTax = await ProcrastinationTax.deploy(
    deploymentParams.initialTaxRate,
    deploymentParams.maxTaxRate,
    deploymentParams.taxIncreaseRate,
    deploymentParams.gracePeriod,
    deploymentParams.beneficiary
  );

  // Wait for deployment to complete
  await procrastinationTax.deployed();

  console.log("✅ Procrastination Tax contract deployed!");
  console.log("📍 Contract address:", procrastinationTax.address);
  console.log("🔗 Transaction hash:", procrastinationTax.deployTransaction.hash);

  // Get network information
  const network = await ethers.provider.getNetwork();
  console.log("🌐 Network:", network.name, `(Chain ID: ${network.chainId})`);

  // Get deployment cost
  const deployTx = await ethers.provider.getTransaction(procrastinationTax.deployTransaction.hash);
  const receipt = await ethers.provider.getTransactionReceipt(procrastinationTax.deployTransaction.hash);
  const gasCost = receipt.gasUsed.mul(deployTx.gasPrice);
  console.log("⛽ Gas used:", receipt.gasUsed.toString());
  console.log("💰 Deployment cost:", ethers.utils.formatEther(gasCost), "ETH");

  // Verify contract deployment
  console.log("\n🔍 Verifying deployment...");
  try {
    const owner = await procrastinationTax.owner();
    const currentTaxRate = await procrastinationTax.getCurrentTaxRate();
    
    console.log("✅ Contract verified successfully!");
    console.log("👤 Owner:", owner);
    console.log("📊 Current tax rate:", ethers.utils.formatEther(currentTaxRate), "ETH");
  } catch (error) {
    console.error("❌ Contract verification failed:", error.message);
  }

  // Save deployment info
  const deploymentInfo = {
    contractAddress: procrastinationTax.address,
    transactionHash: procrastinationTax.deployTransaction.hash,
    network: network.name,
    chainId: network.chainId,
    deploymentParams: {
      initialTaxRate: deploymentParams.initialTaxRate.toString(),
      maxTaxRate: deploymentParams.maxTaxRate.toString(),
      taxIncreaseRate: deploymentParams.taxIncreaseRate,
      gracePeriod: deploymentParams.gracePeriod,
      beneficiary: deploymentParams.beneficiary
    },
    deployedAt: new Date().toISOString(),
    gasCost: gasCost.toString()
  };

  // Write deployment info to file
  const fs = require('fs');
  const path = require('path');
  
  const deploymentsDir = path.join(__dirname, '..', 'deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const deploymentFile = path.join(deploymentsDir, `procrastination-tax-${network.name}-${Date.now()}.json`);
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
  console.log("📄 Deployment info saved to:", deploymentFile);

  // Contract interaction examples
  console.log("\n📋 Contract Interaction Examples:");
  console.log("// Create a new task");
  console.log(`await contract.createTask("Complete project", ${Math.floor(Date.now() / 1000) + 86400 * 7}, { value: ethers.utils.parseEther("0.1") });`);
  console.log("\n// Complete a task");
  console.log("await contract.completeTask(taskId);");
  console.log("\n// Get task details");
  console.log("await contract.getTask(taskId);");
  console.log("\n// Get current tax rate");
  console.log("await contract.getCurrentTaxRate();");

  // Etherscan verification command (if on mainnet/testnet)
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("\n🔍 To verify on Etherscan, run:");
    console.log(`npx hardhat verify --network ${network.name} ${procrastinationTax.address} "${deploymentParams.initialTaxRate}" "${deploymentParams.maxTaxRate}" "${deploymentParams.taxIncreaseRate}" "${deploymentParams.gracePeriod}" "${deploymentParams.beneficiary}"`);
  }

  console.log("\n🎉 Deployment completed successfully!");
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });

// Additional utility functions
async function getEstimatedGasCost() {
  console.log("Estimating deployment gas cost...");
  
  const ProcrastinationTax = await ethers.getContractFactory("ProcrastinationTax");
  const gasEstimate = await ethers.provider.estimateGas(
    ProcrastinationTax.getDeployTransaction(
      ethers.utils.parseEther("0.01"),
      ethers.utils.parseEther("1.0"),
      200,
      86400,
      "0x0000000000000000000000000000000000000000"
    )
  );
  
  const gasPrice = await ethers.provider.getGasPrice();
  const estimatedCost = gasEstimate.mul(gasPrice);
  
  console.log("Estimated gas:", gasEstimate.toString());
  console.log("Gas price:", ethers.utils.formatUnits(gasPrice, "gwei"), "gwei");
  console.log("Estimated cost:", ethers.utils.formatEther(estimatedCost), "ETH");
  
  return estimatedCost;
}

module.exports = { main, getEstimatedGasCost };



