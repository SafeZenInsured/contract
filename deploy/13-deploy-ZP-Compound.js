const XVS_TESTNET = "0xB9e0E753630434d7863528cc73CB7AC638a7c8ff"

module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments

    const GLOBAL_PAUSE_CONTRACT = await ethers.getContract("GlobalPauseOperation");
    const GLOBAL_PAUSE_ADDRESS = GLOBAL_PAUSE_CONTRACT.address;
    
    const ZP_COMPOUND_CONTRACT = await ethers.getContractFactory("CompoundV2Insurance");
    const ZP_COMPOUND = await upgrades.deployProxy(ZP_COMPOUND_CONTRACT, [GLOBAL_PAUSE_ADDRESS, XVS_TESTNET], {
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