// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./IWETH.sol";
import "./IRoyaltyDB.sol";

interface IBaseZetaExchange {
    event SetFee(TokenType indexed tokenType, uint256 fee);
    event SetFeeReceiver(address newFeeReceiver);
    event SetRoyaltyDB(IRoyaltyDB newRoyaltyDB);
    event SetMinDuration(uint32 newDuration);
    event CreateOrder(address indexed user, bytes32 indexed orderHash);
    event CancelOrder(bytes32 indexed orderhash, address indexed canceller);
    event SetBlacklistUser(address indexed user, bool indexed status);
    event SetBlacklistToken(address indexed token, bool indexed status);
    event EmergencyWithdraw(TokenType[] tokenTypes, address[] tokens, uint256[] tokenIds, uint256[] amounts);

    enum Strategy {
        FixedPrice,
        EnglishAuction,
        DutchAuction
    }
    enum OrderType {
        SellToken,
        BuyToken
    }
    enum TokenType {
        ETH,
        ERC20,
        ERC1155,
        ERC721
    }

    struct Order {
        address maker;
        OrderType orderType;
        Strategy strategy;
        TokenType tokenType;
        address token;
        uint256 tokenId;
        uint256 amount;
        uint128[4] prices; //price ratio([0] token = [1] currency). 0/1: startPrice on EA & DA, 2/3: only on DA. endPrice
        address currency; //ETH or ERC20. fee and loyalty will be deducted as currency
        uint32 startTime;
        uint32 endTime;
        uint32 salt; //for duplicated hash
    }

    function WETH() external view returns (IWETH);

    function isBlacklistedToken(address user) external view returns (bool);

    function isBlacklistedUser(address user) external view returns (bool);

    function minDuration() external view returns (uint32);

    function protocolFee(TokenType tokenType) external view returns (uint256);

    function feeReceiver() external view returns (address);

    function getOrder(bytes32 orderHash) external view returns (Order calldata);

    function getOrderHash(Order calldata order) external pure returns (bytes32);

    function getCurrentPrice(bytes32 orderHash) external view returns (uint256[2] calldata prices);

    function isCancelled(bytes32 orderHash) external view returns (bool);

    function createOrders(Order[] calldata orders_) external payable;

    function cancelOrders(bytes32[] calldata orderHashes) external;
}
