// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

contract SimpleDEX is Ownable {
    using ECDSA for bytes32;
    // Constants
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _DOMAIN_SEPARATOR_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // keccak256("Order(uint256 nonce,address sender,TradeDirection direction,uint256 price,uint256 amount,uint256 expired,address baseToken,address quoteToken)");
    bytes32 private constant _ORDER_TYPEHASH =
        0x08557a36a845e671a87115b910edd837f6ef0464af5717433f63dd919b2dd285;

    // State variables
    mapping(address => bool) public supportedTokens;
    mapping(address => mapping(address => uint256)) public userBalances;

    // Enum and Structs
    enum TradeDirection {
        SELL,
        BUY
    }

    struct Order {
        uint256 nonce;
        address sender;
        TradeDirection direction;
        uint256 price;
        uint256 amount;
        uint256 expired;
        address baseToken;
        address quoteToken;
    }

    // Modifiers
    modifier orderNotExpired(uint256 expired) {
        require(block.timestamp <= expired, "Order has expired");
        _;
    }

    // Events
    event AddSupportedToken(address indexed token);
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event OrderMatched(
        address indexed baseToken,
        address indexed quoteToken,
        address maker,
        address taker,
        uint256 indexed price,
        uint256 amount
    );

    // Public and External Functions
    function deposit(address token, uint256 amount) external {
        require(supportedTokens[token], "Token not supported");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        userBalances[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        require(supportedTokens[token], "Token not supported");
        require(
            userBalances[msg.sender][token] >= amount,
            "Insufficient balance"
        );
        userBalances[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, token, amount);
    }

    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
        emit AddSupportedToken(token);
    }

    function matchOrders(
        Order calldata makerOrder,
        bytes calldata makerOrderSignature,
        Order calldata takerOrder,
        bytes calldata takerOrderSignature
    )
        external
        onlyOwner
        orderNotExpired(makerOrder.expired)
        orderNotExpired(takerOrder.expired)
    {
        require(
            makerOrder.baseToken == takerOrder.baseToken &&
                makerOrder.quoteToken == takerOrder.quoteToken,
            "Token pair mismatch"
        );
        require(
            makerOrder.direction != takerOrder.direction,
            "Trade directions should be opposite"
        );

        require(
            verifySignature(makerOrder, makerOrderSignature),
            "Invalid maker signature"
        );
        require(
            verifySignature(takerOrder, takerOrderSignature),
            "Invalid taker signature"
        );

        uint8 quoteDecimals = IERC20Metadata(makerOrder.quoteToken).decimals();

        // Trade logic
        uint256 tradeAmount = _min(makerOrder.amount, takerOrder.amount);
        uint256 tradePrice = _min(makerOrder.price, takerOrder.price) *
            10 ** quoteDecimals;

        // Update balances
        userBalances[makerOrder.sender][makerOrder.baseToken] += tradeAmount;

        userBalances[takerOrder.sender][takerOrder.baseToken] -= tradeAmount;

        userBalances[makerOrder.sender][makerOrder.quoteToken] -= tradePrice;

        userBalances[takerOrder.sender][takerOrder.quoteToken] += tradePrice;

        emit OrderMatched(
            makerOrder.baseToken,
            makerOrder.quoteToken,
            makerOrder.sender,
            takerOrder.sender,
            tradePrice,
            tradeAmount
        );
    }

    // Internal Functions
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // Signature utils
    function verifySignature(
        Order calldata order,
        bytes calldata signature
    ) public view returns (bool) {
        bytes32 messageHash = getOrderHash(order);

        bytes32 signedMessageHash = messageHash.toEthSignedMessageHash();

        return signedMessageHash.recover(signature) == order.sender;
    }

    function getOrderHash(Order memory order) public view returns (bytes32) {
        bytes memory encodedData = _encodeOrderData(order);
        return keccak256(encodedData);
    }

    function domainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _DOMAIN_SEPARATOR_TYPEHASH,
                    keccak256(bytes("SimpleERC20Exchange")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _encodeOrderData(
        Order memory order
    ) internal view returns (bytes memory) {
        bytes32 dataHash = keccak256(
            abi.encode(
                _ORDER_TYPEHASH,
                order.nonce,
                order.sender,
                uint(order.direction),
                order.price,
                order.amount,
                order.expired,
                order.baseToken,
                order.quoteToken
            )
        );

        return
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                domainSeparator(),
                dataHash
            );
    }
}
