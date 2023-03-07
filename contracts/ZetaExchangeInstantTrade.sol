// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./interfaces/IZetaExchangeInstantTrade.sol";
import "./BaseZetaExchange.sol";

contract ZetaExchangeInstantTrade is BaseZetaExchange, IZetaExchangeInstantTrade {
    constructor(IWETH _WETH, address _feeReceiver) BaseZetaExchange(_WETH, _feeReceiver) {}

    function _getCurrentPrice(bytes32 orderHash) internal view override returns (uint256[2] memory prices) {
        super._getCurrentPrice(orderHash);
        Order storage _order = _orders[orderHash];
        if (_order.strategy == Strategy.FixedPrice) {
            prices[0] = _order.prices[0];
            prices[1] = _order.prices[1];
        } else {
            //DutchAuction
            uint32 startTime = _order.startTime;
            uint256 totalTime = _order.endTime - startTime;
            uint256 timeElapsed = block.timestamp - startTime;

            uint128[4] memory _prices = _order.prices;

            uint256 numerator = _prices[1] * _prices[2] * totalTime;
            if (_order.orderType == OrderType.SellToken) {
                numerator -= ((_prices[1] * _prices[2]) - (_prices[0] * _prices[3])) * timeElapsed;
            } else {
                numerator += ((_prices[0] * _prices[3]) - (_prices[1] * _prices[2])) * timeElapsed;
            }

            prices[0] = _prices[0] * _prices[2] * totalTime;
            prices[1] = numerator;
        }
    }

    function fillOrders(
        bytes32[] calldata orderHashes,
        uint256[] calldata amounts,
        bool shouldPassExactly
    ) external payable nonReentrant nonBlacklistedUser {
        require(orderHashes.length == amounts.length, "LENGTH_NOT_EQUAL");
        uint256 totalETHFromTaker;
        for (uint256 i = 0; i < orderHashes.length; i++) {
            require(
                !isBlacklistedToken[_orders[orderHashes[i]].token] &&
                    !isBlacklistedToken[_orders[orderHashes[i]].currency],
                "BLACKLISTED_TOKEN_CURRENCY"
            );

            uint256 ETHFromTaker = _fillOrder(orderHashes[i], amounts[i], shouldPassExactly);
            totalETHFromTaker += ETHFromTaker;
        }
        if (totalETHFromTaker > 0) {
            require(totalETHFromTaker <= msg.value, "INVALID_MSG_VALUE");
            _transferTokens(TokenType.ETH, address(0), 0, totalETHFromTaker, msg.sender, address(this), true);
        } else {
            require(msg.value == 0, "INVALID_MSG_VALUE");
        }
    }

    function createOrderWithFilling(Order memory orderA, bytes32[] calldata orderHashes)
        external
        payable
        nonReentrant
        nonBlacklistedUser
    {
        if (orderA.startTime == 0) orderA.startTime = uint32(block.timestamp);
        _checkOrderForCreation(orderA);
        require(orderA.strategy == Strategy.FixedPrice, "SHOULD_BE_FP");
        require(orderHashes.length != 0, "Orders_0");

        uint256 totalETHFromTaker;
        uint256 amountRemained = orderA.amount;

        uint256 _case;
        if (orderA.tokenType <= TokenType.ERC20) _case = 0;
        else if (orderA.orderType == OrderType.SellToken) _case = 1;
        else if (orderA.orderType == OrderType.BuyToken) _case = 2;

        for (uint256 i = 0; i < orderHashes.length; i++) {
            Order storage orderB = _orders[orderHashes[i]];
            uint256 amountB = orderB.amount;
            if (amountB == 0) continue;
            bool orderMatched;
            if (_case == 0) {
                require(orderB.tokenType <= TokenType.ERC20, "INVALID_TOKENTYPE");
                orderMatched = orderB.currency == orderA.token && orderB.token == orderA.currency;
            } else if (_case == 1) {
                orderMatched =
                    orderB.orderType == OrderType.BuyToken &&
                    orderA.tokenType == orderB.tokenType &&
                    orderA.token == orderB.token &&
                    orderA.tokenId == orderB.tokenId &&
                    orderA.currency == orderB.currency;
            } else {
                orderMatched =
                    orderB.orderType == OrderType.SellToken &&
                    orderA.tokenType == orderB.tokenType &&
                    orderA.token == orderB.token &&
                    orderA.tokenId == orderB.tokenId &&
                    orderA.currency == orderB.currency;
            }
            require(orderMatched, "UNMATCHED_ORDER");

            uint256[2] memory pricesB = _getCurrentPrice(orderHashes[i]);
            bool priceMatched;
            if (_case == 0) {
                priceMatched = (orderA.prices[0] * pricesB[0]) >= (orderA.prices[1] * pricesB[1]);
            } else if (_case == 1) {
                priceMatched = (orderA.prices[1] * pricesB[0]) <= (orderA.prices[0] * pricesB[1]);
            } else {
                priceMatched = (orderA.prices[1] * pricesB[0]) >= (orderA.prices[0] * pricesB[1]);
            }
            require(priceMatched, "INVALID_PRICE");

            if (_case == 0) {
                uint256 tokensFromB = (amountB * pricesB[1]) / pricesB[0];
                if (amountRemained >= tokensFromB) {
                    uint256 ETHFromTaker = _fillOrder(orderHashes[i], amountB, false);
                    amountRemained -= tokensFromB;
                    totalETHFromTaker += ETHFromTaker;
                } else {
                    uint256 ETHFromTaker = _fillOrder(
                        orderHashes[i],
                        (amountRemained * pricesB[0]) / pricesB[1],
                        false
                    );
                    amountRemained = 0;
                    totalETHFromTaker += ETHFromTaker;
                }
            } else {
                if (amountRemained >= amountB) {
                    uint256 ETHFromTaker = _fillOrder(orderHashes[i], amountB, false);
                    amountRemained -= amountB;
                    totalETHFromTaker += ETHFromTaker;
                } else {
                    uint256 ETHFromTaker = _fillOrder(orderHashes[i], amountRemained, false);
                    amountRemained = 0;
                    totalETHFromTaker += ETHFromTaker;
                }
            }
            if (amountRemained == 0) break;
        }

        if (amountRemained != 0 && _getHighestPrice(orderA.prices, amountRemained) != 0) {
            orderA.amount = amountRemained;
            _createOrder(orderA);
            if (orderA.tokenType == TokenType.ETH) {
                totalETHFromTaker += amountRemained;
            } else if (orderA.orderType == OrderType.BuyToken && orderA.currency == address(0)) {
                totalETHFromTaker += _getHighestPrice(orderA.prices, amountRemained);
            }
        }

        if (totalETHFromTaker > 0) {
            require(totalETHFromTaker <= msg.value, "INVALID_MSG_VALUE");
            _transferTokens(TokenType.ETH, address(0), 0, totalETHFromTaker, msg.sender, address(this), true);
        } else {
            require(msg.value == 0, "INVALID_MSG_VALUE");
        }
    }

    function _checkOrderForCreation(Order memory order) internal override {
        super._checkOrderForCreation(order);
        if (order.strategy == Strategy.FixedPrice) {
            require(order.prices[2] == 0 && order.prices[3] == 0, "INVALID_PRICE_PARAM");
        } else {
            require(order.strategy == Strategy.DutchAuction, "SHOULD_BE_DA");
            require(order.prices[2] > 0 && order.prices[3] > 0, "INVALID_PRICES23");
            require((order.prices[3] * order.amount) / order.prices[2] > 0, "INVALID_PRICE_AMOUNT23");

            uint256 price0 = (order.prices[1] * order.amount) / order.prices[0];
            uint256 price1 = (order.prices[3] * order.amount) / order.prices[2];
            uint256 priceDiff = order.orderType == OrderType.SellToken ? price0 - price1 : price1 - price0;

            require(priceDiff / (order.endTime - order.startTime) != 0, "INVALID_PRICE_TIME");
        }
    }

    function _fillOrder(
        bytes32 orderHash,
        uint256 amountToFill, //amount of token
        bool shouldPassExactly
    ) internal returns (uint256 ETHFromTaker) {
        Order storage _order = _orders[orderHash];
        address currency = _order.currency;

        require(amountToFill != 0, "AMOUNT_TO_FILL_0");

        uint256 amount = _order.amount;
        if (amount == 0) return 0;

        Strategy strategy = _order.strategy;
        if (shouldPassExactly || strategy == Strategy.DutchAuction) {
            require(amountToFill == amount, "INVALID_AMOUNT_TO_FILL");
        }

        if (amountToFill > amount) amountToFill = amount;

        uint256[2] memory prices = _getCurrentPrice(orderHash);
        address orderMaker = _order.maker;
        require(orderMaker != msg.sender, "SELF_TRADE");

        TokenType tokenType = _order.tokenType;
        uint256 totalPrice = (prices[1] * amountToFill) / prices[0];

        {
            uint256 amountRemained = amount - amountToFill;
            if ((prices[1] * amountRemained) / prices[0] == 0) _order.amount = 0;
            else _order.amount = amountRemained;
        }

        _transferFeeRoyaltyCurrencyAndTokens(
            _order.orderType,
            tokenType,
            _order.token,
            _order.tokenId,
            amountToFill,
            currency,
            totalPrice,
            msg.sender,
            false,
            orderMaker
        );

        if (_order.orderType == OrderType.SellToken) {
            if (currency == address(0)) ETHFromTaker = totalPrice;
        } else if (strategy == Strategy.DutchAuction) {
            _refundExcessCurrency(
                (((_order.prices[3] * prices[0]) - (_order.prices[2] * prices[1])) * amountToFill) /
                    (_order.prices[2] * prices[0]),
                currency,
                orderMaker
            );
        }
        emit FillOrder(orderHash, msg.sender, amountToFill == amount, amountToFill);
    }
}
