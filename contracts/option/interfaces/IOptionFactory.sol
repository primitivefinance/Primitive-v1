// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

interface IOptionFactory {
    function deploy(
        address underlyingToken,
        address strikeToken,
        uint256 base,
        uint256 quote,
        uint256 expiry
    ) external returns (address option);

    function initialize(address option, address redeem) external;

    function deployOptionTemplate() external;

    function optionTemplate() external returns (address);
}
