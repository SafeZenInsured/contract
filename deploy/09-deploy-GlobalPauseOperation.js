module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments  

    const GLOBAL_PAUSE_CONTRACT = await ethers.getContractFactory("GlobalPauseOperation");
    const GLOBAL_PAUSE = await upgrades.deployProxy(GLOBAL_PAUSE_CONTRACT, [], {
        constructorArgs: [], 
    });
    await GLOBAL_PAUSE.deployed();
    console.log("GlobalPauseOperation Proxy deployed at:", GLOBAL_PAUSE.address);

    const artifact = await deployments.getExtendedArtifact('GlobalPauseOperation');
    let proxyDeployments = {
        address: GLOBAL_PAUSE.address,
        ...artifact
    }
    await save('GlobalPauseOperation', proxyDeployments);
    console.log(`Pause Contract has been deployed on ${GLOBAL_PAUSE.address} address.`)
}

module.exports.tags = ["all", "GlobalPauseOperation"]