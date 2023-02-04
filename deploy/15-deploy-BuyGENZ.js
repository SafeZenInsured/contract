const VALUE = 1
const DECIMALS = 4


module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    const GENZ_CONTRACT = await ethers.getContract("GENZ")
    const GENZ_ADDRESS = GENZ_CONTRACT.address

    const DAI_CONTRACT = await ethers.getContract("MockDAI")
    const DAI_ADDRESS = DAI_CONTRACT.address

    const PAUSE_OP_CONTRACT = await ethers.getContract("GlobalPauseOperation")
    const PAUSE_OP_ADDRESS = PAUSE_OP_CONTRACT.address

    const BUYGENZ_CONTRACT = await ethers.getContractFactory("BuyGENZ");
    const BuyGENZ = await upgrades.deployProxy(BUYGENZ_CONTRACT, [PAUSE_OP_ADDRESS], {
        constructorArgs: [VALUE, DECIMALS, DAI_ADDRESS, GENZ_ADDRESS], 
        unsafeAllow: ['constructor', 'state-variable-immutable'],
    });
    await BuyGENZ.deployed();
    console.log("BuyGENZ Proxy deployed at:", BuyGENZ.address);

    const artifact = await deployments.getExtendedArtifact('BuyGENZ');
    let proxyDeployments = {
        address: BuyGENZ.address,
        ...artifact
    }
    await save('BuyGENZ', proxyDeployments);
    console.log(`BuyGENZ Contract has been deployed on ${BuyGENZ.address} address.`)
}

module.exports.tags = ["all", "BuyGENZ"]