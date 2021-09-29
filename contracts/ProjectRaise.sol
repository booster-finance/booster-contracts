// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "./Tier/TierNFT.sol";


contract ProjectRaise {/// The ERC20 token used to fund the project
    IERC20 public usdToken;

    /// The address of the project's creator
    address public creator;

    /// The minimum number of tokens that must be raised
    uint256 public fundingGoal;

    /// Timestamp of the start of the project
    uint256 public startTime;

    /// IPFS pointer of project details
    string public tokenURI;

    /// Record of backings that have been made to the project
    mapping(address => BackerInfo) private backerInfoMapping;

    /// Total number of tokens backed
    uint256 public totalBackingAmount;

    /// Vote count weighted by backing amount
    uint256 public cancelVoteCount;

    // Current status of project, start at started
    Status public currentStatus = Status.STARTED;

    // Current milestone of project, start at 0
    uint8 public currentMilestone;

    // Keep track of funds that have already been allocated to creator, used for keeping track of how much a backer can get after each milestone
    uint8 private cummulativeReleasePercent;

    // Total amount of funds the creator is able to withdraw
    uint256 public withdrawableFunds;

    // Array of all milestones in project
    Milestone[] private milestones;

    // Mapping of funding amount to the tier it corresponds to
    mapping(uint256 => FundingTier) private fundingAmountToTier;

    // Array of funding reward amounts
    uint256[] private fundingTiers;

    struct BackerInfo {
        uint256 amount;
        bool cancelVote;
        BackerNFTReward[] rewards;
    }

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
    constructor(address _usdToken, address _creator, uint256 _fundingGoal, uint256 _startTime, string memory _tokenURI,
                        uint256[] memory _milestoneReleaseDates, uint8[] memory _milestoneReleasePercents) {

        require(_startTime > block.timestamp, "start < now");
        require(_creator != address(0), "null address");
        require(_milestoneReleaseDates.length == _milestoneReleasePercents.length, "lengtb");
        usdToken = IERC20(_usdToken);
        creator = _creator;
        fundingGoal = _fundingGoal;
        startTime = _startTime;
        tokenURI = _tokenURI;

        uint8 sumMilestoneReleasePercent = 0;
        uint256 prevMilestoneReleaseDate = startTime;
        for (uint8 i=0;i < _milestoneReleaseDates.length; i++) {
            require(prevMilestoneReleaseDate < _milestoneReleaseDates[i], "milestones order");
            Milestone memory milestone = Milestone(_milestoneReleaseDates[i], _milestoneReleasePercents[i], 0);
            milestones.push(milestone);

            sumMilestoneReleasePercent += _milestoneReleasePercents[i];
            prevMilestoneReleaseDate = _milestoneReleaseDates[i];
        }
        require(sumMilestoneReleasePercent == 100, "= 100");
    }

    /*
    CREATOR FUNCTIONS
    */
    /// @notice Creator function for withdrawing funds from the raise that they are allowed to
    function withdrawFunds() external {
        require(msg.sender == creator, "sender check");
        uint256 temp = withdrawableFunds;
        withdrawableFunds = 0;  
        usdToken.transfer(creator, temp);
    }

    /// @notice Creator function to cancel project
    /// @notice If called after funding successful, cancelling project will only return funds that are remaining
    function cancelProject() external {
        require(msg.sender == creator, "sender check");
        require(currentStatus == Status.STARTED || currentStatus == Status.FUNDED, "!started || !funded");
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
    ) external {
        require(msg.sender == creator, "sender check");
        require(currentStatus == Status.STARTED, "!started");
        require(block.timestamp < startTime, "now > started");

        require(_tierAmounts.length == _tierRewards.length, "!length");
        require(_tierRewards.length == _maxBackers.length, "!length");

        for (uint8 i = 0; i < _tierAmounts.length; i++) {
            require(fundingAmountToTier[_tierAmounts[i]].reward == address(0), "one per NFT/USD");
            fundingAmountToTier[_tierAmounts[i]] = FundingTier(_tierRewards[i], _maxBackers[i], 0);
            fundingTiers.push(_tierAmounts[i]);
        }
    }

    /*
    BACKER FUNCTIONS
    */
    /// @notice Special function for checking the successful completion of raise
    function checkFundingSuccess() external {
        require(currentStatus == Status.STARTED && startTime <= block.timestamp, "!started");
        require(milestones[currentMilestone].releaseDate >= block.timestamp, "now < milestone");
        if (totalBackingAmount >= fundingGoal) {
            currentStatus = Status.FUNDED;
            withdrawableFunds += totalBackingAmount * milestones[currentMilestone].releasePercent / 100;
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
    ) external {
        require(currentStatus == Status.STARTED && startTime <= block.timestamp, "!started");
        uint256 allowance = usdToken.allowance(msg.sender, address(this));
        require(allowance >= _amount, "!backer");
        
        totalBackingAmount = totalBackingAmount + _amount;
        backerInfoMapping[msg.sender].amount = backerInfoMapping[msg.sender].amount + _amount;

        if (fundingAmountToTier[_amount].reward != address(0) &&
            fundingAmountToTier[_amount].maxBackers > fundingAmountToTier[_amount].currentBackers)
        {
            Tier reward = Tier(fundingAmountToTier[_amount].reward);
            uint256 tokenId = reward.mintTo(msg.sender);
            backerInfoMapping[msg.sender].rewards.push(BackerNFTReward(_amount, tokenId));
        }
        usdToken.transferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Milestone vote by backers. Backers are assumed "n/a" by default and do not affect milestone checks
    /// @param _cancelVote Boolean vote on cancelling the project, where 'True' means you want to cancel
    function vote(
        bool _cancelVote
    ) external {
        require(currentStatus == Status.FUNDED, "!funded");
        require(backerInfoMapping[msg.sender].amount > 0, "!backer");
        if (backerInfoMapping[msg.sender].cancelVote == false && _cancelVote == true) {
            backerInfoMapping[msg.sender].cancelVote = true;
            cancelVoteCount = cancelVoteCount + backerInfoMapping[msg.sender].amount;
        } else if (backerInfoMapping[msg.sender].cancelVote == true && _cancelVote == false) {
            backerInfoMapping[msg.sender].cancelVote = false;
            cancelVoteCount = cancelVoteCount - backerInfoMapping[msg.sender].amount;
        } else {
            revert("vote=prev");
        }
    }

    /// @notice Milestone check, can be called by anyone. If not enough voters against, moves on to next milestone
    /// @notice If successful, increases amount of money creator can withdraw
    /// @notice If unsuccessful, marks project as cancelled, and backers can withdraw 
    function milestoneCheck() external {
        require(currentStatus == Status.FUNDED, "!funded");
        require(block.timestamp >= milestones[currentMilestone].releaseDate, "now < milestone");
        if (cancelVoteCount > (totalBackingAmount / 2) + 1) { 
            currentStatus = Status.CANCELLED;
        } else {
            withdrawableFunds = withdrawableFunds + totalBackingAmount * (milestones[currentMilestone].releasePercent / 100);
            cummulativeReleasePercent += milestones[currentMilestone].releasePercent;
            if (currentMilestone == milestones.length - 1) {
                currentStatus = Status.FINISHED;
            } else {
                currentMilestone += 1;
            }     
        }
    }

    /// @dev Internal function to handle NFT returns (burning)
    function returnTierNFT(uint256 _amount) internal {
        if (_amount != 0) {
            bool burned = false;
            for (uint16 i;i < backerInfoMapping[msg.sender].rewards.length; i++) {
                if (burned == true) {
                    break;
                }

                if (_amount == backerInfoMapping[msg.sender].rewards[i].tierAmount) {
                    Tier reward = Tier(fundingAmountToTier[_amount].reward);
                    if (reward.ownerOf(backerInfoMapping[msg.sender].rewards[i].tokenId) == msg.sender) {
                        reward.burn(backerInfoMapping[msg.sender].rewards[i].tokenId);
                        delete backerInfoMapping[msg.sender].rewards[i];
                        burned = true;
                    }
                }
            }
            require(burned == true, "!backerNFT");
        } else {
            for (uint16 i;i < backerInfoMapping[msg.sender].rewards.length; i++) {
                BackerNFTReward memory backingReward = backerInfoMapping[msg.sender].rewards[i];
                Tier reward = Tier(fundingAmountToTier[backingReward.tierAmount].reward);
                require(reward.ownerOf(backerInfoMapping[msg.sender].rewards[i].tokenId) == msg.sender, "!NFT ownership");
                reward.burn(backerInfoMapping[msg.sender].rewards[i].tokenId);
                delete backerInfoMapping[msg.sender].rewards[i];
            }
        }
    }

    /// @notice Required: Project status is either 'STARTED' or 'CANCELLED'
    /// @notice We look at cummulative release percent to see what percent is left for a backer to get back
    /// @notice NFTs are only returned if Project is in 'STARTED' state.
    /// @notice This will FAIL if you do not own all of the NFTs and try to withdraw
    /// @param _amount Optional field (setting to 0 ignores, also ignored if in 'CANCELLED' state). If included, we will check for a specicic reward to return.
    function withdrawRefund(uint256 _amount) external {
        require(currentStatus == Status.STARTED || currentStatus == Status.CANCELLED, "!started || !cancelled");
        require(backerInfoMapping[msg.sender].amount > 0, "!backer");

        
        // If this is called when project has started, will just equal full backings 
        uint256 refundAmount = (backerInfoMapping[msg.sender].amount * 100) - (cummulativeReleasePercent / 100);
        if (currentStatus == Status.STARTED) {
            if (_amount != 0) {
                refundAmount = _amount;
            }
            returnTierNFT(_amount);
            totalBackingAmount = totalBackingAmount - refundAmount;
            backerInfoMapping[msg.sender].amount = 0;
        }
        usdToken.transfer(msg.sender, refundAmount);
    }

    function getFundingTiers() public view returns(FundingTier[] memory tiers, uint256[] memory values) {
        FundingTier[] memory _fundingTiers = new FundingTier[](fundingTiers.length);
        uint256[] memory _values = new uint256[](fundingTiers.length);
        for (uint8 i;i < fundingTiers.length; i++) {
            _fundingTiers[i] = fundingAmountToTier[fundingTiers[i]];
            _values[i] = fundingTiers[i];
        }
        return (_fundingTiers, _values);
    }

    function getMilestones() public view returns(Milestone[] memory) {
        return milestones;
    }

    function getBackerRewards(address _account) public view returns(BackerNFTReward[] memory rewards) {
        return backerInfoMapping[_account].rewards;
    }

    function getAddressBacking(address _account) public view returns(uint256 balance) {
        return backerInfoMapping[_account].amount;
    }

    function getCancelVote(address _account) public view returns(bool cancelVote) {
        return backerInfoMapping[_account].cancelVote;
    }

    function balanceOf() public view returns(uint256 balance) {
        return usdToken.balanceOf(address(this));
    }
}