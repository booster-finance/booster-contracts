import { Signer } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { TokenSale, TokenSale__factory } from "../typechain";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    let accounts: Signer[];
    let tokenSaleContract: TokenSale;

    accounts = await hre.ethers.getSigners();

    console.log(await accounts[0].getAddress());

    const saleFactory = (await hre.ethers.getContractFactory(
        "TokenSale",
        accounts[0]
    )) as TokenSale__factory;

    tokenSaleContract = await saleFactory.deploy();

    console.log(
        `The address the Contract WILL have once mined: ${tokenSaleContract.address}`
    );

    console.log(
        `The transaction that was sent to the network to deploy the Contract: ${tokenSaleContract.deployTransaction.hash}`
    );

    console.log(
        "The contract is NOT deployed yet; we must wait until it is mined..."
    );

    await tokenSaleContract.deployed();

    console.log("Minted...");
};
export default func;
func.id = "token_sale_deploy";
func.tags = ["local"];
