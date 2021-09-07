pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


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

    /// @notice Emits when a backer votes to refund or not
    /// @param backer The address of the project creator
    /// @param amount The value of the vote
    /// @param vote True if they voted to refund
    event BackerVote(address indexed backer, uint256 amount, bool vote);

    /// The ERC20 token used to fund the project
    IERC20 public usdToken;

    /// The address of the project's creator
    address public creator;

    /// The minimum number of tokens that must be raised
    uint256 public fundingGoal;

    /// Timestamp of the start of the project
    uint256 public startTime;

    /// Record of backings that have been made to the project
    mapping(address => uint256) public backings;

    /// Total number of tokens backed
    uint256 public totalBackingAmount;

    /// Record that indicates whether a backer has voted to deny funds to `creator`
    mapping(address => bool) public refundVotes;

    /// Vote count weighted by backing amount
    uint256 public refundVoteCount;

    // current status of project, start at initialized
    Status public currentStatus = Status.INITIALIZED;

    // current milestone of project, start at 0
    uint8 public currentMilestone = 0;

    // total amount of funds the creator is able to withdraw
    uint256 public withdrawableFunds;

    // array of all milestones in project
    Milestone[] public milestones;

    // mapping of funding amount to the tier it corresponds to
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

    // enum of project possible status
    enum Status {
        INITIALIZED,
        STARTED,
        FUNDED,
        FINISHED,
        CANCELLED
    }

    /// @param _usdToken Address of ERC20 token used to facilitate the project
    /// @param _creator Address of the project's creator (will almost always be msg sender)
    /// @param _fundingGoal Minimum number of tokens required for a successful project
    /// @param _startTime Timestamp of sale start
    /// @param _milestoneReleaseDates Times we we want each milestone to RELEASE FUNDS on. The first release is actually the end date of when funds can be given to project
    /// @param _milestoneReleasePercents Corresponding percentage of total funds each milestone will release to creator
    constructor(address _usdToken, address _creator, uint256 _fundingGoal, uint256 _startTime,
                        uint256[] memory _milestoneReleaseDates, uint8[] memory _milestoneReleasePercents) {

        require(_startTime > block.timestamp, "has to start sometime in the future");
        require(_creator != address(0), "no null creator addresses");
        require(_milestoneReleaseDates.length == _milestoneReleasePercents.length, "Non matching lists for milestone info");
        usdToken = IERC20(_usdToken);
        creator = _creator;
        fundingGoal = _fundingGoal;
        startTime = _startTime;
        for (uint8 i=0;i < _milestoneReleaseDates.length; i++) {
            Milestone memory milestone = Milestone(_milestoneReleaseDates[i], _milestoneReleasePercents[i], 0);
            milestones.push(milestone);
        }

    }

    /// @dev Require that the modified function is only called by `creator`
    modifier onlyCreator() {
        require(msg.sender == creator, "msg sender must be creator");
        _;
    }

    /// @dev Require that the modified function occurs while Status is `INITIALIZED`
    modifier initialized() {
        require(currentStatus == Status.INITIALIZED, "project is no longer initialized");
        _;
    }

    /// @dev Require that the modified function occurs while Status is `STARTED`
    modifier active() {
        require(currentStatus == Status.FUNDED, "project is no longer active");
        _;
    }

    /// @dev Require that the modified function occurs after successful funding
    modifier funded() {
        require(currentStatus == Status.FUNDED, "project funding is not in successful state");
        _;
    }

    /// @notice Creator function for withdrawing funds from the raise that they are allowed to
    function withdrawFunds() external onlyCreator {
        uint256 temp = withdrawableFunds;
        withdrawableFunds = 0;  
        usdToken.transfer(creator, temp);
    }

    /// @notice Special function for checking the successful completion of raise
    function checkFundingSuccess() external active {
        currentStatus = Status.FUNDED;
        // TODO: increase creator withdrawable funds
        currentMilestone += 1;
    }

    /// @notice Back project. Allows anyone to deposit USD in exchange for voting right and tier (if they met tier)
    /// @notice Mints and transfers Tier NFT to msg.sender if they matched tier
    /// @notice In order to accurately track backings, if an address backs it multiple times, the most recent will be the one
    /// @notice accepted. This means that backings DO NOT compound, they replace
    function acceptBacker() external active {
        uint256 allowance = usdToken.allowance(msg.sender, address(this));
        require(allowance > 0, "backeer has not given allowance to project to transfer funds");
        // TODO: handle address that has already funded
        totalBackingAmount.add(allowance);

        backings[msg.sender] = allowance;
        usdToken.transferFrom(msg.sender, address(this), allowance);
        emit Back(msg.sender, allowance);
    }

    /// @notice Record backer vote
    function vote(bool shouldRefund) external funded {
        require(backings[msg.sender] > 0, "msg sender has not backed project");
        if (refundVotes[msg.sender] == false && shouldRefund == true) {
            refundVotes[msg.sender] = true;
            refundVoteCount.add(backings[msg.sender]);
            emit BackerVote(msg.sender, backings[msg.sender], true);
        } else if (refundVotes[msg.sender] == true && shouldRefund == false) {
            refundVotes[msg.sender] = false;
            refundVoteCount.sub(backings[msg.sender]);
            emit BackerVote(msg.sender, backings[msg.sender], false);
        }
        // TODO
    }

    /// @notice Milestone vote, can be called by anyone. If not enough voters against, moves on to next milestone
    /// @notice If successful, increases amount of money creator can withdraw
    /// @notice If unsuccessful, marks project as cancelled, and backers can withdraw 
    function milestoneCheck() external funded {
        // TODO: add checks
        currentMilestone += 1;
    }

    /// @notice First if: Return tokens to sender if they are a valid backer 
    /// and funding wasn't reached
    /// @notice Second if: Return half tokens to sender if they are a valid backer 
    /// and refundVoteCount > totalBackingAmount/2
    function withdrawRefund() external funded {
        require(backings[msg.sender] > 0, "backer has not backed project");
        uint256 refundAmount;
        if (totalBackingAmount < fundingGoal) {
            refundAmount = backings[msg.sender];
            backings[msg.sender] = 0;
            usdToken.transfer(msg.sender, refundAmount);
        } else if (refundVoteCount > totalBackingAmount/2) {
            refundAmount = backings[msg.sender]/2;
            backings[msg.sender] = 0;
            usdToken.transfer(msg.sender, refundAmount);
        }

    }

    function getTotalBackingAmount() public view returns(uint256) {
        return totalBackingAmount;
    }

    function getRefundVoteCount() public view returns(uint256) {
        return refundVoteCount;
    }

    function getAddressBacking(address _account) public view returns(uint256 balance) {
        return backings[_account];
    } 

    function getRefundVote(address _account) public view returns(bool refundVote) {
        return refundVotes[_account];
    } 

    function balanceOf() public view returns(uint256 balance) {
        return address(this).balance;
    }
}