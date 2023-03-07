// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IRoyaltyDB.sol";

contract RoyaltyDB is Ownable, IRoyaltyDB {
    uint16 public maxRoyalty = 1000;
    mapping(address => RoyaltyInfo) internal _royalties;

    address public signer;
    uint96 public signingNonce;

    function royaltyInfoOf(address token) external view returns (RoyaltyInfo memory) {
        return _royalties[token];
    }

    function setMaxRoyalty(uint16 newMaxRoyalty) external onlyOwner {
        require(newMaxRoyalty <= 10000, "OUT_OF_RANGE");
        maxRoyalty = newMaxRoyalty;
        emit SetMaxRoyalty(newMaxRoyalty);
    }

    function updateSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "SIGNER_ADDRESS_0");
        require(signer != newSigner, "UNCHANGED");

        signer = newSigner;
        emit UpdateSigner(newSigner);
    }

    function setRoyaltyInfo(
        address token,
        uint16 royalty,
        address recipient,
        bytes calldata signature
    ) external {
        if (msg.sender != owner()) {
            bytes32 hash = keccak256(
                abi.encodePacked(block.chainid, address(this), token, royalty, recipient, signingNonce++)
            );
            bytes32 message = ECDSA.toEthSignedMessageHash(hash);
            address _signer = ECDSA.recover(message, signature);
            require(signer == _signer, "INVALID_SIGNER");
        }

        require(royalty <= maxRoyalty, "OUT_OF_RANGE");
        _royalties[token].royalty = royalty;
        _royalties[token].recipient = recipient;
        emit SetRoyaltyInfo(token, royalty, recipient);
    }
}
