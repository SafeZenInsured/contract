module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()

    const GENZ_CONTRACT = await ethers.getContractFactory("GENZ");
    const GENZ = await upgrades.deployProxy(GENZ_CONTRACT, [], {
        constructorArgs: [], 
    });
    await GENZ.deployed();
    console.log("GENZ Proxy deployed at:", GENZ.address);

    const artifact = await deployments.getExtendedArtifact('GENZ');
    let proxyDeployments = {
        address: GENZ.address,
        ...artifact
    }
    await save('GENZ', proxyDeployments);
    console.log(`GENZ Contract has been deployed on ${GENZ.address} address.`)
}

module.exports.tags = ["all", "GENZ"]