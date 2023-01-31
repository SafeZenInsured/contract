module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    if (chainID != 31337) {
        const BUYSELLSZT_CONTRACT = await ethers.getContract("BuySellSZT")
        const BUYSELLSZT_ADDRESS = BUYSELLSZT_CONTRACT.address

        const GSZT_CONTRACT = await ethers.getContractFactory("GSZT");
        const GSZT = await upgrades.deployProxy(GSZT_CONTRACT, [BUYSELLSZT_ADDRESS], {
            constructorArgs: [], 
        });
        await GSZT.deployed();
        console.log("GSZT Contract Proxy deployed at:", GSZT.address);

        const artifact = await deployments.getExtendedArtifact('GSZT');
        let proxyDeployments = {
            address: GSZT.address,
            ...artifact
        }
        await save('GSZT', proxyDeployments);
        console.log(`GSZT Contract has been deployed on ${GSZT.address} address.`)

    } else {
    }
}

module.exports.tags = ["all", "GSZT"]