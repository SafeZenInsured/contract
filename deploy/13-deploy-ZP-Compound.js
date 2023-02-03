module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments

    const GLOBAL_PAUSE_CONTRACT = await ethers.getContract("GlobalPauseOperation");
    const GLOBAL_PAUSE_ADDRESS = GLOBAL_PAUSE_CONTRACT.address;
    
    const ZP_COMPOUND_CONTRACT = await ethers.getContractFactory("CompoundV2Insurance");
    const ZP_COMPOUND = await upgrades.deployProxy(ZP_COMPOUND_CONTRACT, [GLOBAL_PAUSE_ADDRESS], {
        constructorArgs: [], 
    });
    await ZP_COMPOUND.deployed();
    console.log("CompoundV2Insurance Proxy deployed at:", ZP_COMPOUND.address);

    const artifact = await deployments.getExtendedArtifact('CompoundV2Insurance');
    let proxyDeployments = {
        address: ZP_COMPOUND.address,
        ...artifact
    }
    await save('CompoundV2Insurance', proxyDeployments);
    console.log(`CompoundV2Insurance has been deployed on ${ZP_COMPOUND.address} address.`)

}

module.exports.tags = ["all", "CompoundV2Insurance"]