import { Signer } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { start } from "repl";

import { ProjectFactory, ProjectFactory__factory } from "../typechain";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    let accounts: Signer[];
    let factoryContract: ProjectFactory;

    // address _usdToken, address _creator, uint256 _fundingGoal, uint256 _startTime, uint256 _tokenURI,
    // uint256[] memory _milestoneReleaseDates, uint8[] memory _milestoneReleasePercents

    accounts = await hre.ethers.getSigners();
    let blockNum = await hre.ethers.provider.getBlockNumber();
    let block = await hre.ethers.provider.getBlock(blockNum);
    let timestamp = block.timestamp;
    let creator = await accounts[0].getAddress()

    let startTime = timestamp + 10000
    const tokenURI = '0x048a2991c2676296b330734992245f5ba6b98174d3f1907d795b7639e92ce532';
    const milestoneReleaseDates = [
      hre.ethers.BigNumber.from(startTime+10000),
      hre.ethers.BigNumber.from(startTime+20000),
      hre.ethers.BigNumber.from(startTime+30000)
    ]
    const milestoneReleasePercents = [
      hre.ethers.BigNumber.from(50),
      hre.ethers.BigNumber.from(30),
      hre.ethers.BigNumber.from(20)
    ]

    console.log(await accounts[0].getAddress());

    const tokenFactory = await hre.ethers.getContractFactory('DemoToken', accounts[0]);
    const demoToken = await tokenFactory.deploy();
    await demoToken.deployed();

    const projectFactory = (await hre.ethers.getContractFactory(
        "ProjectFactory",
        accounts[0]
    )) as ProjectFactory__factory;

    factoryContract = await projectFactory.deploy();

    console.log(
        `The address the Contract WILL have once mined: ${factoryContract.address}`
    );

    console.log(
        `The transaction that was sent to the network to deploy the Contract: ${factoryContract.deployTransaction.hash}`
    );

    console.log(
        "The contract is NOT deployed yet; we must wait until it is mined..."
    );

    await factoryContract.deployed();

    console.log("Minted...");

    factoryContract.createProjectRaise(demoToken.address, creator, hre.ethers.BigNumber.from('150000000'), hre.ethers.BigNumber.from(startTime),tokenURI, milestoneReleaseDates, milestoneReleasePercents);
};
export default func;
func.id = "deploy";
func.tags = ["local"];