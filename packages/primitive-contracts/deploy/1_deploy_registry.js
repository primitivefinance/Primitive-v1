// We require the Buidler Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
// When running the script with `buidler run <script>` you'll find the Buidler
// Runtime Environment's members available in the global scope.
const bre = require("@nomiclabs/buidler");
const { ethers } = require("@nomiclabs/buidler");

module.exports = async ({ getNamedAccounts, deployments }) => {
    const [signer] = await ethers.getSigners();
    const { log, deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const chain = await bre.getChainId();
    const optionTemplateLib = await deploy("OptionTemplateLib", {
        from: deployer,
        contractName: "OptionTemplateLib",
        args: [],
    });
    const redeemTemplateLib = await deploy("RedeemTemplateLib", {
        from: deployer,
        contractName: "RedeemTemplateLib",
        args: [],
    });

    const registry = await deploy("Registry", {
        from: deployer,
        contractName: "Registry",
        args: [],
    });

    let optionFactory = await deploy("OptionFactory", {
        from: deployer,
        contractName: "OptionFactory",
        args: [registry.address],
        libraries: {
            ["OptionTemplateLib"]: optionTemplateLib.address,
        },
    });

    let redeemFactory = await deploy("RedeemFactory", {
        from: deployer,
        contractName: "RedeemFactory",
        args: [registry.address],
        libraries: {
            ["RedeemTemplateLib"]: redeemTemplateLib.address,
        },
    });

    const opFacInstance = new ethers.Contract(optionFactory.address, optionFactory.abi, signer);
    const reFacInstance = new ethers.Contract(redeemFactory.address, redeemFactory.abi, signer);

    const optionImpAddress = await opFacInstance.optionTemplate();
    const redeemImpAddress = await reFacInstance.redeemTemplate();
    if (optionImpAddress == ethers.constants.AddressZero) {
        await opFacInstance.deployOptionTemplate();
    }
    if (redeemImpAddress == ethers.constants.AddressZero) {
        await reFacInstance.deployRedeemTemplate();
    }

    let deployed = [registry, optionFactory, redeemFactory];
    for (let i = 0; i < deployed.length; i++) {
        if (deployed[i].newlyDeployed)
            log(`Contract deployed at ${deployed[i].address} using ${deployed[i].receipt.gasUsed} gas on chain ${chain}`);
    }
};
