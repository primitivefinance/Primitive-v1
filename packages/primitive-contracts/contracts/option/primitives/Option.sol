// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

/**
 * @title   Vanilla Option Token
 * @author  Primitive
 */

import { Primitives } from "../../Primitives.sol";
import { IOption } from "../interfaces/IOption.sol";
import { IRedeem } from "../interfaces/IRedeem.sol";
import { IFlash } from "../interfaces/IFlash.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Option is IOption, ERC20, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    Primitives.Option public optionParameters;

    // solhint-disable-next-line const-name-snakecase
    uint256 public override underlyingCache;
    uint256 public override strikeCache;
    address public override redeemToken;
    address public override factory;

    event Mint(address indexed from, uint256 outOptions, uint256 outRedeems);
    event Exercise(
        address indexed from,
        uint256 outUnderlyings,
        uint256 inStrikes
    );
    event Redeem(address indexed from, uint256 inRedeems);
    event Close(address indexed from, uint256 outUnderlyings);
    event UpdatedCacheBalances(uint256 underlyingCache, uint256 strikeCache);
    event InitializedRedeem(
        address indexed caller,
        address indexed redeemToken
    );
    event Skimming(
        address indexed caller,
        uint256 quantityUnderlyings,
        uint256 quantityStrikes,
        uint256 quantityOptions,
        uint256 quantityRedeems
    );

    // solhint-disable-next-line no-empty-blocks
    constructor() public ERC20("Primitive V1 Vanilla Option", "OPTION") {}

    function initialize(
        address underlyingToken,
        address strikeToken,
        uint256 base,
        uint256 quote,
        uint256 expiry
    ) public {
        require(factory == address(0x0), "ERR_IS_INITIALIZED");
        require(underlyingToken != strikeToken, "ERR_SAME_ASSETS");
        require(base > 0, "ERR_BASE_ZERO");
        require(quote > 0, "ERR_QUOTE_ZERO");
        require(expiry >= block.timestamp, "ERR_EXPIRY");
        factory = msg.sender;
        optionParameters = Primitives.Option(
            underlyingToken,
            strikeToken,
            base,
            quote,
            expiry
        );
    }

    modifier notExpired {
        // solhint-disable-next-line not-rely-on-time
        require(isNotExpired(), "ERR_EXPIRED");
        _;
    }

    function initRedeemToken(address _redeemToken) external override {
        require(msg.sender == factory, "ERR_NOT_OWNER");
        require(redeemToken == address(0x0), "ERR_REDEEM_INITIALIZED");
        redeemToken = _redeemToken;
        emit InitializedRedeem(msg.sender, _redeemToken);
    }

    /**
     * @dev Updates the cached balances to the actual current balances.
     */
    function updateCacheBalances() external override nonReentrant {
        _updateCacheBalances(
            IERC20(optionParameters.underlyingToken).balanceOf(address(this)),
            IERC20(optionParameters.strikeToken).balanceOf(address(this))
        );
    }

    /**
     * @dev Difference between balances and caches is sent out so balances == caches.
     * Fixes underlyingToken, strikeToken, redeemToken, and optionToken balances.
     */
    function withdrawUnusedFunds() external override nonReentrant {
        (
            address _underlyingToken,
            address _strikeToken,
            address _redeemToken
        ) = getAssetAddresses();
        uint256 quantityUnderlyings = IERC20(_underlyingToken)
            .balanceOf(address(this))
            .sub(underlyingCache);
        uint256 quantityStrikes = IERC20(_strikeToken)
            .balanceOf(address(this))
            .sub(strikeCache);
        uint256 quantityRedeems = IERC20(_redeemToken).balanceOf(address(this));
        uint256 quantityOptions = IERC20(address(this)).balanceOf(
            address(this)
        );
        IERC20(_underlyingToken).safeTransfer(msg.sender, quantityUnderlyings);
        IERC20(_strikeToken).safeTransfer(msg.sender, quantityStrikes);
        IERC20(_redeemToken).safeTransfer(msg.sender, quantityRedeems);
        IERC20(address(this)).safeTransfer(msg.sender, quantityOptions);
        emit Skimming(
            msg.sender,
            quantityUnderlyings,
            quantityStrikes,
            quantityRedeems,
            quantityOptions
        );
    }

    /**
     * @dev Sets the cache balances to new values.
     */
    function _updateCacheBalances(
        uint256 underlyingBalance,
        uint256 strikeBalance
    ) private {
        underlyingCache = underlyingBalance;
        strikeCache = strikeBalance;
        emit UpdatedCacheBalances(underlyingBalance, strikeBalance);
    }

    /* === STATE MUTABLE === */

    /**
     * @dev Mints optionTokens at a 1:1 ratio to underlyingToken deposits. Also mints Redeem tokens at a base:quote ratio.
     * @notice inUnderlyings = outOptions. inUnderlying / strike ratio = outRedeems.
     * @param receiver The newly minted tokens are sent to the receiver address.
     */
    function mintOptions(address receiver)
        external
        override
        nonReentrant
        notExpired
        returns (uint256 inUnderlyings, uint256 outRedeems)
    {
        // Save on gas because this variable is used twice.
        uint256 underlyingBalance = IERC20(optionParameters.underlyingToken)
            .balanceOf(address(this));

        // Mint optionTokens equal to the difference between current and cached balance of underlyingTokens.
        inUnderlyings = underlyingBalance.sub(underlyingCache);

        // Calculate the quantity of redeemTokens to mint.
        outRedeems = inUnderlyings.mul(optionParameters.quote).div(
            optionParameters.base
        );
        require(outRedeems > 0, "ERR_ZERO");

        // Mint the optionTokens and redeemTokens.
        IRedeem(redeemToken).mint(receiver, outRedeems);
        _mint(receiver, inUnderlyings);

        // Update the underlyingCache.
        _updateCacheBalances(underlyingBalance, strikeCache);
        emit Mint(msg.sender, inUnderlyings, outRedeems);
    }

    /**
     * @dev Sends out underlyingTokens then checks to make sure they are returned or paid for.
     * @notice If the underlyingTokens are returned, only the fee has to be paid.
     * @param receiver The outUnderlyings are sent to the receiver address.
     * @param outUnderlyings Quantity of underlyingTokens to safeTransfer to receiver optimistically.
     * @param data Passing in any abritrary data will trigger the flash exercise callback function.
     */
    function exerciseOptions(
        address receiver,
        uint256 outUnderlyings,
        bytes calldata data
    )
        external
        override
        nonReentrant
        notExpired
        returns (uint256 inStrikes, uint256 inOptions)
    {
        // Store the cached balances and token addresses in memory.
        address underlyingToken = optionParameters.underlyingToken;
        (uint256 _underlyingCache, uint256 _strikeCache) = getCacheBalances();

        // Require outUnderlyings > 0 and balane of underlings >= outUnderlyings.
        require(outUnderlyings > 0, "ERR_ZERO");
        require(
            IERC20(underlyingToken).balanceOf(address(this)) >= outUnderlyings,
            "ERR_BAL_UNDERLYING"
        );

        // Optimistically safeTransfer out underlyingTokens.
        IERC20(underlyingToken).safeTransfer(receiver, outUnderlyings);
        if (data.length > 0)
            IFlash(receiver).primitiveFlash(msg.sender, outUnderlyings, data);

        // Store in memory for gas savings.
        uint256 strikeBalance = IERC20(optionParameters.strikeToken).balanceOf(
            address(this)
        );
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(
            address(this)
        );

        // Calculate the Differences.
        inStrikes = strikeBalance.sub(_strikeCache);
        uint256 inUnderlyings = underlyingBalance.sub(
            _underlyingCache.sub(outUnderlyings)
        ); // will be > 0 if underlyingTokens are returned.

        // Either underlyingTokens or strikeTokens must be sent into the contract.
        require(inStrikes > 0 || inUnderlyings > 0, "ERR_ZERO");

        // Calculate the remaining amount of underlyingToken that needs to be paid for.
        uint256 remainder = inUnderlyings > outUnderlyings
            ? 0
            : outUnderlyings.sub(inUnderlyings);

        // Calculate the expected payment of strikeTokens.
        uint256 payment = remainder.mul(optionParameters.quote).div(
            optionParameters.base
        );

        // Assumes the cached optionToken balance is 0, which is what it should be.
        inOptions = balanceOf(address(this));

        // Enforce the invariants.
        require(inStrikes >= payment, "ERR_STRIKES_INPUT");
        require(inOptions >= remainder, "ERR_OPTIONS_INPUT");

        // Burn the optionTokens at a 1:1 ratio to outUnderlyings.
        _burn(address(this), inOptions);

        // Update the cached balances.
        _updateCacheBalances(underlyingBalance, strikeBalance);
        emit Exercise(msg.sender, outUnderlyings, inStrikes);
    }

    /**
     * @dev Burns redeemTokens to withdraw strikeTokens at a ratio of 1:1.
     * @notice inRedeems = outStrikes. Only callable when strikeTokens are in the contract.
     * @param receiver The inRedeems quantity of strikeTokens are sent to the receiver address.
     */
    function redeemStrikeTokens(address receiver)
        external
        override
        nonReentrant
        returns (uint256 inRedeems)
    {
        address strikeToken = optionParameters.strikeToken;
        address _redeemToken = redeemToken;
        uint256 strikeBalance = IERC20(strikeToken).balanceOf(address(this));
        inRedeems = IERC20(_redeemToken).balanceOf(address(this));

        // Difference between redeemTokens balance and cache.
        require(inRedeems > 0, "ERR_ZERO");
        require(strikeBalance >= inRedeems, "ERR_BAL_STRIKE");

        // Burn redeemTokens in the contract. Send strikeTokens to receiver.
        IRedeem(_redeemToken).burn(address(this), inRedeems);
        IERC20(strikeToken).safeTransfer(receiver, inRedeems);

        // Current balances.
        strikeBalance = IERC20(strikeToken).balanceOf(address(this));

        // Update the cached balances.
        _updateCacheBalances(underlyingCache, strikeBalance);
        emit Redeem(msg.sender, inRedeems);
    }

    /**
     * @dev If the option has expired, burn redeem tokens with withdraw underlying tokens.
     * If the option is not expired, burn option and redeem tokens to withdraw underlying tokens.
     * @notice inRedeems / strike ratio = outUnderlyings && inOptions >= outUnderlyings.
     * @param receiver The outUnderlyings are sent to the receiver address.
     */
    function closeOptions(address receiver)
        external
        override
        nonReentrant
        returns (
            uint256 inRedeems,
            uint256 inOptions,
            uint256 outUnderlyings
        )
    {
        // Stores addresses and balances locally for gas savings.
        address underlyingToken = optionParameters.underlyingToken;
        address _redeemToken = redeemToken;
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(
            address(this)
        );
        uint256 optionBalance = balanceOf(address(this));
        inRedeems = IERC20(_redeemToken).balanceOf(address(this));

        // The quantity of underlyingToken to send out it still determined by the quantity of inRedeems.
        // inRedeems is in units of strikeTokens, which is converted to underlyingTokens
        // by multiplying inRedeems by the strike ratio, which is base / quote.
        // This outUnderlyings quantity is checked against inOptions.
        // inOptions must be greater than or equal to outUnderlyings (1 option burned per 1 underlying purchased).
        // optionBalance must be greater than or equal to outUnderlyings.
        // Neither inRedeems or inOptions can be zero.
        outUnderlyings = inRedeems.mul(optionParameters.base).div(
            optionParameters.quote
        );

        // Assumes the cached balance is 0 so inOptions = balance of optionToken.
        // If optionToken is expired, optionToken does not need to be sent in. Only redeemToken.
        // solhint-disable-next-line not-rely-on-time
        inOptions = isNotExpired() ? optionBalance : outUnderlyings;
        require(inRedeems > 0 && inOptions > 0, "ERR_ZERO");
        require(
            inOptions >= outUnderlyings && underlyingBalance >= outUnderlyings,
            "ERR_BAL_UNDERLYING"
        );

        // Burn optionTokens. optionTokens are only sent into contract when not expired.
        // solhint-disable-next-line not-rely-on-time
        if (isNotExpired()) {
            _burn(address(this), inOptions);
        }

        // Send underlyingTokens to user.
        // Burn redeemTokens held in the contract.
        // User does not receive extra underlyingTokens if there was extra optionTokens in the contract.
        // User receives outUnderlyings proportional to inRedeems.
        IRedeem(_redeemToken).burn(address(this), inRedeems);
        IERC20(underlyingToken).safeTransfer(receiver, outUnderlyings);

        // Current balances of underlyingToken and redeemToken.
        underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));

        // Update the cached balances.
        _updateCacheBalances(underlyingBalance, strikeCache);
        emit Close(msg.sender, outUnderlyings);
    }

    /* === VIEW === */
    function getCacheBalances()
        public
        override
        view
        returns (uint256 _underlyingCache, uint256 _strikeCache)
    {
        _underlyingCache = underlyingCache;
        _strikeCache = strikeCache;
    }

    function getAssetAddresses()
        public
        override
        view
        returns (
            address _underlyingToken,
            address _strikeToken,
            address _redeemToken
        )
    {
        _underlyingToken = optionParameters.underlyingToken;
        _strikeToken = optionParameters.strikeToken;
        _redeemToken = redeemToken;
    }

    function getStrikeTokenAddress() public override view returns (address) {
        return optionParameters.strikeToken;
    }

    function getUnderlyingTokenAddress()
        public
        override
        view
        returns (address)
    {
        return optionParameters.underlyingToken;
    }

    function getBaseValue() public override view returns (uint256) {
        return optionParameters.base;
    }

    function getQuoteValue() public override view returns (uint256) {
        return optionParameters.quote;
    }

    function getExpiryTime() public override view returns (uint256) {
        return optionParameters.expiry;
    }

    function getParameters()
        public
        override
        view
        returns (
            address _underlyingToken,
            address _strikeToken,
            address _redeemToken,
            uint256 _base,
            uint256 _quote,
            uint256 _expiry
        )
    {
        Primitives.Option memory _optionParameters = optionParameters;
        _underlyingToken = _optionParameters.underlyingToken;
        _strikeToken = _optionParameters.strikeToken;
        _redeemToken = redeemToken;
        _base = _optionParameters.base;
        _quote = _optionParameters.quote;
        _expiry = _optionParameters.expiry;
    }

    function isNotExpired() internal view returns (bool) {
        return optionParameters.expiry >= block.timestamp;
    }
}
