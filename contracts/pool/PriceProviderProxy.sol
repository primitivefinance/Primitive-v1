pragma solidity ^0.6.2;

/**
 * @title   Oracle for Calculating The Prices of Prime Options
 * @author  Primitive
 */

import "../interfaces/IAggregator.sol";
import "../interfaces/IPrimeOracle.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract PrimeOracle is IPrimeOracle {
    using SafeMath for uint256;

    address public oracle;
    address public weth;

    uint256 public constant MANTISSA = 10**36;
    uint256 public constant ONE_ETHER = 1 ether;
    uint256 public constant MIN_PREMIUM = 10**3;
    uint256 public constant SECONDS_IN_DAY = 86400;

    constructor(address _oracle, address _weth) public {
        oracle = _oracle;
        weth = _weth;
    }

    /**
     * @dev Calculates the intrinsic + extrinsic value of the Prime option.
     * @notice Strike / Market * (Volatility * 1000) * sqrt(T in seconds remaining) / Seconds in a Day.
     * @param tokenU The address of the underlying asset.
     * @param tokenS The address of the strike asset.
     * @param volatility The arbritary volatility as a percentage scaled by 1000.
     * @param base The quantity of the underlying asset. Also the price of tokenU denomined in tokenU.
     * @param price The quantity of the strike asset. Also the price of tokenU denominated in tokenS.
     * @param expiry The expirate date (strike date) of the Prime option as a UNIX timestamp.
     * @return premium The sum of the 'time value' and 'intrinsic' value of the Prime option.
     * Returns a premium that is denominated in tokenU.
     */
    function calculatePremium(
        address tokenU,
        address tokenS,
        uint256 volatility,
        uint256 base,
        uint256 price,
        uint256 expiry
    ) public override view returns (uint256 premium) {
        // Calculate the parts.
        uint256 intrinsic = calculateIntrinsic(tokenU, tokenS, base, price);
        uint256 extrinsic = calculateExtrinsic(
            tokenU,
            tokenS,
            volatility,
            base,
            price,
            expiry
        );

        // Sum the parts.
        premium = (extrinsic.add(intrinsic));

        // If the premium is 0, return a minimum value.
        premium = premium > MIN_PREMIUM ? premium : MIN_PREMIUM;
    }

    /**
     * @dev Gets the market price Ether.
     */
    function marketPrice() public override view returns (uint256 market) {
        market = uint256(IAggregator(oracle).latestAnswer());
    }

    /**
     * @dev Calculates the intrinsic value of a Prime option using compound's price oracle.
     * @param tokenU The address of the underlying asset.
     * @param tokenS The address of the strike asset.
     * @param base The quantity of the underlying asset. Also the price of tokenU denomined in tokenU.
     * @param price The quantity of the strike asset. Also the price of tokenU denominated in tokenS.
     * @return intrinsic The difference between the price of tokenU denominated in S between the
     * strike price (price) and market price (market).
     */
    function calculateIntrinsic(
        address tokenU,
        address tokenS,
        uint256 base,
        uint256 price
    ) public override view returns (uint256 intrinsic) {
        // Currently only supports WETH options with an assumed stablecoin strike.
        require(tokenU == weth || tokenS == weth, "ERR_ONLY_WETH_SUPPORT");
        // Get the oracle market price of ether.
        // If the underlying is WETH, the option is a call. Intrinsic = (S - K).
        // Else if the strike is WETH, the option is a put. Intrinsic = (K - S).
        uint256 market = marketPrice();
        if (tokenU == weth) {
            intrinsic = market > price ? market.sub(price) : uint256(0);
        } else intrinsic = base > market ? base.sub(market) : uint256(0);
    }

    /**
     * @dev Calculates the extrinsic value of the Prime option using Primitive's pricing model.
     * @notice Strike / Market * (Volatility(%) * 1000) * sqrt(T in seconds left) / Seconds in a Day.
     * @param tokenU The address of the underlying asset.
     * @param tokenS The address of the strike asset.
     * @param volatility The arbritary volatility as a percentage scaled by 1000.
     * @param base The quantity of the underlying asset. Also the price of tokenU denomined in tokenU.
     * @param price The quantity of the strike asset. Also the price of tokenU denominated in tokenS.
     * @param expiry The expirate date (strike date) of the Prime option as a UNIX timestamp.
     * @return extrinsic The 'time value' of the Prime option based on Primitive's pricing model.
     */
    function calculateExtrinsic(
        address tokenU,
        address tokenS,
        uint256 volatility,
        uint256 base,
        uint256 price,
        uint256 expiry
    ) public override view returns (uint256 extrinsic) {
        // Get the oracle market price of ether.
        uint256 market = marketPrice();
        // Time left in seconds.
        uint256 timeRemainder = (expiry.sub(block.timestamp));
        // Strike price is the price of tokenU denominated in tokenS.
        uint256 strike = tokenU == weth
            ? price.mul(ONE_ETHER).div(base)
            : base.mul(ONE_ETHER).div(price);
        // Strike / Market scaled to 1e18. Denominated in ethers.
        uint256 moneyness = market.mul(ONE_ETHER).div(strike);
        // Extrinsic value denominted in tokenU.
        (extrinsic) = _extrinsic(moneyness, volatility, timeRemainder);
    }

    function _extrinsic(
        uint256 moneyness,
        uint256 volatility,
        uint256 timeRemainder
    ) public pure returns (uint256 extrinsic) {
        extrinsic = moneyness
            .mul(ONE_ETHER)
            .mul(volatility)
            .mul(sqrt(timeRemainder))
            .div(ONE_ETHER)
            .div(SECONDS_IN_DAY);
    }

    /**
     * @dev Utility function to calculate the square root of an integer. Used in calculating premium.
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            uint256 x = (y + 1) / 2;
            z = y;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
