// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./IBaseZetaExchange.sol";

interface IZetaExchangeDelayedTrade is IBaseZetaExchange {
    event SetMaxDuration(uint32 newDuration);
    event SetAuctionExtensionInternal(uint32 newInternal);
    event SetMinBiddingDiff(uint32 newDiff);
    event Bid(bytes32 indexed orderHash, address indexed bidder, uint128[2] biddingPrices);
    event Claim(bytes32 indexed orderHash, address indexed bestBidder, uint128[2] bestBiddingPrices);
    event ExtendAuction(bytes32 indexed orderHash, uint32 endTime);
    event CancelBidding(bytes32 indexed orderHash, address indexed bestBidder, uint128[2] bestBiddingPrices);

    struct BestBidding {
        address bidder;
        uint128[2] prices;
    }

    function maxDuration() external view returns (uint32);

    function auctionExtensionInterval() external view returns (uint32);

    function minBiddingDiff() external view returns (uint32);

    function bestBidding(bytes32 biddingHash) external view returns (BestBidding calldata);

    function bid(bytes32 orderHash, uint128[2] memory prices) external payable;

    function claim(bytes32 orderHash) external;
}
