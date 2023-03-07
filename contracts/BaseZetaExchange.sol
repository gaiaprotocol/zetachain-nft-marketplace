// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./interfaces/IBaseZetaExchange.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./libraries/ERC1155Holder.sol";

abstract contract BaseZetaExchange is ERC1155Holder, Ownable, ReentrancyGuard, IBaseZetaExchange {
    using Address for address;
    using SafeERC20 for IERC20;

    IWETH public immutable WETH;
    IRoyaltyDB public royaltyDB;

    mapping(TokenType => uint256) public protocolFee; //out of 10000
    address public feeReceiver;

    mapping(bytes32 => Order) internal _orders;
    mapping(bytes32 => bool) public isCancelled;

    mapping(address => bool) public isBlacklistedUser;
    mapping(address => bool) public isBlacklistedToken;

    uint32 public minDuration = 15 minutes;

    constructor(IWETH _WETH, address _feeReceiver) {
        WETH = _WETH;
        feeReceiver = _feeReceiver;

        protocolFee[TokenType.ETH] = 30;
        protocolFee[TokenType.ERC20] = 30;
        protocolFee[TokenType.ERC1155] = 250;
        protocolFee[TokenType.ERC721] = 250;
    }

    // modifier
    modifier nonBlacklistedUser() {
        require(!isBlacklistedUser[msg.sender], "BLACKLISTED_USER");
        _;
    }

    // ownership functions
    function setFee(TokenType tokenType, uint256 fee) external onlyOwner {
        require(fee <= 10000, "INVALID_FEE");
        require(protocolFee[tokenType] != fee, "UNCHANGED");
        protocolFee[tokenType] = fee;
        emit SetFee(tokenType, fee);
    }

    function setFeeReceiver(address newFeeReceiver) external onlyOwner {
        require(feeReceiver != newFeeReceiver, "UNCHANGED");
        feeReceiver = newFeeReceiver;
        emit SetFeeReceiver(newFeeReceiver);
    }

    function setRoyaltyDB(IRoyaltyDB newRoyaltyDB) external onlyOwner {
        require(royaltyDB != newRoyaltyDB, "UNCHANGED");
        royaltyDB = newRoyaltyDB;
        emit SetRoyaltyDB(newRoyaltyDB);
    }

    function setMinDuration(uint32 newDuration) external onlyOwner {
        require(minDuration != newDuration, "UNCHANGED");
        minDuration = newDuration;
        emit SetMinDuration(newDuration);
    }

    function setBlacklistUsers(address[] calldata users, bool[] calldata status) external onlyOwner {
        require(users.length == status.length, "LENGTH_NOT_EQUAL");
        for (uint256 i = 0; i < status.length; i++) {
            isBlacklistedUser[users[i]] = status[i];
            emit SetBlacklistUser(users[i], status[i]);
        }
    }

    function setBlacklistTokens(address[] calldata tokens, bool[] calldata status) external onlyOwner {
        require(tokens.length == status.length, "LENGTH_NOT_EQUAL");
        for (uint256 i = 0; i < status.length; i++) {
            isBlacklistedToken[tokens[i]] = status[i];
            emit SetBlacklistToken(tokens[i], status[i]);
        }
    }

    function cancelOrdersByOwner(bytes32[] calldata orderHashes) external virtual onlyOwner {
        for (uint256 i = 0; i < orderHashes.length; i++) {
            _cancelOrder(orderHashes[i]);
        }
    }

    function emergencyWithdraw(
        TokenType[] calldata tokenTypes,
        address[] calldata tokens,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external onlyOwner {
        uint256 length = tokenTypes.length;
        require(length == tokens.length && length == tokenIds.length && length == amounts.length, "LENGTH_NOT_EQUAL");

        for (uint256 i = 0; i < length; i++) {
            _transferTokens(tokenTypes[i], tokens[i], tokenIds[i], amounts[i], address(this), msg.sender, false);
        }
        emit EmergencyWithdraw(tokenTypes, tokens, tokenIds, amounts);
    }

    // public/external view/pure functions
    function getOrder(bytes32 orderHash) external view returns (Order memory) {
        return _orders[orderHash];
    }

    //@return prices[0] token <-> prices[1] currency
    function getCurrentPrice(bytes32 orderHash) external view returns (uint256[2] memory prices) {
        return _getCurrentPrice(orderHash);
    }

    function getOrderHash(Order calldata order) external pure returns (bytes32) {
        return _getOrderHash(order);
    }

    // internal view/pure functions
    function _getCurrentPrice(bytes32 orderHash) internal view virtual returns (uint256[2] memory prices) {
        require(_orders[orderHash].startTime <= block.timestamp, "NOT_STARTED_YET");
        require(_orders[orderHash].endTime >= block.timestamp, "OUTDATED");
    }

    function _getOrderHash(Order memory order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    order.maker,
                    order.orderType,
                    order.strategy,
                    order.tokenType,
                    order.token,
                    order.tokenId,
                    order.amount,
                    order.prices,
                    order.currency,
                    order.startTime,
                    order.endTime,
                    order.salt
                )
            );
    }

    function _currencyTypeOf(address currency) internal pure returns (TokenType) {
        return currency == address(0) ? TokenType.ETH : TokenType.ERC20;
    }

    function _getHighestPrice(uint128[4] memory prices, uint256 amount) internal pure returns (uint256) {
        uint256 price0 = (prices[1] * amount) / prices[0];
        if (prices[2] != 0) {
            uint256 price1 = (prices[3] * amount) / prices[2];
            return price0 > price1 ? price0 : price1;
        } else {
            return price0;
        }
    }

    // external functions
    function createOrders(Order[] calldata orders_) external payable nonReentrant nonBlacklistedUser {
        uint256 totalETH;
        for (uint256 i = 0; i < orders_.length; i++) {
            if (orders_[i].tokenType == TokenType.ETH) {
                totalETH += orders_[i].amount;
            } else if (orders_[i].orderType == OrderType.BuyToken && orders_[i].currency == address(0)) {
                totalETH += _getHighestPrice(orders_[i].prices, orders_[i].amount);
            }
            _createOrder(orders_[i]);
        }
        if (totalETH > 0 || msg.value > 0) {
            require(msg.value == totalETH, "INVALID_ETH_AMOUNT");
        }
    }

    function cancelOrders(bytes32[] calldata orderHashes) external virtual nonReentrant nonBlacklistedUser {
        for (uint256 i = 0; i < orderHashes.length; i++) {
            require(_orders[orderHashes[i]].maker == msg.sender, "UNAUTHORIZED");
            _cancelOrder(orderHashes[i]);
        }
    }

    // internal functions
    function _checkOrderForCreation(Order memory order) internal virtual {
        require(order.maker == msg.sender, "INVALID_MAKER");
        require(order.amount > 0, "AMOUNT_0");
        require(order.token != order.currency, "TOKEN_CURRENCY_SAME");

        require(order.startTime >= uint32(block.timestamp), "INVALID_STARTTIME");
        require(order.endTime - order.startTime > minDuration, "OUT_OF_RANGE_DURATION");
        require(order.prices[0] > 0 && order.prices[1] > 0, "INVALID_PRICES01");
        require((order.prices[1] * order.amount) / order.prices[0] > 0, "INVALID_PRICE_AMOUNT");

        require(!isBlacklistedToken[order.token], "BLACKLISTED_TOKEN");
        require(!isBlacklistedToken[order.currency], "BLACKLISTED_CURRENCY");

        if (order.tokenType <= TokenType.ERC20) {
            require(order.orderType == OrderType.SellToken, "INVALID_ORDERTYPE");
            require(order.strategy == Strategy.FixedPrice, "SHOULD_BE_FP");
            require(order.tokenId == 0, "INVALID_TOKEN_ID");
        } else if (order.tokenType == TokenType.ERC721) {
            require(order.amount == 1, "INVALID_AMOUNT");

            if (order.orderType == OrderType.BuyToken) {
                require(order.strategy == Strategy.FixedPrice, "SHOULD_BE_FP");
            }
        }
        if (order.tokenType == TokenType.ETH) {
            require(order.token == address(0), "INVALID_TOKEN");
        } else {
            require(order.token.isContract(), "INVALID_TOKEN");
        }
    }

    function _createOrder(Order memory order) internal virtual {
        if (order.startTime == 0) order.startTime = uint32(block.timestamp);
        _checkOrderForCreation(order);

        bytes32 hash = _getOrderHash(order);
        Order storage _order = _orders[hash];
        require(_order.maker == address(0), "ORDER_EXISTS");
        {
            _order.maker = order.maker;
            _order.orderType = order.orderType;
            _order.strategy = order.strategy;
            _order.tokenType = order.tokenType;
            _order.token = order.token;
            _order.tokenId = order.tokenId;
            _order.amount = order.amount;
            _order.prices = order.prices;
            _order.currency = order.currency;
            _order.startTime = order.startTime;
            _order.endTime = order.endTime;
            _order.salt = order.salt;
        }

        TokenType _tokenType;
        address _token;
        uint256 _tokenId;
        uint256 _amount;
        if (order.orderType == OrderType.SellToken) {
            _tokenType = order.tokenType;
            _token = order.token;
            _tokenId = order.tokenId;
            _amount = order.amount;
        } else {
            _tokenType = _currencyTypeOf(order.currency);
            _token = order.currency;
            _tokenId = 0;
            _amount = _getHighestPrice(order.prices, order.amount);
        }

        _transferTokens(_tokenType, _token, _tokenId, _amount, msg.sender, address(this), false);

        emit CreateOrder(msg.sender, hash);
    }

    function _cancelOrder(bytes32 orderHash) internal virtual {
        require(!isCancelled[orderHash], "ALREADY_CANCELLED");
        Order storage _order = _orders[orderHash];
        uint256 amount = _order.amount;
        require(amount != 0, "AMOUNT_0");

        TokenType _tokenType;
        address _token;
        uint256 _tokenId;
        if (_order.orderType == OrderType.SellToken) {
            _tokenType = _order.tokenType;
            _token = _order.token;
            _tokenId = _order.tokenId;
        } else {
            address currency = _order.currency;
            _tokenType = _currencyTypeOf(currency);
            _token = currency;
            _tokenId = 0;
            amount = _getHighestPrice(_order.prices, amount);
            //due to this line, BuyToken order with Dutch Auction strategy should be filled perfectly in terms of amount
        }

        _transferTokens(_tokenType, _token, _tokenId, amount, address(this), _order.maker, false);
        isCancelled[orderHash] = true;
        emit CancelOrder(orderHash, msg.sender);
    }

    function _getFeeAndRoyalty(
        TokenType tokenType,
        address token,
        uint256 totalPrice
    )
        internal
        view
        returns (
            uint256 fee,
            address _feeReceiver,
            uint256 royalty,
            address royaltyReceiver
        )
    {
        fee = (totalPrice * protocolFee[tokenType]) / 10000;
        _feeReceiver = feeReceiver;

        if (tokenType >= TokenType.ERC1155) {
            IRoyaltyDB.RoyaltyInfo memory rInfo = royaltyDB.royaltyInfoOf(token);
            royalty = (totalPrice * rInfo.royalty) / 10000;
            royaltyReceiver = rInfo.recipient;
        }
    }

    function _transferFeeRoyaltyCurrencyAndTokens(
        OrderType orderType,
        TokenType tokenType,
        address token,
        uint256 tokenId,
        uint256 tokenAmount,
        address currency,
        uint256 totalPrice,
        address orderTaker,
        bool isCurrencyReserved,
        address orderMaker
    ) internal {
        (uint256 fee, address _feeReceiver, uint256 royalty, address royaltyReceiver) = _getFeeAndRoyalty(
            tokenType,
            token,
            totalPrice
        );

        address currencyFrom = isCurrencyReserved ? address(this) : msg.sender;

        if (orderType == OrderType.SellToken) {
            if (fee > 0) _transferCurrency(currency, currencyFrom, _feeReceiver, fee);
            if (royalty > 0) _transferCurrency(currency, currencyFrom, royaltyReceiver, royalty);

            _transferCurrency(currency, currencyFrom, orderMaker, totalPrice - fee - royalty);

            _transferTokens(tokenType, token, tokenId, tokenAmount, address(this), orderTaker, false);
        } else {
            if (fee > 0) _transferCurrency(currency, address(this), _feeReceiver, fee);
            if (royalty > 0) _transferCurrency(currency, address(this), royaltyReceiver, royalty);

            _transferTokens(tokenType, token, tokenId, tokenAmount, currencyFrom, orderMaker, false);

            _transferCurrency(currency, address(this), orderTaker, totalPrice - fee - royalty);
        }
    }

    function _transferCurrency(
        address currency,
        address from,
        address to,
        uint256 amount
    ) internal {
        _transferTokens(_currencyTypeOf(currency), currency, 0, amount, from, to, false);
    }

    function _refundExcessCurrency(
        uint256 refundPrice,
        address currency,
        address orderMaker
    ) internal {
        if (refundPrice > 0) {
            _transferTokens(_currencyTypeOf(currency), currency, 0, refundPrice, address(this), orderMaker, false);
        }
    }

    //ETH transfer 의 경우 msg.value 의 check 는 따로 필요함.
    function _transferTokens(
        TokenType tokenType,
        address token,
        uint256 tokenId,
        uint256 amount,
        address from,
        address to,
        bool refundExcessETH
    ) internal {
        require(amount > 0, "TRANSFER_AMOUNT_0");
        if (tokenType == TokenType.ETH) {
            require(token == address(0), "INVALID_ETH");
            require(tokenId == 0, "INVALID_ID_ETH");

            if (from == msg.sender) {
                if (to != address(this)) _safeETHTransfer(to, amount);

                if (refundExcessETH) {
                    uint256 diff = msg.value - amount;
                    if (diff > 0) _safeETHTransfer(msg.sender, diff);
                }
            } else {
                require(from == address(this), "INVALID_ETH_TRANSFER");
                _safeETHTransfer(to, amount);
            }
        } else if (tokenType == TokenType.ERC20) {
            require(tokenId == 0, "INVALID_ID_ERC20");

            if (from == address(this)) {
                IERC20(token).safeTransfer(to, amount);
            } else {
                IERC20(token).safeTransferFrom(from, to, amount);
            }
        } else if (tokenType == TokenType.ERC1155) {
            require(token.isContract(), "NOT_CONTRACT");
            IERC1155(token).safeTransferFrom(from, to, tokenId, amount, "");
        } else {
            // TokenType.ERC721
            require(amount == 1, "INVALID_AMOUNT_ERC721");
            require(token.isContract(), "NOT_CONTRACT");
            IERC721(token).transferFrom(from, to, tokenId);
        }
    }

    function _safeETHTransfer(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            WETH.deposit{value: amount}();
            IERC20(WETH).safeTransfer(to, amount);
        }
    }
}
