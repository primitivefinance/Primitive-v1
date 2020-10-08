const bre = require("@nomiclabs/buidler");

// Artifacts
const TestERC20 = require("../../artifacts/TestERC20");
const BadERC20 = require("../../artifacts/BadERC20");
const OptionFactory = require("../../artifacts/OptionFactory");
const RedeemFactory = require("../../artifacts/RedeemFactory");
const Option = require("../../artifacts/Option");
const OptionTest = require("../../artifacts/OptionTest");
const Redeem = require("../../artifacts/Redeem");
const Registry = require("../../artifacts/Registry");
const Flash = require("../../artifacts/Flash");
const Weth = require("../../artifacts/WETH9");
const Trader = require("../../artifacts/Trader");
const WethConnector = require("../../artifacts/WethConnector");
const UniswapConnector = require("../../artifacts/UniswapConnector.json");
const OptionTemplateLib = require("../../artifacts/OptionTemplateLib");
const RedeemTemplateLib = require("../../artifacts/RedeemTemplateLib");

// Constants and Utility functions
const constants = require("./constants");
const { MILLION_ETHER } = constants.VALUES;
const { OPTION_TEMPLATE_LIB, REDEEM_TEMPLATE_LIB } = constants.LIBRARIES;
const { deployContract, link } = require("ethereum-waffle");
const { parseEther, formatEther } = bre.ethers.utils;
const ethers = bre.ethers;

// Uniswap related artifacts and addresses
const UniswapV2Router02 = require("@uniswap/v2-periphery/build/UniswapV2Router02.json");
const UniswapV2Factory = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const { RINKEBY_UNI_ROUTER02, RINKEBY_UNI_FACTORY } = constants.ADDRESSES;

const MAX_UINT = parseEther("10000000000000000000000000000000000000");

/**
 * @dev Gets signers from ethers.
 */
const newWallets = async () => {
    const wallets = await ethers.getSigners();
    return wallets;
};

/**
 * @dev Deploys a new ERC-20 token contract.
 * @param {*} signer An ethers js Signer object
 * @param {*} name The name for the ERC-20 token.
 * @param {*} symbol The symbol for the ERC-20 token.
 * @param {*} totalSupply The initial supply for the token.
 */
const newERC20 = async (signer, name, symbol, totalSupply) => {
    const ERC20 = await deployContract(
        signer,
        TestERC20,
        [name, symbol, totalSupply],
        {
            gasLimit: 6000000,
        }
    );
    return ERC20;
};

/**
 * @dev Deploys a non-standard ERC-20 token that does not return a boolean.
 * @param {*} signer An ethers js Signer object.
 * @param {*} name The name for the ERC-20 token.
 * @param {*} symbol The symbol for the ERC-20 token.
 */
const newBadERC20 = async (signer, name, symbol) => {
    const bad = await deployContract(signer, BadERC20, [name, symbol], {
        gasLimit: 6000000,
    });
    return bad;
};

/**
 * @dev Deploys a new WETH contract using the canonical-weth package.
 * @param {*} signer An ethers js Signer object.
 */
const newWeth = async (signer) => {
    const weth = await deployContract(signer, Weth, [], {
        gasLimit: 6000000,
    });
    return weth;
};

/**
 * @dev Deploys a test contract Flash.sol.
 * @param {*} signer
 * @param {*} optionToken The address of an Option contract
 */
const newFlash = async (signer, optionToken) => {
    const flash = await deployContract(signer, Flash, [optionToken], {
        gasLimit: 6000000,
    });
    return flash;
};

/**
 * @dev Deploys a Registry instance and initializes it with the correct factories.
 * @param signer A Signer object from ethers js.
 */
