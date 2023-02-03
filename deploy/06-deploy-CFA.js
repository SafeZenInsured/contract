module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()

    if (chainID != 31337) {
        const DAI_CONTRACT = await ethers.getContract("MockDAI")
        const DAI_ADDRESS = DAI_CONTRACT.address

        const sztDAI_CONTRACT = await ethers.getContract("SZTDAI")
        const sztDAI_ADDRESS = sztDAI_CONTRACT.address

        const INSURANCE_REGISTRY_CONTRACT = await ethers.getContract("InsuranceRegistry")
        const INSURANCE_REGISTRY_ADDRESS = INSURANCE_REGISTRY_CONTRACT.address

        const CFA_CONTRACT = await ethers.getContractFactory("ConstantFlowAgreement");
        const CFA = await upgrades.deployProxy(
            CFA_CONTRACT, 
            [DAI_ADDRESS, sztDAI_ADDRESS, INSURANCE_REGISTRY_ADDRESS, 2, 1, 5], 
            {}
        );
        await CFA.deployed();
        console.log("CFA Proxy deployed at:", CFA.address);

        const artifact = await deployments.getExtendedArtifact('ConstantFlowAgreement');
        let proxyDeployments = {
            address: CFA.address,
            ...artifact
        }
        await save('ConstantFlowAgreement', proxyDeployments);
        console.log(`CFA Contract has been deployed on ${CFA.address} address.`)
    } else {

        POLYGON_NETWORK_DAI_ADDRESS = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"

        const sztDAI_CONTRACT = await ethers.getContract("SZTDAI")
        const sztDAI_ADDRESS = sztDAI_CONTRACT.address

        const INSURANCE_REGISTRY_CONTRACT = await ethers.getContract("InsuranceRegistry")
        const INSURANCE_REGISTRY_ADDRESS = INSURANCE_REGISTRY_CONTRACT.address

        const CFA_CONTRACT = await ethers.getContractFactory("ConstantFlowAgreement");
        const CFA = await upgrades.deployProxy(
            CFA_CONTRACT, 
            [POLYGON_NETWORK_DAI_ADDRESS, sztDAI_ADDRESS, INSURANCE_REGISTRY_ADDRESS, 2, 1, 5], 
            {}
        );
        await CFA.deployed();
        console.log("CFA Proxy deployed at:", CFA.address);

        const artifact = await deployments.getExtendedArtifact('ConstantFlowAgreement');
        let proxyDeployments = {
            address: CFA.address,
            ...artifact
        }
        await save('ConstantFlowAgreement', proxyDeployments);
        console.log(`CFA Contract has been deployed on ${CFA.address} address.`)
    }
}

module.exports.tags = ["all", "ConstantFlowAgreement"]