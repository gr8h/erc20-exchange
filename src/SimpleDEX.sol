// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract SimpleDEX is Ownable {
    // State variables
    mapping(address => bool) public supportedTokens;
    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => mapping(uint256 => Order)) public orders;

    // Constants
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 private constant ORDER_TYPEHASH =
        keccak256(
            "Order(uint256 nonce,address sender,TradeDirection direction,uint256 price,uint256 amount,uint256 expired,address baseToken,address quoteToken)"
        );

    // General Functions
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    function domainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_SEPARATOR_TYPEHASH,
                    keccak256(bytes("SimpleERC20Exchange")),
                    keccak256(bytes("1")),
                    getChainId(),
                    address(this)
                )
            );
    }

    // Function to encode order data
    function encodeOrderData(
        Order memory order
    ) internal view returns (bytes memory) {
        bytes32 dataHash = keccak256(
            abi.encode(
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

    function getOrderHash(Order memory order) public view returns (bytes32) {
        bytes memory encodedData = encodeOrderData(order);
        return keccak256(encodedData);
    }

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

    function isValidSignature(
        Order memory order,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 messageHash = getOrderHash(order);

        (uint8 v, bytes32 r, bytes32 s) = signatureSplit(signature, 0);

        // If v > 30 then default va (27,28) has been adjusted for eth_sign flow
        // To support eth_sign and similar we adjust v and hash the messageHash with the Ethereum message prefix before applying ecrecover
        require(v == 27 || v == 28, "Invalid signature version");

        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    messageHash
                )
            ),
            v - 4,
            r,
            s
        );

        return (recoveredAddress == order.sender);
    }

    // Events
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
        address indexed maker,
        address indexed taker,
        uint256 price
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
    }

    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
    }

    function matchOrders(
        Order memory makerOrder,
        bytes memory makerOrderSignature,
        Order memory takerOrder,
        bytes memory takerOrderSignature
    ) external onlyOwner orderNotExpired(makerOrder.expired) {
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
            isValidSignature(makerOrder, makerOrderSignature),
            "Invalid maker signature"
        );
        require(
            isValidSignature(takerOrder, takerOrderSignature),
            "Invalid taker signature"
        );

        // Additional checks and trade logic here
        _trade(makerOrder, takerOrder);

        // Emit OrderMatched event
        emit OrderMatched(
            makerOrder.sender,
            takerOrder.sender,
            makerOrder.price
        );
    }

    // Internal Functions
    function _trade(Order memory makerOrder, Order memory takerOrder) internal {
        // Trade logic
        uint256 tradeAmount = _min(makerOrder.amount, takerOrder.amount);

        // Update balances
        userBalances[makerOrder.sender][makerOrder.baseToken] -= tradeAmount;
        userBalances[takerOrder.sender][makerOrder.baseToken] += tradeAmount;

        userBalances[takerOrder.sender][makerOrder.quoteToken] -=
            tradeAmount *
            makerOrder.price;
        userBalances[makerOrder.sender][makerOrder.quoteToken] +=
            tradeAmount *
            makerOrder.price;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function signatureSplit(
        bytes memory signatures,
        uint256 pos
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // The signature format is a compact form of:
        //   {bytes32 r}{bytes32 s}{uint8 v}
        // Compact means, uint8 is not padded to 32 bytes.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let signaturePos := mul(0x41, pos)
            r := mload(add(signatures, add(signaturePos, 0x20)))
            s := mload(add(signatures, add(signaturePos, 0x40)))
            // Here we are loading the last 32 bytes, including 31 bytes
            // of 's'. There is no 'mload8' to do this.
            //
            // 'byte' is not working due to the Solidity parser, so lets
            // use the second best option, 'and'
            v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
        }
    }
}
