// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

/**
 * @title Factory for deploying option series.
 * @author Primitive
 */

import { Option, SafeMath } from "../../primitives/Option.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OptionTemplateLib } from "../../libraries/OptionTemplateLib.sol";
import { NullCloneConstructor } from "../NullCloneConstructor.sol";
import { CloneLib } from "../../libraries/CloneLib.sol";
import { IOptionFactory } from "../../interfaces/IOptionFactory.sol";

contract OptionFactory is IOptionFactory, Ownable, NullCloneConstructor {
    using SafeMath for uint;

    address public override optionTemplate;

    constructor(address registry) public {
        transferOwnership(registry);
    }

    function deployOptionTemplate() public override {
        optionTemplate = OptionTemplateLib.deployTemplate();
    }

    function deploy(
        address underlyingToken,
        address strikeToken,
        uint base,
        uint quote,
        uint expiry
    ) external override onlyOwner returns (address option) {
        require(optionTemplate != address(0x0), "ERR_NO_DEPLOYED_TEMPLATE");
        bytes32 salt = keccak256(
            abi.encodePacked(OptionTemplateLib.OPTION_SALT(), underlyingToken, strikeToken, base, quote, expiry)
        );
        option = CloneLib.create2Clone(optionTemplate, uint(salt));
        Option(option).initialize(underlyingToken, strikeToken, base, quote, expiry);
    }

    function initialize(address option, address redeem) external override onlyOwner {
        Option(option).initRedeemToken(redeem);
    }

    function getOption(
        address underlyingToken,
        address strikeToken,
        uint base,
        uint quote,
        uint expiry
    ) external override view returns (address option) {
        bytes32 salt = keccak256(
            abi.encodePacked(OptionTemplateLib.OPTION_SALT(), underlyingToken, strikeToken, base, quote, expiry)
        );
        option = CloneLib.deriveInstanceAddress(optionTemplate, salt);
    }
}