const newRegistry = async (signer) => {
    const registry = await deployContract(signer, Registry, [], {
        gasLimit: 6500000,
    });
    let oLib = await deployContract(signer, OptionTemplateLib, [], {
        gasLimit: 6000000,
    });
    let opFacContract = Object.assign(OptionFactory, {
        evm: { bytecode: { object: OptionFactory.bytecode } },
    });
    link(opFacContract, OPTION_TEMPLATE_LIB, oLib.address);

    let optionFactory = await deployContract(
        signer,
        opFacContract,
        [registry.address],
        {
            gasLimit: 6000000,
        }
    );
    let rLib = await deployContract(signer, RedeemTemplateLib, [], {
        gasLimit: 6000000,
    });

    let reFacContract = Object.assign(RedeemFactory, {
        evm: { bytecode: { object: RedeemFactory.bytecode } },
    });
    link(reFacContract, REDEEM_TEMPLATE_LIB, rLib.address);

    let redeemTokenFactory = await deployContract(
        signer,
        reFacContract,
        [registry.address],
        {
            gasLimit: 6000000,
        }
    );
    await optionFactory.deployOptionTemplate();
    await redeemTokenFactory.deployRedeemTemplate();
    await registry.setOptionFactory(optionFactory.address);
    await registry.setRedeemFactory(redeemTokenFactory.address);
    return registry;
};

/**
 * @dev Deploys new option and redeem factory instances and links the necessary libraries.
 * @param {*} signer
 * @param {*} registry The registry contract instance.
 */
const newOptionFactory = async (signer, registry) => {
    let oLib = await deployContract(signer, OptionTemplateLib, [], {
        gasLimit: 6000000,
    });
    let opFacContract = Object.assign(OptionFactory, {
        evm: { bytecode: { object: OptionFactory.bytecode } },
    });
    link(opFacContract, OPTION_TEMPLATE_LIB, oLib.address);

    let optionFactory = await deployContract(
        signer,
        opFacContract,
        [registry.address],
        {
            gasLimit: 6000000,
        }
    );
    let rLib = await deployContract(signer, RedeemTemplateLib, [], {
        gasLimit: 6000000,
    });

    let reFacContract = Object.assign(RedeemFactory, {
        evm: { bytecode: { object: RedeemFactory.bytecode } },
    });
    link(reFacContract, REDEEM_TEMPLATE_LIB, rLib.address);

    let redeemTokenFactory = await deployContract(
        signer,
        reFacContract,
        [registry.address],
        {
            gasLimit: 6000000,
        }
    );
    await optionFactory.deployOptionTemplate();
    await redeemTokenFactory.deployRedeemTemplate();
    await registry.setOptionFactory(optionFactory.address);
    await registry.setRedeemFactory(redeemTokenFactory.address);
    return optionFactory;
};

/**
 * @dev Deploys a TestOption contract instance and returns it.
 * @param {*} signer
 * @param {*} underlyingToken The address of the underlying token.
 * @param {*} strikeToken The address of the strike token.
 * @param {*} base The quantity of underlying tokens per unit of quote strike tokens.
 * @param {*} quote The quantity of strike tokens per unit of base underlying tokens.
 * @param {*} expiry The unix timestamp for when the option token expires.
 */
const newTestOption = async (
    signer,
    underlyingToken,
    strikeToken,
    base,
    quote,
    expiry
) => {
    const optionToken = await deployContract(signer, OptionTest, [], {
        gasLimit: 6000000,
    });
    await optionToken.initialize(
        underlyingToken,
        strikeToken,
        base,
        quote,
        expiry
    );
    return optionToken;
};

/**
 *
 * @param {*} signer
 * @param {*} factory The address of the redeem factory contract.
 * @param {*} optionToken The address of the option token linked to the redeem token.
 * @param {*} underlying The address of the underlying token for the option token.
 */
const newTestRedeem = async (signer, factory, optionToken) => {
    const redeemToken = await deployContract(signer, Redeem, [], {
        gasLimit: 6000000,
    });
    await redeemToken.initialize(factory, optionToken);
    return redeemToken;
};

/**
 * @dev Deploys a new Trader contract instance.
 * @param {*} signer
 * @param {*} weth The address of WETH for the respective network.
 */
const newTrader = async (signer, weth) => {
    const trader = await deployContract(signer, Trader, [weth], {
        gasLimit: 6000000,
    });
    return trader;
};

/**
 * @dev Deploys a new Trader contract instance.
 * @param {*} signer
 * @param {*} weth The address of WETH for the respective network.
 */
