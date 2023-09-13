// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "forge-std/console.sol";

contract SimpleDEX is Ownable, ReentrancyGuard {
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
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(bytes32 => bool) public usedHashes;

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
        if (block.timestamp > expired) revert OrderExpired();
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

    // Errors
    error TokenNotSupported(address token);
    error InsufficientBalance();
    error OrderExpired();
    error TokenPairMismatch();
    error TradeDirectionsMustBeOpposite();
    error InvalidSignature(address signer);
    error NonceAlreadyUsed(address sender, uint256 nonce);
    error HashAlreadyUsed();

    // Public and External Functions
    function deposit(address token, uint256 amount) external {
        if (!supportedTokens[token]) revert TokenNotSupported(token);

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        userBalances[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (userBalances[msg.sender][token] < amount)
            revert InsufficientBalance();

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
        if (
            makerOrder.baseToken != takerOrder.baseToken &&
            makerOrder.quoteToken != takerOrder.quoteToken
        ) revert TokenPairMismatch();

        if (makerOrder.direction == takerOrder.direction)
            revert TradeDirectionsMustBeOpposite();

        if (usedNonces[makerOrder.sender][makerOrder.nonce])
            revert NonceAlreadyUsed(makerOrder.sender, makerOrder.nonce);

        if (usedNonces[takerOrder.sender][takerOrder.nonce])
            revert NonceAlreadyUsed(takerOrder.sender, takerOrder.nonce);

        if (!verifySignature(makerOrder, makerOrderSignature))
            revert InvalidSignature(makerOrder.sender);

        if (!verifySignature(takerOrder, takerOrderSignature))
            revert InvalidSignature(takerOrder.sender);

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

        // Mark nonces as used
        usedNonces[makerOrder.sender][makerOrder.nonce] = true;
        usedNonces[takerOrder.sender][takerOrder.nonce] = true;
    }

    // Internal Functions
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // Signature utils
    function verifySignature(
        Order calldata order,
        bytes calldata signature
    ) public returns (bool) {
        bytes32 messageHash = getOrderHash(order);

        if (usedHashes[messageHash]) revert HashAlreadyUsed();
        usedHashes[messageHash] = true;

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
