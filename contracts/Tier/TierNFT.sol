// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721Mintable.sol";

/**
 * @title Tier
 * Tier - a contract for representing a reward tier in a project raise on booster finance.
 */
contract Tier is ERC721Mintable {
    
    constructor(address _proxyMintingAddress)
        ERC721Mintable("Tier", "TIER", _proxyMintingAddress)
    {}

    function baseTokenURI() override public pure returns (string memory) {
        return "https://ipfs.io/ipfs/";
    }

    function contractURI() public pure returns (string memory) {
        return "https://github.com/booster-finance/booster-contracts";
    }
}