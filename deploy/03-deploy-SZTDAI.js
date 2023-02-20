module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    const SZTDAI_CONTRACT = await ethers.getContractFactory("SZTDAI");
    const SZTDAI = await upgrades.deployProxy(SZTDAI_CONTRACT, [], {
        constructorArgs: [], 
        initializer: "initialize"
    });
    await SZTDAI.deployed();
    console.log("SZTDAI Proxy deployed at:", SZTDAI.address);

    const artifact = await deployments.getExtendedArtifact('SZTDAI');
    let proxyDeployments = {
        address: SZTDAI.address,
        ...artifact
    }
    await save('SZTDAI', proxyDeployments);
    console.log(`SZTDAI Contract has been deployed on ${SZTDAI.address} address.`)

}

module.exports.tags = ["all", "SZTDAI"]