module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
    const { deploy, log, save } = deployments
    const { deployer } = await getNamedAccounts()
    const chainID = await getChainId()

    if (chainID != 31337) {
        const DAI_CONTRACT = await ethers.getContract("MockDAI")
        const DAI_ADDRESS = DAI_CONTRACT.address

        const SZTDAI_TOKEN_CONTRACT = await ethers.getContract("SZTDAI")
        const SZTDAI_TOKEN_ADDRESS = SZTDAI_TOKEN_CONTRACT.address

        const SWAPDAI_CONTRACT = await ethers.getContractFactory("SwapDAI");
        const SWAPDAI = await upgrades.deployProxy(
            SWAPDAI_CONTRACT, 
            [], 
            {
                constructorArgs: [DAI_ADDRESS, SZTDAI_TOKEN_ADDRESS], 
                unsafeAllow: ['constructor', 'state-variable-immutable'],
            }
        );

        await SWAPDAI.deployed();
        console.log("Swap DAI Contract Proxy deployed at:", SWAPDAI.address);

        const artifact = await deployments.getExtendedArtifact('SwapDAI');
        let proxyDeployments = {
            address: SWAPDAI.address,
            ...artifact
        }
        await save('SwapDAI', proxyDeployments);
        console.log(`Swap DAI Contract has been deployed on ${SWAPDAI.address} address.`);
    } else {
        POLYGON_NETWORK_DAI_ADDRESS = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"

        const SZTDAI_TOKEN_CONTRACT = await ethers.getContract("SZTDAI")
        const SZTDAI_TOKEN_ADDRESS = SZTDAI_TOKEN_CONTRACT.address

        const SWAPDAI_CONTRACT = await ethers.getContractFactory("SwapDAI");
        const SWAPDAI = await upgrades.deployProxy(
            SWAPDAI_CONTRACT, 
            [], 
            {
                constructorArgs: [POLYGON_NETWORK_DAI_ADDRESS, SZTDAI_TOKEN_ADDRESS], 
                unsafeAllow: ['constructor', 'state-variable-immutable'],
            }
        );

        await SWAPDAI.deployed();
        console.log("Swap DAI Contract Proxy deployed at:", SWAPDAI.address);

        const artifact = await deployments.getExtendedArtifact('SwapDAI');
        let proxyDeployments = {
            address: SWAPDAI.address,
            ...artifact
        }
        await save('SwapDAI', proxyDeployments);
        console.log(`Swap DAI Contract has been deployed on ${SWAPDAI.address} address.`);
    }
    
}

module.exports.tags = ["all", "SwapDAI"]