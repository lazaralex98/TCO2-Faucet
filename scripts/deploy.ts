import { ethers } from "hardhat";

async function main() {
  const FaucetFactory = await ethers.getContractFactory("Faucet");
  const faucet = await FaucetFactory.deploy();

  await faucet.deployed();

  console.log("Faucet deployed to: ", faucet.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
