import { Signer } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ProjectRaise, ProjectRaise__factory } from "../typechain";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    let accounts: Signer[];
    let raiseContract: ProjectRaise;

    accounts = await hre.ethers.getSigners();

    console.log(await accounts[0].getAddress());

    const raiseFactory = (await hre.ethers.getContractFactory(
        "ProjectRaise",
        accounts[0]
    )) as ProjectRaise__factory;

    raiseContract = await raiseFactory.deploy();

    console.log(
        `The address the Contract WILL have once mined: ${raiseContract.address}`
    );

    console.log(
        `The transaction that was sent to the network to deploy the Contract: ${raiseContract.deployTransaction.hash}`
    );

    console.log(
        "The contract is NOT deployed yet; we must wait until it is mined..."
    );

    await raiseContract.deployed();

    console.log("Minted...");
};
export default func;
func.id = "token_sale_deploy";
func.tags = ["local"];
