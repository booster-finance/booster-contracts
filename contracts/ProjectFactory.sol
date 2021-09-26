// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ProjectRaise.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ProjectFactory is Ownable {
    address[] public projects;

    function createProjectRaise(
        address _usdToken,
        address _creator,
        uint256 _fundingGoal,
        uint256 _startTime,
        uint256 _tokenURI,
        uint256[] memory _milestoneReleaseDates,
        uint8[] memory _milestoneReleasePercents) external onlyOwner
        returns (address)
    {
        ProjectRaise project = new ProjectRaise(_usdToken, _creator, _fundingGoal, _startTime, _tokenURI, _milestoneReleaseDates, _milestoneReleasePercents);
        projects.push(address(project));
        return address(project);
    }

    function getProjects() external view returns(address[] memory){
        return projects;
    }
}