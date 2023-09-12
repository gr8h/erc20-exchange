// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract SigUtils {
    /**
     * @dev Calculates the message hash for a withdrawal request.
     * @param _beneficiary The beneficiary address of the withdrawal.
     * @param _amount The amount of tokens to withdraw.
     * @param _nonce A nonce used to ensure that each withdrawal request is unique.
     * @return The message hash of the withdrawal request.
     */
    function getMessageHash(
        address payable _beneficiary,
        uint256 _amount,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_beneficiary, _amount, _nonce));
    }

    /**
     * @dev Calculates the Ethereum signed message hash for a given message hash.
     * @param _messageHash The hash of the message being signed.
     * @return The Ethereum signed message hash.
     */
    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) public pure returns (bytes32) {
        // Signature is produced by signing a keccak256 hash with the following format:
        // "\x19Ethereum Signed Message\n" + len(msg) + msg
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    /**
     * @dev Converts a v, r, and s value into a single byte array.
     * @param v The `v` value of the signature.
     * @param r The `r` value of the signature.
     * @param s The `s` value of the signature.
     * @return The v, r, and s values as a single byte array.
     */
    function fromVRS(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (bytes memory) {
        // v ++ (length(r) + 0x80 ) ++ r ++ (length(s) + 0x80) ++ s
        // v ++ r ++ s
        return abi.encodePacked(r, s, v);
    }
}
