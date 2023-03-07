// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./IBaseZetaExchange.sol";

interface IZetaExchangeInstantTrade is IBaseZetaExchange {
    event FillOrder(bytes32 indexed orderHash, address indexed taker, bool indexed isFilledAll, uint256 amountFilled);

    function fillOrders(
        bytes32[] calldata orderHashes,
        uint256[] calldata amounts,
        bool shouldPassExactly
    ) external payable;

    function createOrderWithFilling(Order memory orderA, bytes32[] calldata orderHashes) external payable;
}
