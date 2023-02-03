module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    const BUYSELLSZT_CONTRACT = await ethers.getContract("BuySellSZT")
    const BUYSELLSZT_ADDRESS = BUYSELLSZT_CONTRACT.address

    const SZT_CONTRACT = await ethers.getContractFactory("SZT");
    const SZT = await upgrades.deployProxy(SZT_CONTRACT, [BUYSELLSZT_ADDRESS], {
        constructorArgs: [], 
    });
    await SZT.deployed();
    console.log("SZT Proxy deployed at:", SZT.address);

    const artifact = await deployments.getExtendedArtifact('SZT');
    let proxyDeployments = {
        address: SZT.address,
        ...artifact
    }
    await save('SZT', proxyDeployments);
    console.log(`SZT Contract has been deployed on ${SZT.address} address.`)
}

module.exports.tags = ["all", "SZT"]