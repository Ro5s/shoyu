// SPDX-License-Identifier: MIT

pragma solidity =0.8.3;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./BaseStrategy.sol";

contract EnglishAuction is BaseStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Cancel(address indexed lastBidder, uint256 lastBidPrice);
    event Bid(address indexed bidder, uint256 bidPrice);
    event Claim(address indexed taker, uint256 indexed price);

    address public lastBidder;
    uint256 public lastBidPrice;
    uint256 public startPrice;
    uint8 public priceGrowth; // out of 100

    function initialize(
        uint256 _tokenId,
        address _recipient,
        address _currency,
        uint256 _endBlock,
        uint256 _startPrice,
        uint8 _priceGrowth
    ) external initializer {
        __BaseStrategy_init(_tokenId, _recipient, _currency, _endBlock);

        startPrice = _startPrice;
        priceGrowth = _priceGrowth;
    }

    function currentPrice() public view override returns (uint256) {
        uint256 _lastBidPrice = lastBidPrice;
        return _lastBidPrice == 0 ? startPrice : _lastBidPrice;
    }

    function cancel() external override onlyOwner whenSaleOpen {
        _cancel();

        address _lastBidder = lastBidder;
        uint256 _lastBidPrice = lastBidPrice;

        lastBidder = address(0);
        lastBidPrice = 0;

        if (_lastBidPrice > 0) {
            _safeTransfer(_lastBidder, _lastBidPrice);
        }

        emit Cancel(_lastBidder, _lastBidPrice);
    }

    function bid(uint256 price) external payable nonReentrant whenSaleOpen {
        uint256 _endBlock = endBlock;
        require(block.number <= _endBlock, "SHOYU: EXPIRED");

        (uint256 _priceGrowth, address _lastBidder) = (priceGrowth, lastBidder); // gas optimization
        uint256 _lastBidPrice = lastBidPrice;
        if (_lastBidPrice != 0) {
            require(msg.value >= _lastBidPrice + ((_lastBidPrice * _priceGrowth) / 100), "SHOYU: PRICE_NOT_INCREASED");
        } else {
            require(msg.value >= startPrice && msg.value > 0, "low price bid");
        }

        if (block.number > _endBlock - 20) {
            endBlock = endBlock + 20; // 5 mins
        }

        _safeTransferFrom(price);
        if (_lastBidPrice > 0) {
            _safeTransfer(_lastBidder, _lastBidPrice);
        }

        lastBidder = msg.sender;
        lastBidPrice = price;

        emit Bid(msg.sender, price);
    }

    function claim() external nonReentrant whenSaleOpen {
        require(block.number > endBlock, "SHOYU: ONGOING_SALE");
        address _token = token;
        uint256 _tokenId = tokenId;
        address factory = INFT(_token).factory();

        uint256 _lastBidPrice = lastBidPrice;
        address feeTo = INFTFactory(factory).feeTo();
        uint256 feeAmount = (_lastBidPrice * INFTFactory(factory).fee()) / 1000;

        status = Status.CANCELLED;
        INFT(token).closeSale(_tokenId);

        _safeTransfer(feeTo, feeAmount);
        _safeTransfer(recipient, _lastBidPrice - feeAmount);

        address _owner = INFT(_token).ownerOf(_tokenId);
        address _lastBidder = lastBidder;
        INFT(_token).safeTransferFrom(_owner, _lastBidder, _tokenId);

        emit Claim(_lastBidder, _lastBidPrice);
    }

    function _safeTransfer(address to, uint256 amount) internal {
        address _currency = currency;
        if (_currency == ETH) {
            payable(to).transfer(amount);
        } else {
            IERC20(_currency).safeTransfer(to, amount);
        }
    }

    function _safeTransferFrom(uint256 amount) internal {
        address _currency = currency;
        if (_currency == ETH) {
            require(msg.value == amount, "SHOYU: INVALID_MSG_VALUE");
        } else {
            IERC20(_currency).safeTransferFrom(msg.sender, address(this), amount);
        }
    }
}
