// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * This is a generic interface contract for the functionality a Tier NFT needs to adhere to.
 * We believe there can be many unique expansions of this, including P2E, loot boxes, and more,
 * as we explore how project backing reward NFTs can function and be used as a mechanism for incentiving backers.
 */
interface ITierNFT {
    /**
     * @dev Returns a URL specifying some metadata about the option. This metadata can be of the
     * same structure as the ERC721 metadata.
     */
    function tokenURI() external view returns (string memory);

    /**
     * @dev Mints asset(s) in accordance to a specific address. This should be
     * callable only by the Project Raise contract.
     * @param _toAddress address of the future owner of the asset(s)
     */
    function mintTo(address _toAddress) external;

    /**
     * @dev Burns an asset in accordance to a specific token ID. This should be
     * callable only by the Project Raise contract.
     * @param _tokenId the token id
     */
    function burn(uint256 _tokenId) external;
}