const newWethConnector = async (signer, weth) => {
    const trader = await deployContract(signer, WethConnector, [weth], {
        gasLimit: 6000000,
    });
    return trader;
};

/**
 * @dev Deploys a new Option contract instance through the Registry contract instance.
 * @param {*} signer
 * @param {*} registry The instance of the Registry contract.
 * @param {*} underlyingToken The address of the underlying token.
 * @param {*} strikeToken The address of the strike token.
 * @param {*} base The quantity of underlying tokens per unit of quote strike tokens.
 * @param {*} quote The quantity of strike tokens per unit of base underlying tokens.
 * @param {*} expiry The unix timestamp for when the option expires.
 */
const newOption = async (
    signer,
    registry,
    underlyingToken,
    strikeToken,
    base,
    quote,
    expiry
) => {
    await registry.verifyToken(underlyingToken);
    await registry.verifyToken(strikeToken);
    await registry.deployOption(
        underlyingToken,
        strikeToken,
        base,
        quote,
        expiry
    );
    let optionToken = new ethers.Contract(
        await registry.allOptionClones(
            ((await registry.getAllOptionClonesLength()) - 1).toString()
        ),
        Option.abi,
        signer
    );
    return optionToken;
};

/**
 * @dev Gets the Redeem token contract instance by getting the address through the option token.
 * @param {*} signer
 * @param {*} optionToken The instance of the option token contract.
 */
const newRedeem = async (signer, optionToken) => {
    let redeemTokenAddress = await optionToken.redeemToken();
    let redeemToken = new ethers.Contract(
        redeemTokenAddress,
        Redeem.abi,
        signer
    );
    return redeemToken;
};

/**
 * @dev Deploys new Option and Redeem contract instances and returns them.
 * @param {*} signer
 * @param {*} registry The instance contract of the Registry.
 * @param {*} underlyingToken The instance contract for the underlying token.
 * @param {*} strikeToken The instance contract for the strike token.
 * @param {*} base The quantity of underlying tokens per unit of quote stike tokens.
 * @param {*} quote The quantity of strike tokens per unit of base underlying tokens.
 * @param {*} expiry The unix timestamp for when the option expires.
 */
const newPrimitive = async (
    signer,
    registry,
    underlyingToken,
    strikeToken,
    base,
    quote,
    expiry
) => {
    let optionToken = await newOption(
        signer,
        registry,
        underlyingToken.address,
        strikeToken.address,
        base,
        quote,
        expiry
    );
    let redeemToken = await newRedeem(signer, optionToken);

    const Primitive = {
        underlyingToken: underlyingToken,
        strikeToken: strikeToken,
        optionToken: optionToken,
        redeemToken: redeemToken,
    };
    return Primitive;
};

/**
 * @dev A generalized function to update approval state for any ERC-20 token.
 * @param {*} token The contract instance of the token that should update its approval.
 * @param {*} signer The address which is approving.
 * @param {*} spender The address which should be approved.
 */
const approveToken = async (token, signer, spender) => {
    await token.approve(spender, MILLION_ETHER, { from: signer });
};

/**
 * @dev Gets the UniswapConnector instance.
 */
const newUniswapConnector = async (signer) => {
    const connector = await deployContract(signer, UniswapConnector, [], {
        gasLimit: 6000000,
    });
    return connector;
};

/**
 * @dev Deploys a new Uniswap factory and router instance for testing.
 * @param {*} signer
 * @param {*} feeToSetter The address which receives fees from the uniswap contracts.
 * @param {*} WETH The address of WETH for the respective chain ID.
 */
const newUniswap = async (signer, feeToSetter, WETH) => {
    const uniswapFactory = await deployContract(
        signer,
        UniswapV2Factory,
        [feeToSetter],
        {
            gasLimit: 6000000,
        }
    );
    const uniswapRouter = await deployContract(
        signer,
        UniswapV2Router02,
        [uniswapFactory.address, WETH.address],
        {
            gasLimit: 6000000,
        }
    );
    return { uniswapRouter, uniswapFactory };
};

