/// Order of deployments:

/// GlobalPauseOperation, DAI, LUSD, 

/// Init functions contracts:
/// BuySellSZT

module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments

    const chainID = await getChainId()
    if (chainID != 31337) {
        const DAIERC20_CONTRACT = await ethers.getContractFactory("MockDAI");
        const DAI_INSTANCE = await upgrades.deployProxy(
            DAIERC20_CONTRACT, 
            ["MockDAI", "MockDAI"], 
            {initializer: 'initialize'}
        );
        await DAI_INSTANCE.deployed();
        console.log("DAI Proxy deployed at:", DAI_INSTANCE.address);

        const artifact = await deployments.getExtendedArtifact('MockDAI');
        let proxyDeployments = {
            address: DAI_INSTANCE.address,
            ...artifact
        }

        await save('MockDAI', proxyDeployments);
        console.log(`DAI Contract has been deployed on ${DAI_INSTANCE.address} address.`)
    }
}

module.exports.tags = ["all", "MockDAI"]

// const { deploy, log, save } = deployments
// const { deployer } = await getNamedAccounts()
// const LUSD_ERC20_CONTRACT = await deploy("MockDAI", {
//     from: deployer,
//     args: [],
//     log: true
// })