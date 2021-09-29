import { expect } from "chai";
import { deployments, ethers, getNamedAccounts, getUnnamedAccounts, web3 } from "hardhat";
import { BigNumber, Signer } from "ethers";
import assert from 'assert';
import { ProjectFactory, ProjectFactory__factory } from '../typechain';
import { ProjectRaise, ProjectRaise__factory } from '../typechain';

const { BN, ether, balance } = require('@openzeppelin/test-helpers');


describe("BASIC TEST", function () {
    let accounts: string[];
    let factoryInstance: ProjectFactory;

    before("setup", async () => {
        const projectFactory = await ethers.getContractFactory("ProjectFactory") as ProjectFactory__factory;
        factoryInstance = await projectFactory.deploy() as ProjectFactory;
        accounts = await getUnnamedAccounts();
    });
    

    after("clean up", async () => {
        factoryInstance = null as any;
    });

    it("create project raise", async () => {
        // const normalUser = accounts[0];
        // const userSigner = await ethers.getSigner(normalUser);
        const releaseDates = ["1636869214947", "1638869214947", "1642869214947"];
        const releasePercents = ["40", "30", "30"];
        await factoryInstance.createProjectRaise("0xe548bf086b4baa6c8a5ca63ac55c79f5b9af25f7", accounts[0], "100", "1633869214947", "0", releaseDates, releasePercents);

        let projects = await factoryInstance.getProjects();
    });
});
