module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    if (chainID != 31337) {
        const ZP_AAVE_CONTRACT = await ethers.getContractFactory("AAVE");
        const ZP_AAVE = await upgrades.deployProxy(ZP_AAVE_CONTRACT, [], {
            constructorArgs: [], 
        });
        await ZP_AAVE.deployed();
        console.log("AAVE Proxy deployed at:", ZP_AAVE.address);

        const artifact = await deployments.getExtendedArtifact('AAVE');
        let proxyDeployments = {
            address: ZP_AAVE.address,
            ...artifact
        }
        await save('AAVE', proxyDeployments);
        console.log(`Pause Contract has been deployed on ${ZP_AAVE.address} address.`)

    } else {
    }
}

module.exports.tags = ["all", "AAVE"]