/**
 * @dev Gets the contract instances for Uniswap's Router and Factory for Rinkeby.
 */
const newUniswapRinkeby = async (signer) => {
    const uniswapRouter = new ethers.Contract(
        RINKEBY_UNI_ROUTER02,
        UniswapV2Router02.abi,
        signer
    );
    const uniswapFactory = new ethers.Contract(
        RINKEBY_UNI_FACTORY,
        UniswapV2Factory.abi,
        signer
    );
    return { uniswapRouter, uniswapFactory };
};

const setupMultipleContracts = async (arrayOfContractNames) => {
    let contracts = [];
    for (let i = 0; i < arrayOfContractNames.length; i++) {
        let contractName = arrayOfContractNames[i];
        console.log(contractName);
        let factory = await ethers.getContractFactory(contractName);
        let contract = await factory.deploy({ gasLimit: 10000000 });
        await contract.deployed();
        contract.deployTransaction.wait();
        contracts.push(contract);
    }
    console.log("Set up all contracts!");
    return contracts;
};

const batchApproval = async (
    arrayOfContractsToApprove,
    arrayOfTokens,
    arrayOfOwners
) => {
    // for each contract
    for (let c = 0; c < arrayOfContractsToApprove.length; c++) {
        let contract = arrayOfContractsToApprove[c];
        // for each token
        for (let t = 0; t < arrayOfTokens.length; t++) {
            let token = arrayOfTokens[t];
            // for each owner
            for (let u = 0; u < arrayOfOwners.length; u++) {
                let user = arrayOfOwners[u];

                await token.connect(user).approve(contract.address, MAX_UINT);
            }
        }
    }
};

const newSyntheticOption = async (signer, optionAddress, clearingHouse) => {
    await clearingHouse.deploySyntheticOption(optionAddress);
    let syntheticOptionAddress = await clearingHouse.syntheticOptions(
        optionAddress
    );
    let syntheticOption = new ethers.Contract(
        syntheticOptionAddress,
        Option.abi,
        signer
    );
    return syntheticOption;
};

const formatConfigForBalanceReporter = async (
    contractNamesArray,
    contractsArray,
    tokensArray
) => {
    const info = {
        balances: [
            {
                contract: "Test contract",
                tokenName: "Test Token",
                tokenBalance: "Test Balance",
            },
        ],
    };

    // for each contract, get each token balance
    for (let i = 0; i < contractsArray.length; i++) {
        let name = contractNamesArray[i];
        let contract = contractsArray[i];
        for (let x = 0; x < tokensArray.length; x++) {
            let token = tokensArray[x];
            let balance = await token.balanceOf(contract);
            let formattedBalance = formatEther(balance);
            let tokenName = await token.name();
            let base, quote, underlying, strike;
            if (tokenName == "Primitive V1 Option") {
                let signer = (await ethers.getSigners())[0];
                base = formatEther(await token.getBaseValue());
                quote = formatEther(await token.getQuoteValue());
                strikeToken = new ethers.Contract(
                    await token.getStrikeTokenAddress(),
                    TestERC20.abi,
                    signer
                );

                underlyingToken = new ethers.Contract(
                    await token.getUnderlyingTokenAddress(),
                    TestERC20.abi,
                    signer
                );

                strike = await strikeToken.symbol();
                underlying = await underlyingToken.symbol();
            }
            let data = {
                contract: name,
                tokenName: tokenName,
                tokenBalance: formattedBalance,
                base: base || "-",
                quote: quote || "-",
                underlying: underlying || "-",
                strike: strike || "-",
            };
            info.balances.push(data);
        }
    }

    return info;
};

Object.assign(module.exports, {
    formatConfigForBalanceReporter,
    newUniswapConnector,
    newSyntheticOption,
    newUniswap,
    newUniswapRinkeby,
    newWallets,
    newERC20,
    newBadERC20,
    newWeth,
    newOption,
    newRedeem,
    newTestRedeem,
    newFlash,
    newTestOption,
    newRegistry,
    newOptionFactory,
    newPrimitive,
    approveToken,
    newTrader,
    newWethConnector,
    setupMultipleContracts,
    batchApproval,
});
