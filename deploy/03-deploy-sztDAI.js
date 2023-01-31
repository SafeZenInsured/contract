module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    if (chainID != 31337) {
        const sztDAI_CONTRACT = await ethers.getContractFactory("sztDAI");
        const sztDAI = await upgrades.deployProxy(sztDAI_CONTRACT, [], {
            constructorArgs: [], 
            initializer: "initialize"
        });
        await sztDAI.deployed();
        console.log("sztDAI Proxy deployed at:", sztDAI.address);

        const artifact = await deployments.getExtendedArtifact('sztDAI');
        let proxyDeployments = {
            address: sztDAI.address,
            ...artifact
        }
        await save('sztDAI', proxyDeployments);
        console.log(`szt DAI Contract has been deployed on ${sztDAI.address} address.`)

    } else {
    }
}

module.exports.tags = ["all", "sztDAI"]