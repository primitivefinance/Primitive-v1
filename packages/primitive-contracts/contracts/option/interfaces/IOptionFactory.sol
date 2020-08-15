// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

interface IOptionFactory {
    function deploy(
        address underlyingToken,
        address strikeToken,
        uint base,
        uint quote,
        uint expiry
    ) external returns (address option);

    function initialize(address option, address redeem) external;

    function deployOptionTemplate() external;

    function optionTemplate() external returns (address);

    function getOption(
        address underlyingToken,
        address strikeToken,
        uint base,
        uint quote,
        uint expiry
    ) external view returns (address option);
}
