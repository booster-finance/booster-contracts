// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./Tier/TierNFT.sol";


contract ProjectRaise is Ownable {
    using SafeMath for uint256;

    /// @notice Emits when a backer backs to the project
    /// @param backer The address of the backer
    /// @param amount The number of tokens backed
    event Back(address indexed backer, uint256 amount);

    /// @notice Emits when a backer receives a refund
    /// @param backer The address of the refund recipient
    /// @param amount The number of tokens refunded
    event Refund(address indexed backer, uint256 amount);

    /// @notice Emits when a creator withdraws funds
    /// @param creator The address of the project creator
    /// @param amount The number of tokens withdrawn
    /// @param complete True if this is the final withdrawal
    event CreatorWithdraw(address indexed creator, uint256 amount, bool complete);

    /// @notice Emits when a backer votes to cancel the project or not
    /// @param backer The address of the project creator
    /// @param amount The value of the vote
    /// @param vote True if they voted to cancel the project
    event BackerVote(address indexed backer, uint256 amount, bool vote);

    /// The ERC20 token used to fund the project
    IERC20 public usdToken;

    /// The address of the project's creator
    address public creator;

    /// The minimum number of tokens that must be raised
    uint256 public fundingGoal;

    /// Timestamp of the start of the project
    uint256 public startTime;

    /// IPFS pointer of project details
    uint256 public tokenURI;

    /// Record of backings that have been made to the project
    mapping(address => uint256) public backings;

    /// Record of NFT tier rewards an address has received
    mapping(address => BackerNFTReward[]) public backerRewards;

    /// Total number of tokens backed
    uint256 public totalBackingAmount;

    /// Record that indicates whether a backer has voted to deny funds to `creator`
    mapping(address => bool) public cancelVotes;

    /// Vote count weighted by backing amount
    uint256 public cancelVoteCount;

    // Current status of project, start at started
    Status public currentStatus = Status.STARTED;

    // Current milestone of project, start at 0
    uint8 public currentMilestone = 0;

    // Keep track of funds that have already been allocated to creator, used for keeping track of how much a backer can get after each milestone
    uint8 public cummulativeReleasePercent = 0;

    // Total amount of funds the creator is able to withdraw
    uint256 public withdrawableFunds;

    // Array of all milestones in project
    Milestone[] public milestones;

    // Mapping of funding amount to the tier it corresponds to
    mapping(uint256 => FundingTier) public fundingAmountToTier;

    // Milestone struct, used as a data structure for milestones in funding a project
    struct Milestone {
        // release date of milestone
        uint256 releaseDate;
        // reserve percent that milestone releases to project creator (out of 100)
        uint8 releasePercent;
        // current votes AGAINST milestone success
        uint256 currentVotesAgainst;
    }

    // Funder tier
    struct FundingTier {
        // address of the nft that each funder gets
        address reward;
        // number of people who can receive the reward
        uint8 maxBackers;
        // current number of backers
        uint8 currentBackers;
    }

    // Backer NFT Tier reward
    struct BackerNFTReward {
        // tier amount (denominated in USD)
        uint256 tierAmount;
        // token ID (as set by the NFT contract)
        uint256 tokenId;
    }

    // Enum of project possible status
    enum Status {
        STARTED,
        FUNDED,
        FINISHED,
        CANCELLED
    }

    /// @param _usdToken Address of ERC20 token used to facilitate the project
    /// @param _creator Address of the project's creator (will almost always be msg sender)
    /// @param _fundingGoal Minimum number of tokens required for a successful project
    /// @param _startTime Timestamp of sale start
    /// @param _tokenURI Pointer to IPFS storage of project details
    /// @param _milestoneReleaseDates Times we we want each milestone to RELEASE FUNDS on. The first release is actually the end date of when funds can be given to project
    /// @param _milestoneReleasePercents Corresponding percentage of total funds each milestone will release to creator
    constructor(address _usdToken, address _creator, uint256 _fundingGoal, uint256 _startTime, uint256 _tokenURI,
                        uint256[] memory _milestoneReleaseDates, uint8[] memory _milestoneReleasePercents) {

        require(_startTime > block.timestamp, "has to start sometime in the future");
        require(_creator != address(0), "no null creator addresses");
        require(_milestoneReleaseDates.length == _milestoneReleasePercents.length, "non matching lists for milestone info");
        usdToken = IERC20(_usdToken);
        creator = _creator;
        fundingGoal = _fundingGoal;
        startTime = _startTime;
        tokenURI = _tokenURI;

        uint8 sumMilestoneReleasePercent = 0;
        uint256 prevMilestoneReleaseDate = startTime;
        for (uint8 i=0;i < _milestoneReleaseDates.length; i++) {
            require(prevMilestoneReleaseDate < _milestoneReleaseDates[i], "milestones must be in order of release dates");
            Milestone memory milestone = Milestone(_milestoneReleaseDates[i], _milestoneReleasePercents[i], 0);
            milestones.push(milestone);

            sumMilestoneReleasePercent += _milestoneReleasePercents[i];
            prevMilestoneReleaseDate = _milestoneReleaseDates[i];
        }
        require(sumMilestoneReleasePercent == 100, "must eventually release all the funds to the creator");
    }

    /// @dev Require that the modified function is only called by `creator`
    modifier onlyCreator() {
        require(msg.sender == creator, "msg sender must be creator");
        _;
    }

    /// @dev Require that the modified function occurs while Status is `STARTED`
    modifier active() {
        require(currentStatus == Status.STARTED && startTime <= block.timestamp, "project is not in active state");
        _;
    }

    /// @dev Require that the modified function occurs after successful funding
    modifier funded() {
        require(currentStatus == Status.FUNDED, "project funding is not in successful state");
        _;
    }

    /*
    CREATOR FUNCTIONS
    */
    /// @notice Creator function for withdrawing funds from the raise that they are allowed to
    function withdrawFunds() external onlyCreator {
        uint256 temp = withdrawableFunds;
        withdrawableFunds = 0;  
        usdToken.transfer(creator, temp);
        emit CreatorWithdraw(creator, temp, true);
    }

    /// @notice Creator function to cancel project
    /// @notice If called after funding successful, cancelling project will only return funds that are remaining
    function cancelProject() external onlyCreator {
        require(currentStatus == Status.STARTED || currentStatus == Status.FUNDED, "project must be in either started or funded state to cancel");
        currentStatus = Status.CANCELLED;
    }

    /// @notice Creator function to assign tiers onto a project
    /// @param _tierAmounts Tier amount list used for mapping
    /// @param _tierRewards Tier reward (NFT address) that a backer will receive as a mint whenever they match a tier
    /// @param _maxBackers Max backers allowed to receive a tier reward
    function assignTiers(
        uint256[] memory _tierAmounts,
        address[] memory _tierRewards,
        uint8[] memory _maxBackers
    ) external onlyCreator {
        require(currentStatus == Status.STARTED, "project must be in started state");
        require(block.timestamp < startTime, "project must not yet have started accepting funds");

        require(_tierAmounts.length <= 10, "no more than 10 reward tiers");
        require(_tierAmounts.length == _tierRewards.length, "array lengths do not match");
        require(_tierRewards.length == _maxBackers.length, "array lengths do not match");

        for (uint8 i = 0; i < _tierAmounts.length; i++) {
            fundingAmountToTier[_tierAmounts[i]] = FundingTier(_tierRewards[i], _maxBackers[i], 0);
        }
    }

    /*
    BACKER FUNCTIONS
    */
    /// @notice Special function for checking the successful completion of raise
    function checkFundingSuccess() external active {
        require(milestones[currentMilestone].releaseDate >= block.timestamp, "can only be called after funding round is over");
        if (totalBackingAmount >= fundingGoal) {
            currentStatus = Status.FUNDED;
            withdrawableFunds += totalBackingAmount.mul(milestones[currentMilestone].releasePercent).div(100);
            cummulativeReleasePercent += milestones[currentMilestone].releasePercent;
            currentMilestone += 1;
        } else {
            currentStatus = Status.CANCELLED;
        }
    }

    /// @notice Back project. Allows anyone to deposit USD in exchange for voting right and tier (if they met tier)
    /// @notice Mints and transfers Tier NFT to msg.sender if they matched tier
    /// @notice In order to accurately track backings, if an address backs it multiple times, the most recent will be the one
    /// @notice accepted. This means that backings DO NOT compound, they replace
    /// @param _amount Amount a backer wishes to put into a project
    function acceptBacker(
        uint256 _amount
    ) external active {
        uint256 allowance = usdToken.allowance(msg.sender, address(this));
        require(allowance >= _amount, "backer has not given allowance to project to transfer funds");
        
        totalBackingAmount.add(_amount);
        backings[msg.sender] = backings[msg.sender].add(_amount);

        if (fundingAmountToTier[_amount].reward != address(0) &&
            fundingAmountToTier[_amount].maxBackers > fundingAmountToTier[_amount].currentBackers)
        {
            Tier reward = Tier(fundingAmountToTier[_amount].reward);
            uint256 tokenId = reward.mintTo(msg.sender);
            backerRewards[msg.sender].push(BackerNFTReward(_amount, tokenId));
        }
        usdToken.transferFrom(msg.sender, address(this), _amount);
        emit Back(msg.sender, _amount);
    }

    /// @notice Milestone vote by backers. Backers are assumed "n/a" by default and do not affect milestone checks
    /// @param _cancelVote Boolean vote on cancelling the project, where 'True' means you want to cancel
    function vote(
        bool _cancelVote
    ) external funded {
        require(backings[msg.sender] > 0, "msg sender has not backed project");
        if (cancelVotes[msg.sender] == false && _cancelVote == true) {
            cancelVotes[msg.sender] = true;
            cancelVoteCount.add(backings[msg.sender]);
        } else if (cancelVotes[msg.sender] == true && _cancelVote == false) {
            cancelVotes[msg.sender] = false;
            cancelVoteCount.sub(backings[msg.sender]);
        } else {
            revert("New vote must not match previous vote");
        }
        emit BackerVote(msg.sender, backings[msg.sender], _cancelVote);
    }

    /// @notice Milestone check, can be called by anyone. If not enough voters against, moves on to next milestone
    /// @notice If successful, increases amount of money creator can withdraw
    /// @notice If unsuccessful, marks project as cancelled, and backers can withdraw 
    function milestoneCheck() external funded {
        require(block.timestamp >= milestones[currentMilestone].releaseDate, "must be past the release date of when the milestone is over");
        if (cancelVoteCount > totalBackingAmount.div(2).add(1)) { 
            currentStatus = Status.CANCELLED;
        } else {
            withdrawableFunds = withdrawableFunds.add(totalBackingAmount.mul(milestones[currentMilestone].releasePercent).div(100));
            cummulativeReleasePercent += milestones[currentMilestone].releasePercent;
            if (currentMilestone == milestones.length - 1) {
                currentStatus == Status.FINISHED;
            } else {
                currentMilestone += 1;
            }     
        }
    }

    /// @dev Internal function to handle NFT returns (burning)
    function returnTierNFT(uint256 _amount) internal {
        if (_amount != 0) {
            bool burned = false;
            for (uint16 i;i < backerRewards[msg.sender].length; i++) {
                if (burned == true) {
                    break;
                }

                if (_amount == backerRewards[msg.sender][i].tierAmount) {
                    Tier reward = Tier(fundingAmountToTier[_amount].reward);
                    if (reward.ownerOf(backerRewards[msg.sender][i].tokenId) == msg.sender) {
                        reward.burn(backerRewards[msg.sender][i].tokenId);
                        burned = true;
                    }
                }
            }
            require(burned == true, "Must have burned one NFT. Make sure to set amount = to a tier");
        } else {
            for (uint16 i;i < backerRewards[msg.sender].length; i++) {
                BackerNFTReward memory backingReward = backerRewards[msg.sender][i];
                Tier reward = Tier(fundingAmountToTier[backingReward.tierAmount].reward);
                require(reward.ownerOf(backerRewards[msg.sender][i].tokenId) == msg.sender, "If withdrawing all, you must own all NFTs");
                reward.burn(backerRewards[msg.sender][i].tokenId);
            }
        }
    }

    /// @notice Required: Project status is either 'STARTED' or 'CANCELLED'
    /// @notice We look at cummulative release percent to see what percent is left for a backer to get back
    /// @notice NFTs are only returned if Project is in 'STARTED' state.
    /// @notice This will FAIL if you do not own all of the NFTs and try to withdraw
    /// @param _amount Optional field (setting to 0 ignores, also ignored if in 'CANCELLED' state). If included, we will check for a specicic reward to return.
    function withdrawRefund(uint256 _amount) external {
        require(currentStatus == Status.STARTED || currentStatus == Status.CANCELLED,
            "must be in either 'STARTED' or 'CANCELLED' state");
        require(backings[msg.sender] > 0, "backer has not backed project");

        
        // If this is called when project has started, will just equal full backings 
        uint256 refundAmount = backings[msg.sender].mul(100 - cummulativeReleasePercent).div(100);
        if (currentStatus == Status.STARTED) {
            if (_amount != 0) {
                refundAmount = _amount;
            }
            returnTierNFT(_amount);
            totalBackingAmount = totalBackingAmount.sub(refundAmount);
            backings[msg.sender] = 0;
        }
        usdToken.transfer(msg.sender, refundAmount);
        emit Refund(msg.sender, refundAmount);
    }

    function getBackerRewards(address _account) public view returns(BackerNFTReward[] memory rewards) {
        return backerRewards[_account];
    } 

    function getAddressBacking(address _account) public view returns(uint256 balance) {
        return backings[_account];
    } 

    function getCancelVote(address _account) public view returns(bool cancelVote) {
        return cancelVotes[_account];
    } 

    function balanceOf() public view returns(uint256 balance) {
        return usdToken.balanceOf(address(this));
    }
}