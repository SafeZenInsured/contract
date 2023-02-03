module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    if (chainID != 31337) {
        const INSURANCE_REGISTRY_CONTRACT = await ethers.getContract("InsuranceRegistry")
        const INSURANCE_REGISTRY_ADDRESS = INSURANCE_REGISTRY_CONTRACT.address

        const SZT_CONTRACT = await ethers.getContract("SZT")
        const SZT_ADDRESS = SZT_CONTRACT.address

        const DAI_CONTRACT = await ethers.getContract("MockDAI")
        const DAI_ADDRESS = DAI_CONTRACT.address

        const BUYSELLSZT_CONTRACT = await ethers.getContract("BuySellSZT")
        const BUYSELLSZT_ADDRESS = BUYSELLSZT_CONTRACT.address

        const COVERAGE_POOL_CONTRACT = await ethers.getContractFactory("CoveragePool");
        const COVERAGE_POOL_REGISTRY = await upgrades.deployProxy(
            COVERAGE_POOL_CONTRACT, 
            [INSURANCE_REGISTRY_ADDRESS], 
            {
                constructorArgs: [SZT_ADDRESS, BUYSELLSZT_ADDRESS, DAI_ADDRESS], 
                unsafeAllow: ['constructor', 'state-variable-immutable'],
            }
        );
        await COVERAGE_POOL_REGISTRY.deployed();
        console.log("Coverage Pool Proxy deployed at:", COVERAGE_POOL_REGISTRY.address);

        const artifact = await deployments.getExtendedArtifact('CoveragePool');
        let proxyDeployments = {
            address: COVERAGE_POOL_REGISTRY.address,
            ...artifact
        }
        await save('CoveragePool', proxyDeployments);
        console.log(`Coverage Pool Contract has been deployed on ${COVERAGE_POOL_REGISTRY.address} address.`)

    } else {
        const INSURANCE_REGISTRY_CONTRACT = await ethers.getContract("InsuranceRegistry")
        const INSURANCE_REGISTRY_ADDRESS = INSURANCE_REGISTRY_CONTRACT.address

        const SZT_CONTRACT = await ethers.getContract("SZT")
        const SZT_ADDRESS = SZT_CONTRACT.address

        POLYGON_NETWORK_DAI_ADDRESS = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"

        const BUYSELLSZT_CONTRACT = await ethers.getContract("BuySellSZT")
        const BUYSELLSZT_ADDRESS = BUYSELLSZT_CONTRACT.address

        const COVERAGE_POOL_CONTRACT = await ethers.getContractFactory("CoveragePool");
        const COVERAGE_POOL_REGISTRY = await upgrades.deployProxy(
            COVERAGE_POOL_CONTRACT, 
            [INSURANCE_REGISTRY_ADDRESS], 
            {
                constructorArgs: [SZT_ADDRESS, BUYSELLSZT_ADDRESS, POLYGON_NETWORK_DAI_ADDRESS], 
                unsafeAllow: ['constructor', 'state-variable-immutable'],
            }
        );
        await COVERAGE_POOL_REGISTRY.deployed();
        console.log("Coverage Pool Proxy deployed at:", COVERAGE_POOL_REGISTRY.address);

        const artifact = await deployments.getExtendedArtifact('CoveragePool');
        let proxyDeployments = {
            address: COVERAGE_POOL_REGISTRY.address,
            ...artifact
        }
        await save('CoveragePool', proxyDeployments);
        console.log(`Coverage Pool Contract has been deployed on ${COVERAGE_POOL_REGISTRY.address} address.`)
    }
}

module.exports.tags = ["all", "CoveragePool"]
