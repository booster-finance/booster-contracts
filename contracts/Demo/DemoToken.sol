// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 

/**
 * @title Demo Token for local testing
 */

/// @title Demo USD Token (dUSD)
/// @notice ERC20 compatible token for mirroring USD Token Contract
contract DemoToken is Ownable {
    using SafeMath for uint256;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    string public name = "DemoUSD";
    string public symbol = "dUSD";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    /// Flag for only allowing a single token initialization
    bool public initialized = false;

    /// Account balances
    mapping(address => uint256) public balances;

    /// Allowances for transferring on behalf of another address
    mapping(address => mapping(address => uint256)) internal allowed;

    /// @notice Set initial token allocations, which can only happen once
    /// @param addresses Addresses of beneficiaries
    /// @param allocations Amounts to allocate each beneficiary
    function initialize(address[] memory addresses, uint256[] memory allocations) public onlyOwner {
        require(!initialized, "can only call this function");
        require(addresses.length == allocations.length, "must be matching array lengths");
        initialized = true;

        for(uint i=0; i<allocations.length; i+=1) {
            balances[addresses[i]] = allocations[i];
        }
    }

    /// @notice Disallow ETH transfers
    fallback () external {}

    /// @dev Gets the balance of the specified address.
    /// @param _owner The address to query the the balance of.
    /// @return balance A uint256 of the amount owned by _owner
    function balanceOf(address _owner) public view returns(uint256 balance) {
        return balances[_owner];
    }

    /// @dev Transfer token to a specified address
    /// @param _to The address to transfer to.
    /// @param _value The amount to be transferred.
    function transfer(address _to, uint256 _value) public returns(bool) {
        require(_to != address(0), "no null addresses");
        require(_value <= balances[msg.sender], "cannot transfer more than address owns");

        // SafeMath.sub will throw if there is not enough balance.
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    /// @dev Transfer tokens from _from to _to
    /// @param _from address The address which you want to send tokens from
    /// @param _to address The address which you want to transfer to
    /// @param _value uint256 the amount of tokens to be transferred
    function transferFrom(address _from, address _to, uint256 _value) public returns(bool) {
        require(_to != address(0), "no null addresses");
        require(_value <= balances[_from], "cannot transfer more than address owns");
        require(_value <= allowed[_from][msg.sender], "cannot transfer more than address has allowed to be transfered");

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    /// @dev Allow the passed address to spend _value tokens on behalf of msg.sender.
    /// Beware double spend https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    /// @param _spender The address which will spend the funds.
    /// @param _value The amount of tokens to be spent.
    function approve(address _spender, uint256 _value) public returns(bool) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /// @dev Check the amount of tokens _owner has approved for _spender.
    /// @param _owner address Owner of the tokens.
    /// @param _spender address Token grantee
    /// @return The amount of tokens available to the spender.
    function allowance(address _owner, address _spender) public view returns(uint256) {
        return allowed[_owner][_spender];
    }
}