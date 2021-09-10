// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


contract MintingProxy {}

contract ProxyRegistry {
    mapping(address => MintingProxy) public proxies;
}

/**
 * @title ERC721Mintable
 * ERC721Mintable - ERC721 contract that whitelists a minting address.
 * Also includes storage management for URIs
 */
abstract contract ERC721Mintable is ERC721Enumerable {
    using SafeMath for uint256;
    using Strings for uint256;

    address public proxyMintingAddress;
    uint256 private _currentTokenId = 0;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    constructor(
        string memory _name,
        string memory _symbol,
        address _proxyMintingAddress
    ) ERC721(_name, _symbol) {
        proxyMintingAddress = _proxyMintingAddress;
    }

    modifier onlyMintingAddress() {
        require(msg.sender == proxyMintingAddress, "Only the minting address may call this function");
        _;
    }

    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mintTo(address _to) public onlyMintingAddress returns(uint256 tokenId) {
        uint256 newTokenId = _getNextTokenId();
        _mint(_to, newTokenId);
        _incrementTokenId();
        return newTokenId;
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId.add(1);
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

    function baseTokenURI() virtual public pure returns (string memory);

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721URIStorage: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev Burns an NFT. Can only be called by minting address (project raise contract)
     * @param _tokenId token ID that we are looking to burn
     */
    function burn(uint256 _tokenId) public onlyMintingAddress {
        _burn(_tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
    }
}