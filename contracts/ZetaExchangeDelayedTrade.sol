// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./interfaces/IZetaExchangeDelayedTrade.sol";
import "./BaseZetaExchange.sol";

contract ZetaExchangeDelayedTrade is BaseZetaExchange, IZetaExchangeDelayedTrade {
    uint32 public maxDuration = 1 weeks;

    uint32 public auctionExtensionInterval = 5 minutes;
    uint32 public minBiddingDiff = 500; //out of 10000

    mapping(bytes32 => BestBidding) internal _bestBidding;

    constructor(IWETH _WETH, address _feeReceiver) BaseZetaExchange(_WETH, _feeReceiver) {}

    function setMaxDuration(uint32 newDuration) external onlyOwner {
        require(maxDuration != newDuration, "UNCHANGED");
        maxDuration = newDuration;
        emit SetMaxDuration(newDuration);
    }

    function setAuctionExtensionInternal(uint32 newInterval) external onlyOwner {
        require(auctionExtensionInterval != newInterval, "UNCHANGED");
        auctionExtensionInterval = newInterval;
        emit SetAuctionExtensionInternal(newInterval);
    }

    function setMinBiddingDiff(uint32 newDiff) external onlyOwner {
        require(newDiff <= 10000, "INVALID_PARAM");
        require(minBiddingDiff != newDiff, "UNCHANGED");
        minBiddingDiff = newDiff;
        emit SetMinBiddingDiff(newDiff);
    }

    function cancelOrdersByOwner(bytes32[] calldata orderHashes) external override onlyOwner {
        for (uint256 i = 0; i < orderHashes.length; i++) {
            BestBidding storage __bestBidding = _bestBidding[orderHashes[i]];
            address bestBidder = __bestBidding.bidder;

            if (bestBidder != address(0)) {
                Order storage _order = _orders[orderHashes[i]];
                
                uint128[2] memory bestPrices = __bestBidding.prices;
                if (_order.orderType == OrderType.SellToken) {
                    address currency = _order.currency;
                    _transferCurrency(
                        currency,
                        address(this),
                        bestBidder,
                        (bestPrices[1] * _order.amount) / bestPrices[0]
                    );
                } else {
                    _transferTokens(
                        TokenType.ERC1155,
                        _order.token,
                        _order.tokenId,
                        _order.amount,
                        address(this),
                        bestBidder,
                        false
                    );
                }
                delete _bestBidding[orderHashes[i]];
                emit CancelBidding(orderHashes[i], bestBidder, bestPrices);
            }

            _cancelOrder(orderHashes[i]);
        }
    }

    function bestBidding(bytes32 biddingHash) external view returns (BestBidding memory) {
        return _bestBidding[biddingHash];
    }

    function _getCurrentPrice(bytes32 orderHash) internal view override returns (uint256[2] memory prices) {
        super._getCurrentPrice(orderHash);
        if (_bestBidding[orderHash].bidder != address(0)) {
            prices[0] = _bestBidding[orderHash].prices[0];
            prices[1] = _bestBidding[orderHash].prices[1];
        } else {
            prices[0] = _orders[orderHash].prices[0];
            prices[1] = _orders[orderHash].prices[1];
        }
    }

    function cancelOrders(bytes32[] calldata orderHashes) external override(BaseZetaExchange, IBaseZetaExchange) nonReentrant {
        for (uint256 i = 0; i < orderHashes.length; i++) {
            require(_orders[orderHashes[i]].maker == msg.sender, "UNAUTHORIZED");
            require(_bestBidding[orderHashes[i]].bidder == address(0), "BIDDING_EXISTS");

            _cancelOrder(orderHashes[i]);
        }
    }

    function bid(bytes32 orderHash, uint128[2] memory prices) external payable nonReentrant nonBlacklistedUser {
        require(!isCancelled[orderHash], "CANCELLED_ORDER");
        Order storage _order = _orders[orderHash];

        address orderMaker = _order.maker;
        require(orderMaker != msg.sender, "SELF_TRADE");

        uint256 amount = _order.amount;
        require(amount != 0, "ALREADY_FINISHED");

        BestBidding storage __bestBidding = _bestBidding[orderHash];
        address bestBidder = __bestBidding.bidder;

        address token = _order.token;
        address currency = _order.currency;
        require(!isBlacklistedToken[token] && !isBlacklistedToken[currency], "BLACKLISTED_TOKEN_CURRENCY");

        uint256[2] memory currentPrices = _getCurrentPrice(orderHash);

        if (_order.orderType == OrderType.SellToken) {
            if (bestBidder == address(0)) {
                require((currentPrices[0] * prices[1]) >= (currentPrices[1] * prices[0]), "INVALID_PRICE");
            } else {
                require(
                    (currentPrices[0] * prices[1]) >=
                        (((10000 + minBiddingDiff) * (currentPrices[1] * prices[0])) / 10000),
                    "INVALID_PRICE"
                );
                _transferCurrency(currency, address(this), bestBidder, (currentPrices[1] * amount) / currentPrices[0]);
            }
            uint256 totalPrice = (prices[1] * amount) / prices[0];
            _transferCurrency(currency, msg.sender, address(this), totalPrice);

            if (currency == address(0)) require(msg.value == totalPrice, "INVALID_ETH");
        } else {
            // OrderType: BuyToken
            uint256 tokenId = _order.tokenId;

            if (bestBidder == address(0)) {
                require((currentPrices[0] * prices[1]) <= (currentPrices[1] * prices[0]), "INVALID_PRICE");
                _transferTokens(TokenType.ERC1155, token, tokenId, amount, msg.sender, address(this), false);
            } else {
                require(
                    (currentPrices[0] * prices[1]) <=
                        (((10000 - minBiddingDiff) * (currentPrices[1] * prices[0])) / 10000),
                    "INVALID_PRICE"
                );
                _transferTokens(TokenType.ERC1155, token, tokenId, amount, msg.sender, bestBidder, false);
            }
        }

        __bestBidding.bidder = msg.sender;
        __bestBidding.prices = prices;

        uint32 _interval = auctionExtensionInterval;
        uint32 endTime = _order.endTime;
        if ((endTime - block.timestamp) < _interval) {
            endTime += _interval;
            _order.endTime = endTime;
            emit ExtendAuction(orderHash, endTime);
        }
        emit Bid(orderHash, msg.sender, prices);
    }

    function claim(bytes32 orderHash) external nonReentrant nonBlacklistedUser {
        Order storage _order = _orders[orderHash];
        uint32 endTime = _order.endTime;
        require(endTime < block.timestamp, "ALIVE_ORDER");

        BestBidding memory __bestBidding = _bestBidding[orderHash];
        require(__bestBidding.bidder != address(0), "NO_BIDDING");

        uint256 amount = _order.amount;
        require(amount != 0, "AMOUNT_0");

        address orderMaker = _order.maker;
        address token = _order.token;
        address currency = _order.currency;
        require(!isBlacklistedToken[token] && !isBlacklistedToken[currency], "BLACKLISTED_TOKEN_CURRENCY");

        uint256 totalPrice = (__bestBidding.prices[1] * amount) / __bestBidding.prices[0];

        _transferFeeRoyaltyCurrencyAndTokens(
            _order.orderType,
            _order.tokenType,
            token,
            _order.tokenId,
            amount,
            currency,
            totalPrice,
            __bestBidding.bidder,
            true,
            orderMaker
        );

        if (_order.orderType == OrderType.BuyToken) {
            _refundExcessCurrency(
                (((__bestBidding.prices[0] * _order.prices[1]) - (__bestBidding.prices[1] * _order.prices[0])) *
                    amount) / (__bestBidding.prices[0] * _order.prices[0]),
                currency,
                orderMaker
            );
        }

        _order.amount = 0;
        emit Claim(orderHash, __bestBidding.bidder, __bestBidding.prices);
        delete _bestBidding[orderHash];
    }

    function _checkOrderForCreation(Order memory order) internal override {
        super._checkOrderForCreation(order);

        require(order.strategy == Strategy.EnglishAuction, "ONLY_ENGLISH_AUCTION");
        require(order.prices[2] == 0 && order.prices[3] == 0, "INVALID_PRICE_PARAM");
        require(order.endTime - order.startTime <= maxDuration, "INVALID_DURATION");
    }
}
