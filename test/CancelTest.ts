import { expect } from "chai";
import { deployments, ethers, getNamedAccounts, getUnnamedAccounts, web3 } from "hardhat";
import { BigNumber, Signer } from "ethers";
import assert from 'assert';
import { DemoToken, DemoToken__factory } from "../typechain";
import { ProjectFactory, ProjectFactory__factory } from '../typechain';
import { ProjectRaise, ProjectRaise__factory } from '../typechain';

const { BN, ether, balance } = require('@openzeppelin/test-helpers');


describe("CANCEL TEST", function () {
    let accounts: string[];
    let tokenInstance: DemoToken;
    let factoryInstance: ProjectFactory;

    before("setup", async () => {
        const projectFactoryFactory = await ethers.getContractFactory("ProjectFactory") as ProjectFactory__factory;
        factoryInstance = await projectFactoryFactory.deploy() as ProjectFactory;
        accounts = await getUnnamedAccounts();
        const tokenFactory = await ethers.getContractFactory("DemoToken") as DemoToken__factory;
        tokenInstance = await tokenFactory.deploy() as DemoToken;
        tokenInstance.initialize([accounts[1], accounts[2], accounts[3]], ["10000", "10000", "10000"]);
    });
    

    after("clean up", async () => {
        factoryInstance = null as any;
        tokenInstance = null as any;
    });

    it("create project raise", async () => {
        // const normalUser = accounts[0];
        // const userSigner = await ethers.getSigner(normalUser);
        let blockNumber = await ethers.provider.getBlockNumber();
        let timestamp = (await ethers.provider.getBlock(blockNumber)).timestamp;
        const releaseDates = [String(timestamp + 100), String(timestamp + 150)];
        const releasePercents = ["40", "60"];
        await factoryInstance.createProjectRaise(tokenInstance.address, accounts[0], "100", String(timestamp + 50), "test", releaseDates, releasePercents);

        let projects = await factoryInstance.getProjects();

        let projectAddress = projects[projects.length - 1];
        const projectFactory = await ethers.getContractFactory("ProjectRaise") as ProjectRaise__factory;
        let project = await projectFactory.attach(projectAddress) as ProjectRaise;

        await ethers.provider.send("evm_increaseTime", [51]);
        await ethers.provider.send("evm_mine", []);
        
        let backerSigner = await ethers.getSigner(accounts[1]);
        await tokenInstance.connect(backerSigner).approve(projectAddress, "1000");
        await project.connect(backerSigner).acceptBacker("100");

        let totalBackingAmount = await project.totalBackingAmount();
        console.log(totalBackingAmount.toString());

        await ethers.provider.send("evm_increaseTime", [51]);
        await ethers.provider.send("evm_mine", []);

        await project.checkFundingSuccess();
        let projectState = await project.currentStatus();
        console.log(projectState);
        let withdrawableAmount = await project.withdrawableFunds();
        console.log(withdrawableAmount.toString());

        let creatorSigner = await ethers.getSigner(accounts[0]);
        await project.connect(creatorSigner).withdrawFunds();
        let creatorBalance = await tokenInstance.balanceOf(accounts[0]);
        console.log(creatorBalance.toString());

        await project.connect(backerSigner).vote(true);

        await ethers.provider.send("evm_increaseTime", [51]);
        await ethers.provider.send("evm_mine", []);

        await project.milestoneCheck();
        projectState = await project.currentStatus();
        console.log(projectState);
        withdrawableAmount = await project.withdrawableFunds();
        console.log(withdrawableAmount.toString());
        await project.connect(backerSigner).withdrawRefund(0);
        let backerBalance = await tokenInstance.balanceOf(accounts[1]);
        console.log(backerBalance.toString());
    });
});
