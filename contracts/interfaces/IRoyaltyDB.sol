// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

interface IRoyaltyDB {
    event SetMaxRoyalty(uint16 newMaxRoyalty);
    event SetRoyaltyInfo(address indexed token, uint16 royalty, address indexed recipient);
    event UpdateSigner(address newSigner);

    struct RoyaltyInfo {
        uint16 royalty; //out of 10000
        address recipient;
    }

    function maxRoyalty() external view returns (uint16);

    function signer() external view returns (address);

    function signingNonce() external view returns (uint96);

    function royaltyInfoOf(address token) external view returns (RoyaltyInfo memory);

    function setRoyaltyInfo(
        address token,
        uint16 royalty,
        address recipient,
        bytes calldata signature
    ) external;
}
