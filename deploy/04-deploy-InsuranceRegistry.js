module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    if (chainID != 31337) {
        
        const BUYSELLSZT_CONTRACT = await ethers.getContract("BuySellSZT")
        const BUYSELLSZT_ADDRESS = BUYSELLSZT_CONTRACT.address

        const DAI_CONTRACT = await ethers.getContract("MockDAI")
        const DAI_ADDRESS = DAI_CONTRACT.address

        const SZT_CONTRACT = await ethers.getContract("SZT")
        const SZT_ADDRESS = SZT_CONTRACT.address

        const INSURANCE_REGISTRY_CONTRACT = await ethers.getContractFactory("InsuranceRegistry");
        const INSURANCE_REGISTRY = await upgrades.deployProxy(
            INSURANCE_REGISTRY_CONTRACT, 
            [
                BUYSELLSZT_ADDRESS, DAI_ADDRESS, SZT_ADDRESS
            ], {
            constructorArgs: [], 
        });
        await INSURANCE_REGISTRY.deployed();
        console.log("Insurance Registry Proxy deployed at:", INSURANCE_REGISTRY.address);

        const artifact = await deployments.getExtendedArtifact('InsuranceRegistry');
        let proxyDeployments = {
            address: INSURANCE_REGISTRY.address,
            ...artifact
        }
        await save('InsuranceRegistry', proxyDeployments);
        console.log(`Insurance Registry Contract has been deployed on ${INSURANCE_REGISTRY.address} address.`)

    } else {
        const BUYSELLSZT_CONTRACT = await ethers.getContract("BuySellSZT")
        const BUYSELLSZT_ADDRESS = BUYSELLSZT_CONTRACT.address

        POLYGON_NETWORK_DAI_ADDRESS = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"

        const SZT_CONTRACT = await ethers.getContract("SZT")
        const SZT_ADDRESS = SZT_CONTRACT.address

        const INSURANCE_REGISTRY_CONTRACT = await ethers.getContractFactory("InsuranceRegistry");
        const INSURANCE_REGISTRY = await upgrades.deployProxy(
            INSURANCE_REGISTRY_CONTRACT, 
            [
                BUYSELLSZT_ADDRESS, POLYGON_NETWORK_DAI_ADDRESS, SZT_ADDRESS
            ], {
            constructorArgs: [], 
        });
        await INSURANCE_REGISTRY.deployed();
        console.log("Insurance Registry Proxy deployed at:", INSURANCE_REGISTRY.address);

        const artifact = await deployments.getExtendedArtifact('InsuranceRegistry');
        let proxyDeployments = {
            address: INSURANCE_REGISTRY.address,
            ...artifact
        }
        await save('InsuranceRegistry', proxyDeployments);
        console.log(`Insurance Registry Contract has been deployed on ${INSURANCE_REGISTRY.address} address.`)

    }
}

module.exports.tags = ["all", "InsuranceRegistry"]