module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    if (chainID != 31337) {
        const SMART_CONTRACT_ZP_CONTROLLER_CONTRACT = await ethers.getContractFactory("SmartContractZPController");
        const SMART_CONTRACT_ZP_CONTROLLER = await upgrades.deployProxy(SMART_CONTRACT_ZP_CONTROLLER_CONTRACT, [], {
            constructorArgs: [], 
        });
        await SMART_CONTRACT_ZP_CONTROLLER.deployed();
        console.log("SmartContractZPController Proxy deployed at:", SMART_CONTRACT_ZP_CONTROLLER.address);

        const artifact = await deployments.getExtendedArtifact('SmartContractZPController');
        let proxyDeployments = {
            address: SMART_CONTRACT_ZP_CONTROLLER.address,
            ...artifact
        }
        await save('SmartContractZPController', proxyDeployments);
        console.log(`Pause Contract has been deployed on ${SMART_CONTRACT_ZP_CONTROLLER.address} address.`)

    } else {
    }
}

module.exports.tags = ["all", "SmartContractZPController"]