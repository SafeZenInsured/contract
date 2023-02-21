module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments  

    const GLOBAL_PAUSE_OPS_CONTRACT = await ethers.getContractFactory("GlobalPauseOperation");
    const GLOBAL_PAUSE_OP = await upgrades.deployProxy(GLOBAL_PAUSE_OPS_CONTRACT, [], {
        constructorArgs: [], 
    });
    await GLOBAL_PAUSE_OP.deployed();
    console.log("GlobalPauseOperation Proxy deployed at:", GLOBAL_PAUSE_OP.address);

    const artifact = await deployments.getExtendedArtifact('GlobalPauseOperation');
    let proxyDeployments = {
        address: GLOBAL_PAUSE_OP.address,
        ...artifact
    }
    await save('GlobalPauseOperation', proxyDeployments);
    console.log(`Pause Contract has been deployed on ${GLOBAL_PAUSE_OP.address} address.`)
}

module.exports.tags = ["all", "GlobalPauseOperation"]