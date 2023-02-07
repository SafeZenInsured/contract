module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments

    const GLOBAL_PAUSE_CONTRACT = await ethers.getContract("GlobalPauseOperation");
    const GLOBAL_PAUSE_ADDRESS = GLOBAL_PAUSE_CONTRACT.address;

    const ZP_AAVE_CONTRACT = await ethers.getContractFactory("AAVEV3Insurance");
    const ZP_AAVE = await upgrades.deployProxy(ZP_AAVE_CONTRACT, [GLOBAL_PAUSE_ADDRESS], {
        constructorArgs: [], 
    });
    await ZP_AAVE.deployed();
    console.log("AAVEV3Insurance Proxy deployed at:", ZP_AAVE.address);

    const artifact = await deployments.getExtendedArtifact('AAVEV3Insurance');
    let proxyDeployments = {
        address: ZP_AAVE.address,
        ...artifact
    }
    await save('AAVEV3Insurance', proxyDeployments);
    console.log(`AAVEV3Insurance Contract has been deployed on ${ZP_AAVE.address} address.`)

}

module.exports.tags = ["all", "AAVEV3Insurance"]