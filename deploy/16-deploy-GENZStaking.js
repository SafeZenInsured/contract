const VALUE = 1
const DECIMALS = 4


module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    const GENZ_CONTRACT = await ethers.getContract("GENZ")
    const GENZ_ADDRESS = GENZ_CONTRACT.address

    const GENZ_STAKING_CONTRACT = await ethers.getContractFactory("GENZStaking");
    const GENZStaking = await upgrades.deployProxy(GENZ_STAKING_CONTRACT, ["5"], {
        constructorArgs: [GENZ_ADDRESS], 
        unsafeAllow: ['constructor', 'state-variable-immutable'],
    });
    await GENZStaking.deployed();
    console.log("GENZStaking Proxy deployed at:", GENZStaking.address);

    const artifact = await deployments.getExtendedArtifact('GENZStaking');
    let proxyDeployments = {
        address: GENZStaking.address,
        ...artifact
    }
    await save('GENZStaking', proxyDeployments);
    console.log(`GENZStaking Contract has been deployed on ${GENZStaking.address} address.`)
}

module.exports.tags = ["all", "GENZStaking"]